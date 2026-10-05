"""Repair text files damaged by reading UTF-8 as Windows-1252.

This is the failure mode of `Get-Content -Raw` without `-Encoding utf8` in
Windows PowerShell 5.1: it decodes a UTF-8 file as CP1252, and writing it back as
UTF-8 double-encodes every non-ASCII character. The damage is fully reversible
because the transform is lossless in that direction.

Run:
  python tools/repair_encoding.py <file> [<file> ...]
  python tools/repair_encoding.py --all      (every text file in the patch layer)
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Characters that only appear once UTF-8 bytes have been read as CP1252. Written
# as escapes on purpose: spelled out literally, this file would itself contain the
# sequences that tools/verify_encoding.py looks for.
MOJIBAKE_MARKERS = ("\u00d0", "\u00d1", "\u00e2\u20ac", "\u00c3", "\u00c2")

TEXT_SUFFIXES = {".swift", ".py", ".md", ".sql", ".sh", ".yml", ".yaml", ".txt", ".patch", ".json"}
SKIP_DIRS = {".git", "node_modules", "__pycache__"}


def cp1252_reverse_table():
    """Character -> byte, the inverse of how .NET decodes Windows-1252.

    Python's cp1252 codec raises on the five undefined bytes (0x81, 0x8D, 0x8F,
    0x90, 0x9D) where .NET maps them to the matching C1 control character, so those
    are added explicitly. Without this, a file containing one such byte cannot be
    repaired at all.
    """
    table = {}
    for byte in range(256):
        try:
            character = bytes([byte]).decode("cp1252")
        except UnicodeDecodeError:
            character = chr(byte)
        table[character] = byte
    return table


CP1252_REVERSE = cp1252_reverse_table()


def repair(path):
    raw = path.read_bytes()
    text = raw.decode("utf-8", errors="strict")

    had_bom = text.startswith("\ufeff")
    if had_bom:
        text = text[1:]

    markers = [m for m in MOJIBAKE_MARKERS if m in text]
    repaired = text
    if markers:
        try:
            original_bytes = bytes(CP1252_REVERSE[character] for character in text)
            repaired = original_bytes.decode("utf-8")
        except (KeyError, UnicodeDecodeError) as error:
            print(f"[FAIL] {path.name}: cannot reverse the damage ({error})")
            return False

    # The repository convention is UTF-8 without BOM and LF endings.
    normalised = repaired.replace("\r\n", "\n")
    changed = had_bom or bool(markers) or normalised != text

    if changed:
        path.write_bytes(normalised.encode("utf-8"))
        print(f"[FIXED] {path.name}: bom={had_bom} markers={markers}")

    return True


def text_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def main():
    arguments = sys.argv[1:]
    if not arguments:
        print(__doc__)
        return 1

    if arguments == ["--all"]:
        files = list(text_files())
    else:
        files = [Path(argument) for argument in arguments]

    failures = 0
    for path in files:
        if not path.exists():
            print(f"[FAIL] not found: {path}")
            failures += 1
            continue
        if not repair(path):
            failures += 1

    if failures:
        print(f"RESULT: {failures} FAILED")
        return 1
    print(f"RESULT: {len(files)} file(s) checked")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

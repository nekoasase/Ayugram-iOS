"""Fail if a shipped text file is not clean UTF-8 without BOM.

This exists because the same mistake was made twice: editing a file with
`Get-Content -Raw` / `Set-Content` in Windows PowerShell 5.1, which decodes UTF-8
as Windows-1252 and double-encodes every non-ASCII character. The result is
mojibake that is still valid UTF-8, so nothing else notices — the code compiles,
the checks pass, and the documentation is quietly unreadable.

The rule for this repository: text files are UTF-8 without a BOM, with LF endings.

Run:  python tools/verify_encoding.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Only appear after UTF-8 bytes have been read as Windows-1252. A legitimate
# document could contain "\u00c2" in isolation, so a two-character sequence is
# required rather than a single character. Written as escapes on purpose: spelled
# out literally, this file would contain the very sequences it looks for.
MOJIBAKE_SEQUENCES = (
    "\u00d0\u00b0", "\u00d0\u00b5", "\u00d0\u00b8", "\u00d1\u20ac",
    "\u00d1\u201a", "\u00e2\u20ac", "\u00d0\u00be", "\u00d0\u00bd",
)

TEXT_SUFFIXES = {".swift", ".py", ".md", ".sql", ".sh", ".yml", ".yaml", ".txt", ".patch", ".json"}
SKIP_DIRS = {".git", "node_modules", "__pycache__"}

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def text_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def main():
    files = list(text_files())
    check("text files found", bool(files), f"{len(files)} files")
    if not files:
        return 1

    mojibake = []
    boms = []
    crlf = []
    undecodable = []

    for path in files:
        raw = path.read_bytes()
        if raw[:3] == b"\xef\xbb\xbf":
            boms.append(path.relative_to(ROOT).as_posix())
            raw = raw[3:]
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            undecodable.append(path.relative_to(ROOT).as_posix())
            continue
        if any(sequence in text for sequence in MOJIBAKE_SEQUENCES):
            mojibake.append(path.relative_to(ROOT).as_posix())
        if b"\r\n" in raw:
            crlf.append(path.relative_to(ROOT).as_posix())

    check("every file decodes as UTF-8", not undecodable, str(undecodable[:5]))
    check("no file contains double-encoded text", not mojibake,
          f"{mojibake[:5]}" if mojibake else "")
    check("no file starts with a BOM", not boms, str(boms[:5]))
    check("all files use LF endings", not crlf, str(crlf[:5]))

    # The repair tool must stay able to fix what this check detects.
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import repair_encoding

        sample = "\u043a\u0430\u0440\u0442\u0430 \u2014 \u0442\u0435\u0441\u0442"
        # Reproduce the damage exactly as .NET does, including the bytes CP1252
        # leaves undefined (they become C1 controls there, and Python's codec
        # would otherwise need errors="replace" and lose them).
        forward = {byte: character for character, byte in repair_encoding.CP1252_REVERSE.items()}
        damaged = "".join(forward[byte] for byte in sample.encode("utf-8"))
        restored = bytes(
            repair_encoding.CP1252_REVERSE[character] for character in damaged
        ).decode("utf-8")
        check("the repair tool reverses the damage it reports", restored == sample,
              f"{restored!r}")
    except Exception as error:  # noqa: BLE001 - report anything that breaks
        check("the repair tool reverses the damage it reports", False, str(error))

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print(f"RESULT: {len(files)} file(s) are clean UTF-8 with LF endings")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

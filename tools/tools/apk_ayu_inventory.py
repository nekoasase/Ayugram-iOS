"""Inventory of AyuGram feature surface, extracted from the release APK.

Reads every classes*.dex string pool and groups identifiers that belong to the
AyuGram / exteraGram patch layer, so the iOS port can be driven by facts
instead of guesses.
"""
import struct
import sys
import zipfile
from collections import defaultdict

APK = r"C:\Users\neko_asase\Downloads\vanilla-ayuGram-universal-20250101.apk"
DEX = ["classes.dex", "classes2.dex", "classes3.dex", "classes4.dex", "classes5.dex"]


def dex_strings(data):
    """Yield every string from a dex file's string pool."""
    string_ids_size, string_ids_off = struct.unpack_from("<II", data, 0x38)
    for i in range(string_ids_size):
        off = struct.unpack_from("<I", data, string_ids_off + 4 * i)[0]
        p = off
        while data[p] & 0x80:  # uleb128 utf16 length
            p += 1
        p += 1
        end = data.index(b"\x00", p)
        yield data[p:end].decode("utf-8", "ignore")


GROUPS = {
    "AyuGram classes": lambda s: s.startswith("Lcom/radolyn/ayugram/"),
    "AyuGram db entities": lambda s: "database/entities/" in s,
    "AyuGram db daos": lambda s: "database/dao/" in s,
    "exteraGram classes": lambda s: s.startswith("Lcom/exteragram/") or s.startswith("Ltw/neko/"),
    "Ghost mode keys": lambda s: "Ghost" in s or "ghost" in s,
    "Deleted/edited message": lambda s: ("Deleted" in s or "Edited" in s) and len(s) < 60,
    "Spy / read receipts": lambda s: "Spy" in s or "spy" in s,
    "Regex filters": lambda s: "Regex" in s or "regex" in s,
    "Adblock": lambda s: "adblock" in s.lower() or "AdBlock" in s,
    "Transcription": lambda s: "Transcri" in s or "transcri" in s,
    "Settings keys": lambda s: s.startswith("ayu_") or s.startswith("extera_") or s.startswith("ghost_"),
}


def main():
    zf = zipfile.ZipFile(APK)
    all_strings = set()
    for name in DEX:
        all_strings.update(dex_strings(zf.read(name)))

    found = defaultdict(set)
    for s in all_strings:
        for group, pred in GROUPS.items():
            try:
                if pred(s):
                    found[group].add(s)
            except Exception:
                pass

    print(f"APK: {APK}")
    print(f"dex files: {len(DEX)}, distinct strings: {len(all_strings)}\n")
    for group in GROUPS:
        items = sorted(found[group])
        print(f"===== {group} ({len(items)}) =====")
        for s in items:
            print("   ", s)
        print()

    # Full AyuGram class list, deduplicated, is the port checklist.
    classes = sorted(s for s in found["AyuGram classes"])
    print(f"===== PORT CHECKLIST: {len(classes)} AyuGram classes =====")
    for c in classes:
        print(c)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()

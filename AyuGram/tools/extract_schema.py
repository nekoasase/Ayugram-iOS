"""Extract the exact SQL schema of every AyuGram table from the release APK.

Room stores generated DDL as plain strings in the dex, so the CREATE TABLE /
CREATE INDEX statements can be lifted verbatim instead of reverse engineered.
Output is a runnable schema.sql.
"""
import re
import struct
import sys
import zipfile
from collections import OrderedDict

APK = r"C:\Users\neko_asase\Downloads\vanilla-ayuGram-universal-20250101.apk"
DEX = ["classes.dex", "classes2.dex", "classes3.dex", "classes4.dex", "classes5.dex"]

# Tables that belong to the AyuGram patch layer (from the DEX inventory).
AYU_TABLES = [
    "DeletedMessage",
    "DeletedMessageFull",
    "DeletedMessageReaction",
    "DeletedDialog",
    "EditedMessage",
    "SpyMessageRead",
    "SpyMessageContentsRead",
    "RegexFilter",
    "RegexFilterGlobalExclusion",
]


def dex_strings(data):
    string_ids_size, string_ids_off = struct.unpack_from("<II", data, 0x38)
    for i in range(string_ids_size):
        off = struct.unpack_from("<I", data, string_ids_off + 4 * i)[0]
        p = off
        while data[p] & 0x80:
            p += 1
        p += 1
        end = data.index(b"\x00", p)
        yield data[p:end].decode("utf-8", "ignore")


def main():
    zf = zipfile.ZipFile(APK)
    strings = set()
    for name in DEX:
        strings.update(dex_strings(zf.read(name)))

    ddl_prefixes = ("CREATE TABLE", "CREATE UNIQUE INDEX", "CREATE INDEX", "ALTER TABLE", "DROP TABLE")
    ddl = sorted(s for s in strings if s.startswith(ddl_prefixes) and s.endswith(")") or
                 (s.startswith(("CREATE INDEX", "CREATE UNIQUE INDEX", "DROP TABLE", "ALTER TABLE"))))

    # Keep only statements touching AyuGram tables.
    keep = []
    for s in ddl:
        if any(t in s for t in AYU_TABLES):
            keep.append(s)
    keep = sorted(set(keep))

    print("-- AyuGram iOS: schema extracted verbatim from vanilla-ayuGram APK")
    print("-- Source: com.radolyn.ayugram (AyuDatabase), tables of the patch layer")
    print("-- Do not edit by hand: regenerate with tools/extract_schema.py\n")

    for table in AYU_TABLES:
        stmts = [s for s in keep
                 if re.search(rf"\b{re.escape(table)}\b", s)
                 and not re.search(r"_new_|_Impl|AyuDatabase", s)]
        # CREATE TABLE for this table first, then its indexes.
        creates = [s for s in stmts if s.startswith("CREATE TABLE") and f"`{table}`" in s]
        idx = [s for s in stmts if s.startswith("CREATE") and "INDEX" in s]
        if not creates:
            print(f"-- !! no CREATE TABLE captured for {table}\n")
            continue
        print(f"-- ---------- {table} ----------")
        for s in creates + idx:
            print(s + ";")
        print()

    print(f"-- total statements captured: {len(keep)}", file=sys.stderr)
    print("-- ================= raw statement dump =================")
    for s in keep:
        print(s + ";")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()

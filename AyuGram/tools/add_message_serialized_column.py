"""Add the iOS-only `messageSerialized` column to the archive schema.

The schema recovered from the APK has 35 columns for a message snapshot, sized
for Android's `TLRPC` serialisation. Reconstructing a Telegram-iOS `Message`
from those columns would be lossy (media, reply, text entities, attributes), so
the iOS side stores the whole encoded message in one additional BLOB and keeps
the Android columns for the fields that map cleanly.

Rows imported from an Android archive simply have this column NULL; see
`AyuAndroidImporter`.

Idempotent and self-repairing: it rebuilds the column list from scratch, so a
previously broken insertion is fixed and a second run reports no change.
"""
import re
import sys
from pathlib import Path

SCHEMA = Path(__file__).resolve().parent.parent / "Database" / "Schema" / "schema.sql"

# Both snapshot tables must stay identical: one generic record serves them, and
# tools/gen_swift_dao.py fails if their column sets differ.
TABLES = ["DeletedMessage", "EditedMessage"]

COLUMN_NAME = "messageSerialized"
COLUMN_TYPE = "BLOB"

# Type column starts at the same offset as in the surrounding DDL.
TYPE_COLUMN = 35


def column_line(name: str, type_name: str, trailing_comma: bool) -> str:
    prefix = f"    `{name}`"
    padding = " " * max(1, TYPE_COLUMN - len(prefix))
    return f"{prefix}{padding}{type_name}{',' if trailing_comma else ''}"


def desired_body(block: str, table: str) -> str:
    """The block body with exactly one trailing `messageSerialized` column."""
    lines = [line for line in block.split("\n") if f"`{COLUMN_NAME}`" not in line]

    # Drop trailing blank lines; the caller re-adds the closing newline.
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        raise SystemExit(f"{table}: empty block")

    lines[-1] = lines[-1].rstrip()
    if lines[-1].endswith(","):
        lines[-1] = lines[-1][:-1]

    lines[-1] = lines[-1] + ","
    lines.append(column_line(COLUMN_NAME, COLUMN_TYPE, trailing_comma=False))
    return "\n".join(lines)


def main():
    text = SCHEMA.read_text(encoding="utf-8")
    changed_any = False

    for table in TABLES:
        pattern = re.compile(
            r"(CREATE TABLE IF NOT EXISTS `%s` \(\n)(.*?)(\n\);)" % re.escape(table),
            re.S,
        )
        match = pattern.search(text)
        if not match:
            print(f"ERROR: CREATE TABLE block not found for {table}", file=sys.stderr)
            return 1

        current = match.group(2)
        desired = desired_body(current, table)
        if current == desired:
            print(f"already correct: {table}")
            continue

        text = text[: match.start()] + match.group(1) + desired + match.group(3) + text[match.end():]
        changed_any = True
        print(f"updated `{COLUMN_NAME}` in {table}")

    if changed_any:
        SCHEMA.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {SCHEMA}")
    else:
        print("nothing to do")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

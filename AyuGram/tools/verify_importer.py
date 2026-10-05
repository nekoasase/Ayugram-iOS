"""Verify the Android -> iOS database importer actually upgrades an old schema.

The SQL under test is not duplicated here: it is parsed out of the shipped
Swift file (AyuGram/Database/AyuDatabase.swift), so this exercises the real
strings and the real ordering contract the app will use.

What is proven:
  1. A database in the pre-migration shape (missing the columns the Android
     ALTERs add, RegexFilter still on an INTEGER `fakeId` primary key) reaches
     the exact final column set of schema.sql.
  2. Existing user data survives, including the RegexFilter table rebuild.
  3. `upgrade()` is idempotent: a second run changes nothing.
  4. The ordering of the RegexFilter rebuild vs. the `reversed` column matters.
     This script caught the original bug where `reversed` was added before the
     rebuild and was therefore silently dropped.

Run:  python tools/verify_importer.py
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Database" / "AyuDatabase.swift"
SCHEMA = ROOT / "Database" / "Schema" / "schema.sql"

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


# --------------------------------------------------------------------------
# Parse the Swift declarations (the SQL we actually ship)
# --------------------------------------------------------------------------

def swift_array_body(source: str, name: str, kind: str):
    marker = f"static let {name}: [{kind}] = ["
    start = source.index(marker) + len(marker)
    depth, end = 0, len(source)
    for i in range(start, len(source)):
        if source[i] == "[":
            depth += 1
        elif source[i] == "]":
            if depth == 0:
                end = i
                break
            depth -= 1
    return source[start:end]


def unquote(literals):
    def one(lit):
        return lit.replace('\\"', '"').replace("\\\\", "\\")
    return "".join(one(l) for l in literals)


def parse_string_array(source: str, name: str):
    body = swift_array_body(source, name, "String")
    items, current = [], None
    for line in body.splitlines():
        line = line.strip()
        if not line:
            continue
        continuation = line.startswith("+")
        text = unquote(re.findall(r'"((?:[^"\\]|\\.)*)"', line))
        if continuation and current is not None:
            current += text
        else:
            if current is not None:
                items.append(current)
            current = text
    if current is not None:
        items.append(current)
    return [i for i in items if i.strip()]


def parse_tuple_array(source: str, name: str):
    """Parse `[(table: String, column: String, statement: String)]`."""
    body = swift_array_body(source, name, "(table: String, column: String, statement: String)")
    flat = " ".join(body.split())
    pattern = re.compile(
        r'\(\s*"([A-Za-z_]+)"\s*,\s*"([A-Za-z_]+)"\s*,\s*'
        r'((?:"(?:[^"\\]|\\.)*"\s*(?:\+\s*)?)+)\)'
    )
    out = []
    for m in pattern.finditer(flat):
        table, column, raw = m.group(1), m.group(2), m.group(3)
        sql = unquote(re.findall(r'"((?:[^"\\]|\\.)*)"', raw))
        out.append((table, column, sql))
    return out


# --------------------------------------------------------------------------
# Parse schema.sql into per-table DDL
# --------------------------------------------------------------------------

def split_top_level(text: str):
    parts, depth, buf = [], 0, ""
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(buf.strip())
            buf = ""
        else:
            buf += ch
    if buf.strip():
        parts.append(buf.strip())
    return parts


def parse_schema():
    sql = SCHEMA.read_text(encoding="utf-8")
    body = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    tables, indexes = {}, []
    for stmt in (s.strip() for s in body.split(";")):
        if not stmt:
            continue
        if stmt.startswith("CREATE TABLE"):
            name = re.search(r"`([A-Za-z_]+)`\s*\(", stmt).group(1)
            inner = stmt[stmt.index("(") + 1: stmt.rindex(")")]
            tables[name] = split_top_level(inner)
        elif "INDEX" in stmt:
            indexes.append(stmt)
    return tables, indexes


def column_name(clause):
    """Return the column a DDL clause defines, or None for table constraints."""
    clause = clause.strip()
    if clause.upper().startswith("PRIMARY KEY"):
        inner = re.search(r"\(\s*`([A-Za-z_]+)`\s*\)", clause)
        return inner.group(1) if inner else None
    if clause.upper().startswith(("FOREIGN KEY", "UNIQUE", "CHECK", "CONSTRAINT")):
        return None
    m = re.match(r"`?([A-Za-z_]+)`?", clause)
    return m.group(1) if m else None


def table_columns(columns):
    return {c for c in (column_name(x) for x in columns) if c}


def create_table(name, columns):
    return f"CREATE TABLE IF NOT EXISTS `{name}` ({', '.join(columns)})"


def drop_columns(columns, dropped):
    return [c for c in columns if column_name(c) not in dropped]


OLD_REGEX_FILTER = ("CREATE TABLE IF NOT EXISTS `RegexFilter` (`fakeId` INTEGER PRIMARY KEY "
                    "AUTOINCREMENT NOT NULL, `text` TEXT, `enabled` INTEGER NOT NULL, "
                    "`caseInsensitive` INTEGER NOT NULL, `dialogId` INTEGER)")

ADDED_COLUMNS = {
    "DeletedDialog": {"folderId"},
    "DeletedMessage": {"postAuthor", "replySerialized", "replyMarkupSerialized"},
    "EditedMessage": {"postAuthor", "replySerialized", "replyMarkupSerialized"},
}


def columns_of(db, table):
    return {r[1] for r in db.execute(f"PRAGMA table_info(`{table}`)")}


def upgrade(db, pre, rebuild, post):
    """Mirror of AyuAndroidImporter.upgrade(_:) — same order, same guards."""
    def apply(additions):
        for table, column, sql in additions:
            if column not in columns_of(db, table):
                db.execute(sql)

    apply(pre)
    cols = columns_of(db, "RegexFilter")
    if "fakeId" in cols and "id" not in cols:
        for stmt in rebuild:
            db.execute(stmt)
    apply(post)


def main():
    swift = SWIFT.read_text(encoding="utf-8")
    pre = parse_tuple_array(swift, "preRebuildAdditions")
    post = parse_tuple_array(swift, "postRebuildAdditions")
    rebuild = parse_string_array(swift, "regexFilterRebuildStatements")

    print(f"parsed from Swift: {len(pre)} pre-rebuild additions, "
          f"{len(rebuild)} rebuild statements, {len(post)} post-rebuild additions")
    check("parsed pre-rebuild additions", len(pre) == 7, f"got {len(pre)}")
    check("parsed rebuild statements", len(rebuild) == 4, f"got {len(rebuild)}")
    check("parsed post-rebuild additions", len(post) == 1, f"got {len(post)}")
    print()

    tables, indexes = parse_schema()

    db = sqlite3.connect(":memory:")

    # --- build the pre-migration (old) database ----------------------------
    for name, columns in tables.items():
        if name == "RegexFilter":
            db.execute(OLD_REGEX_FILTER)
        else:
            db.execute(create_table(name, drop_columns(columns, ADDED_COLUMNS.get(name, set()))))
    for stmt in indexes:
        if "RegexFilter" in stmt:  # that index does not exist in the old shape
            continue
        db.execute(stmt)

    check("old schema lacks postAuthor", "postAuthor" not in columns_of(db, "DeletedMessage"))
    rf_before = columns_of(db, "RegexFilter")
    check("old schema RegexFilter uses fakeId PK", "fakeId" in rf_before and "id" not in rf_before,
          str(sorted(rf_before)))

    # --- seed user data that must survive ----------------------------------
    db.execute("INSERT INTO `DeletedMessage` (`userId`,`dialogId`,`peerId`,`fromId`,`topicId`,"
               "`messageId`,`date`,`flags`,`editDate`,`views`,`fwdFlags`,`fwdFromId`,`fwdDate`,"
               "`replyFlags`,`replyMessageId`,`replyPeerId`,`replyTopId`,`replyForumTopic`,"
               "`groupedId`,`entityCreateDate`,`text`,`documentType`) "
               "VALUES (1,-1001234567890,-1001234567890,555,0,4242,1700000000000,0,0,7,0,0,0,"
               "0,0,0,0,0,0,1700000000000,'секретное сообщение',0)")
    db.execute("INSERT INTO `RegexFilter` (`text`,`enabled`,`caseInsensitive`,`dialogId`) "
               "VALUES (?,1,1,NULL)", (r"\bспам\b",))
    db.execute("INSERT INTO `RegexFilter` (`text`,`enabled`,`caseInsensitive`,`dialogId`) "
               "VALUES (?,0,1,-1001234567890)", ("реклама",))
    db.execute("INSERT INTO `DeletedDialog` (`userId`,`dialogId`,`peerId`,`topMessage`,"
               "`lastMessageDate`,`flags`,`entityCreateDate`) VALUES (1,-1001234567890,"
               "-1001234567890,4242,1700000000000,0,1700000000000)")

    # --- run the importer (guarded, ordered) -------------------------------
    try:
        upgrade(db, pre, rebuild, post)
        check("importer runs without error", True)
    except sqlite3.Error as exc:
        check("importer runs without error", False, str(exc))

    # --- compare against the final, verified schema ------------------------
    for name, columns in tables.items():
        expected = table_columns(columns)
        actual = columns_of(db, name)
        check(f"{name}: column set after import == schema.sql", expected == actual,
              "" if expected == actual else f"missing={sorted(expected - actual)} "
                                            f"extra={sorted(actual - expected)}")

    # --- data survival -----------------------------------------------------
    text, views = db.execute("SELECT `text`, `views` FROM `DeletedMessage` "
                             "WHERE `messageId`=4242").fetchone()
    check("deleted message survived with its content",
          text == "секретное сообщение" and views == 7, f"text={text!r} views={views}")

    rows = db.execute("SELECT `text`, `enabled` FROM `RegexFilter` ORDER BY `enabled` DESC").fetchall()
    check("both regex filters preserved through table rebuild", len(rows) == 2, str(rows))
    check("filter text intact after rebuild",
          {r[0] for r in rows} == {r"\bспам\b", "реклама"}, str(rows))
    new_ids = [r[0] for r in db.execute("SELECT `id` FROM `RegexFilter`")]
    check("rebuild generated a BLOB id for every filter",
          all(isinstance(i, bytes) and len(i) == 16 for i in new_ids), str(new_ids))
    rev = db.execute("SELECT `reversed` FROM `RegexFilter`").fetchall()
    check("reversed column present after rebuild (ordering contract)",
          all(r[0] == 0 for r in rev), str(rev))

    folder = db.execute("SELECT `folderId` FROM `DeletedDialog`").fetchone()
    check("DeletedDialog.folderId added and defaults to NULL", folder == (None,), str(folder))

    # --- idempotency -------------------------------------------------------
    snapshot = {t: sorted(columns_of(db, t)) for t in tables}
    rows_before = db.execute("SELECT COUNT(*) FROM `RegexFilter`").fetchone()[0]
    upgrade(db, pre, rebuild, post)
    check("second upgrade() run is a no-op",
          snapshot == {t: sorted(columns_of(db, t)) for t in tables}
          and db.execute("SELECT COUNT(*) FROM `RegexFilter`").fetchone()[0] == rows_before)

    # --- the ordering bug is actually detectable ---------------------------
    db2 = sqlite3.connect(":memory:")
    for name, columns in tables.items():
        if name == "RegexFilter":
            db2.execute(OLD_REGEX_FILTER)
        else:
            db2.execute(create_table(name, drop_columns(columns, ADDED_COLUMNS.get(name, set()))))
    db2.execute("INSERT INTO `RegexFilter` (`text`,`enabled`,`caseInsensitive`,`dialogId`) "
                "VALUES ('x',1,1,NULL)")
    for table, column, sql in post:          # wrong order: reversed first
        db2.execute(sql)
    for stmt in rebuild:
        db2.execute(stmt)
    buggy = columns_of(db2, "RegexFilter")
    check("wrong order really does drop `reversed` (regression guard)",
          "reversed" not in buggy, str(sorted(buggy)))
    db2.close()

    db.close()
    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: Android importer verified, all checks passed")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

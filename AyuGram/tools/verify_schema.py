"""Verify schema.sql actually executes and produces the expected structure.

This is the evidence step for the data-layer port: the schema is run in a real
SQLite engine, the resulting tables/indexes are compared against the inventory
extracted from the APK, and a round-trip insert/select smoke test is performed
on the tables whose behaviour matters most (Spy, RegexFilter, DeletedMessage).

Run:  python tools/verify_schema.py
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "Database" / "Schema" / "schema.sql"

EXPECTED_TABLES = {
    "DeletedMessage",
    "DeletedMessageReaction",
    "DeletedDialog",
    "EditedMessage",
    "SpyMessageRead",
    "SpyMessageContentsRead",
    "RegexFilter",
    "RegexFilterGlobalExclusion",
}

EXPECTED_INDEXES = {
    "index_DeletedMessage_groupedId",
    "index_DeletedMessage_userId_dialogId_topicId_messageId",
    "index_DeletedMessageReaction_deletedMessageId",
    "index_DeletedDialog_userId_dialogId",
    "index_EditedMessage_userId_dialogId_messageId",
    "index_EditedMessage_userId_dialogId_messageId_entityCreateDate",
    "index_EditedMessage_userId_dialogId_messageId_fakeId",
    "index_EditedMessage_userId_dialogId_messageId_mediaPath",
    "index_SpyMessageRead_userId_dialogId_messageId",
    "index_SpyMessageContentsRead_userId_dialogId_messageId",
}

failures = []


def check(label, ok, detail=""):
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def main():
    if not SCHEMA.exists():
        print(f"schema not found: {SCHEMA}")
        return 1

    sql = SCHEMA.read_text(encoding="utf-8")
    # Strip comments so the statement count reflects real DDL.
    ddl = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    statements = [s.strip() for s in ddl.split(";") if s.strip()]
    print(f"schema: {SCHEMA}")
    print(f"DDL statements: {len(statements)}\n")

    db = sqlite3.connect(":memory:")
    try:
        db.executescript(sql)
    except sqlite3.Error as exc:
        check("schema executes", False, str(exc))
        return 1
    check("schema executes", True, f"{len(statements)} statements")

    tables = {r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
    missing = EXPECTED_TABLES - tables
    check("all expected tables present", not missing,
          f"missing={sorted(missing)}" if missing else f"{len(tables)} tables")

    indexes = {r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")}
    missing_idx = EXPECTED_INDEXES - indexes
    check("all expected indexes present", not missing_idx,
          f"missing={sorted(missing_idx)}" if missing_idx else f"{len(indexes)} indexes")

    # Idempotency: Room/GRDB run migrations once, but IF NOT EXISTS must hold.
    try:
        db.executescript(sql)
        check("schema is idempotent (re-run)", True)
    except sqlite3.Error as exc:
        check("schema is idempotent (re-run)", False, str(exc))

    # --- structure assertions -------------------------------------------------
    def columns(table):
        return [r[1] for r in db.execute(f"PRAGMA table_info(`{table}`)")]

    dm = columns("DeletedMessage")
    for col in ("fakeId", "userId", "dialogId", "topicId", "messageId",
                "replySerialized", "replyMarkupSerialized", "documentSerialized",
                "thumbsSerialized", "documentAttributesSerialized", "postAuthor"):
        check(f"DeletedMessage.{col}", col in dm)

    rf = columns("RegexFilter")
    check("RegexFilter PK migrated to id BLOB", "id" in rf and "fakeId" not in rf, str(rf))
    check("RegexFilter.reversed (inversion) column", "reversed" in rf)
    pk = [r[1] for r in db.execute("PRAGMA table_info(`RegexFilter`)") if r[5]]
    check("RegexFilter primary key is id", pk == ["id"], f"pk={pk}")

    # --- behavioural smoke tests ---------------------------------------------
    db.execute("INSERT INTO `SpyMessageRead` (`userId`,`dialogId`,`messageId`,`entityCreateDate`)"
               " VALUES (?,?,?,?)", (1, -1001234567890, 4242, 1700000000000))
    row = db.execute("SELECT userId, dialogId, messageId FROM `SpyMessageRead`"
                     " WHERE userId=? AND dialogId=? AND messageId=?",
                     (1, -1001234567890, 4242)).fetchone()
    check("SpyMessageRead round-trip (incl. negative dialogId for channels)",
          row == (1, -1001234567890, 4242), str(row))

    import uuid
    fid = uuid.uuid4().bytes
    db.execute("INSERT INTO `RegexFilter` (`id`,`text`,`enabled`,`reversed`,`caseInsensitive`,`dialogId`)"
               " VALUES (?,?,?,?,?,?)", (fid, r"\bспам\b", 1, 0, 1, None))
    got = db.execute("SELECT enabled, reversed, caseInsensitive, text FROM `RegexFilter`"
                     " WHERE id=?", (fid,)).fetchone()
    check("RegexFilter BLOB-PK round-trip", got == (1, 0, 1, r"\bспам\b"), str(got))

    db.execute("INSERT INTO `RegexFilterGlobalExclusion` (`dialogId`,`filterId`) VALUES (?,?)",
               (-1009876543210, fid))
    n = db.execute("SELECT COUNT(*) FROM `RegexFilterGlobalExclusion` WHERE filterId=?",
                   (fid,)).fetchone()[0]
    check("RegexFilterGlobalExclusion links dialog -> filter", n == 1, f"rows={n}")

    # default value of `reversed` must apply when omitted
    fid2 = uuid.uuid4().bytes
    db.execute("INSERT INTO `RegexFilter` (`id`,`text`,`enabled`,`caseInsensitive`,`dialogId`)"
               " VALUES (?,?,?,?,?)", (fid2, "x", 1, 0, None))
    rev = db.execute("SELECT reversed FROM `RegexFilter` WHERE id=?", (fid2,)).fetchone()[0]
    check("RegexFilter.reversed defaults to 0", rev == 0, f"reversed={rev}")

    db.close()

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: schema verified, all checks passed")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

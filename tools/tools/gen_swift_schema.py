"""Generate the Swift schema constants from the verified schema.sql.

Single source of truth: AyuGram/Database/Schema/schema.sql.
The generated Swift file is used by the GRDB migrator, so the SQL that was
verified in a real SQLite engine is byte-for-byte the SQL the app executes.

Run:  python tools/gen_swift_schema.py [--check]
      --check  exits non-zero if the generated file is stale (for CI).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = ROOT / "AyuGram" / "Database" / "Schema" / "schema.sql"
OUT_PATH = ROOT / "AyuGram" / "Database" / "Schema" / "AyuSchema.generated.swift"

HEADER = """// GENERATED FILE — DO NOT EDIT BY HAND.
// Source: AyuGram/Database/Schema/schema.sql
// Regenerate: python tools/gen_swift_schema.py
//
// The statements below are the AyuGram patch-layer schema, extracted from
// vanilla-ayuGram-universal-20250101.apk (Room v32 final state) and verified
// by executing them in SQLite (tools/verify_schema.py).

import Foundation

enum AyuSchema {
    /// Statements creating the patch-layer schema from scratch.
    /// Executed inside a single GRDB migration.
    static let createStatements: [String] = [
"""

FOOTER = """    ]
}
"""


def statements():
    sql = SQL_PATH.read_text(encoding="utf-8")
    lines = [l for l in sql.splitlines() if not l.strip().startswith("--")]
    body = "\n".join(lines)
    out = []
    for raw in body.split(";"):
        s = raw.strip()
        if s:
            out.append(" ".join(s.split()))
    return out


def swift_literal(sql: str) -> str:
    escaped = sql.replace("\\", "\\\\").replace('"', '\\"')
    return f'        "{escaped}",'


def render() -> str:
    stmts = statements()
    return HEADER + "\n".join(swift_literal(s) for s in stmts) + "\n" + FOOTER


def main():
    check = "--check" in sys.argv
    expected = render()
    if check:
        if not OUT_PATH.exists():
            print(f"STALE: {OUT_PATH} does not exist")
            return 1
        actual = OUT_PATH.read_text(encoding="utf-8")
        if actual != expected:
            print("STALE: generated Swift does not match schema.sql")
            print("       run: python tools/gen_swift_schema.py")
            return 1
        print(f"OK: {OUT_PATH.name} matches schema.sql ({len(statements())} statements)")
        return 0

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(expected, encoding="utf-8", newline="\n")
    print(f"wrote {OUT_PATH} ({len(statements())} statements)")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

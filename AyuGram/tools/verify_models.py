"""Cross-check the Swift GRDB entities against the verified SQL schema.

Without a Swift compiler on this machine, the risk is silent drift between
schema.sql and the `CodingKeys` each record declares. This script parses the
actual Swift sources, resolves generic records through their `typealias`es, and
compares every table's declared columns with schema.sql.

It also checks the reverse direction: every table in schema.sql must be claimed
by exactly one entity, so a table cannot quietly lose its mapping.

Run:  python tools/verify_models.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "Database" / "Schema" / "schema.sql"
ENTITIES = ROOT / "Database" / "Entities"

# Projections that are deliberately not tables (Room @Embedded/@Relation).
NON_TABLE_TYPES = {"DeletedMessageFull"}

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


# --------------------------------------------------------------------------
# schema.sql
# --------------------------------------------------------------------------

def split_top_level(text):
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


def column_name(clause):
    clause = clause.strip()
    if clause.upper().startswith("PRIMARY KEY"):
        inner = re.search(r"\(\s*`([A-Za-z_]+)`\s*\)", clause)
        return inner.group(1) if inner else None
    if clause.upper().startswith(("FOREIGN KEY", "UNIQUE", "CHECK", "CONSTRAINT")):
        return None
    m = re.match(r"`?([A-Za-z_]+)`?", clause)
    return m.group(1) if m else None


def schema_tables():
    sql = SCHEMA.read_text(encoding="utf-8")
    body = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    tables = {}
    for stmt in (s.strip() for s in body.split(";")):
        if stmt.startswith("CREATE TABLE"):
            name = re.search(r"`([A-Za-z_]+)`\s*\(", stmt).group(1)
            inner = stmt[stmt.index("(") + 1: stmt.rindex(")")]
            tables[name] = {c for c in (column_name(x) for x in split_top_level(inner)) if c}
    return tables


# --------------------------------------------------------------------------
# Swift sources
# --------------------------------------------------------------------------

TYPE_RE = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|final\s+)*"
                     r"(struct|enum|class|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)")
TABLE_NAME_RE = re.compile(r'static\s+(?:let|var)\s+databaseTableName\s*=\s*"([^"]+)"')
GENERIC_TABLE_RE = re.compile(r"static\s+var\s+databaseTableName:\s*String\s*\{\s*"
                              r"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*databaseTableName\s*\}")
TYPEALIAS_RE = re.compile(r"typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
                          r"([A-Za-z_][A-Za-z0-9_]*)<\s*([A-Za-z_][A-Za-z0-9_]*)\s*>")
CASE_RE = re.compile(r'case\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"')


CODING_KEYS_RE = re.compile(r"\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*"
                            r"enum\s+CodingKeys\b")


def parse_swift(path):
    """Return (table_names, generic_tables, columns, typealiases) for one file."""
    lines = path.read_text(encoding="utf-8").splitlines()
    table_names, generic_tables, typealiases = {}, {}, {}
    columns = {}
    current_type = None
    in_coding_keys = False

    for line in lines:
        # Order matters: `enum CodingKeys` and `typealias` are themselves
        # matched by TYPE_RE, so they must be recognised first.
        if CODING_KEYS_RE.match(line):
            in_coding_keys = True
            columns.setdefault(current_type, [])
            continue

        if in_coding_keys:
            if line.strip().startswith("}"):
                in_coding_keys = False
                continue
            for prop, col in CASE_RE.findall(line):
                columns.setdefault(current_type, []).append((prop, col))
            continue

        m = TYPEALIAS_RE.search(line)
        if m:
            typealiases[m.group(1)] = (m.group(2), m.group(3))
            current_type = m.group(1)
            continue

        m = TYPE_RE.match(line)
        if m:
            current_type = m.group(2)
            continue

        m = TABLE_NAME_RE.search(line)
        if m and current_type:
            table_names[current_type] = m.group(1)
            continue

        m = GENERIC_TABLE_RE.search(line)
        if m and current_type:
            generic_tables[current_type] = m.group(1)
            continue

    return table_names, generic_tables, columns, typealiases


def main():
    tables = schema_tables()
    print(f"schema.sql: {len(tables)} tables -> {sorted(tables)}\n")

    table_names, generic_tables, columns, typealiases = {}, {}, {}, {}
    files = sorted(ENTITIES.glob("*.swift"))
    check("entity sources found", bool(files), f"{len(files)} files")
    for path in files:
        tn, gt, cols, ta = parse_swift(path)
        for k, v in tn.items():
            if k in table_names and table_names[k] != v:
                check(f"duplicate databaseTableName for {k}", False, f"{table_names[k]} vs {v}")
            table_names[k] = v
        generic_tables.update(gt)
        for k, v in cols.items():
            if k in columns:
                check(f"duplicate CodingKeys for {k}", False)
            columns[k] = v
        typealiases.update(ta)

    print(f"parsed: {len(columns)} CodingKeys blocks, {len(table_names)} concrete table names, "
          f"{len(generic_tables)} generic records, {len(typealiases)} typealiases\n")

    # --- resolve every entity to (table, declared columns) ----------------
    # Table-kind enums (`AyuDeletedMessageTable`) also declare
    # `databaseTableName`, but they are only generic arguments — the actual
    # column list lives on the generic record they parameterise.
    resolved = {}
    kind_enums = {kind for _, kind in typealiases.values()}
    print(f"table-kind enums (excluded from concrete mapping): {sorted(kind_enums)}")

    for type_name, table in table_names.items():
        if type_name in NON_TABLE_TYPES or type_name in kind_enums:
            continue
        resolved.setdefault(table, []).append((type_name, type_name))

    for alias, (generic, kind) in typealiases.items():
        if generic in generic_tables and kind in table_names:
            resolved.setdefault(table_names[kind], []).append((alias, generic))

    # --- forward check: every table claimed, columns match -----------------
    for table, columns_in_schema in sorted(tables.items()):
        entries = resolved.get(table, [])
        if not entries:
            check(f"{table}: mapped to an entity", False, "no entity declares this table")
            continue
        source_types = {src for _, src in entries}
        check(f"{table}: mapped by exactly one record type", len(source_types) == 1,
              f"entries={entries}")
        alias, source_type = entries[0]
        declared = columns.get(source_type, [])
        declared_cols = {col for _, col in declared}
        same = declared_cols == columns_in_schema
        check(f"{table}: entity columns == schema columns ({len(declared)} declared)", same,
              "" if same else f"missing={sorted(columns_in_schema - declared_cols)} "
                              f"extra={sorted(declared_cols - columns_in_schema)}")
        # Property names must be unique, otherwise Codable silently collides.
        props = [p for p, _ in declared]
        check(f"{table}: property names unique", len(props) == len(set(props)))

    # --- reverse check: no entity claims a non-existent table -------------
    for table in sorted(resolved):
        check(f"table `{table}` exists in schema.sql", table in tables)

    # --- non-table projections must not claim a table ---------------------
    for type_name in NON_TABLE_TYPES:
        check(f"{type_name} is a projection, not a table",
              type_name not in table_names.values() and type_name not in table_names)

    # --- the two archive tables really do share one column list -----------
    dm = {c for _, c in columns.get("AyuMessageRecord", [])}
    dm_table = tables.get("DeletedMessage", set())
    em_table = tables.get("EditedMessage", set())
    check("DeletedMessage and EditedMessage have identical column sets",
          dm_table == em_table, f"differ={sorted(dm_table ^ em_table)}")
    check("shared record covers both archive tables", dm == dm_table,
          f"record_only={sorted(dm - dm_table)} table_only={sorted(dm_table - dm)}")

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: entities match the verified schema, all checks passed")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

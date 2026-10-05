"""Generate the record <-> SQL row mapping for the AyuGram archive.

Hand-writing the mapping for a 35-column shared record is exactly the kind of
work that produces silent column-order bugs, so it is generated from the two
things that are already verified:

  * `Database/Schema/schema.sql` — the DDL recovered from the APK and verified by
    `tools/verify_schema.py`;
  * `Database/Entities/*.swift` — the record types, whose `CodingKeys` are
    cross-checked against the schema by `tools/verify_models.py`.

The generator refuses to run if the two disagree, so the generated Swift cannot
drift from the verified schema. `--check` re-renders and compares, which is what
CI runs.

Run:  python tools/gen_swift_dao.py [--check]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "Database" / "Schema" / "schema.sql"
ENTITIES = ROOT / "Database" / "Entities"
OUT = ROOT / "Database" / "DAO" / "AyuRecords.generated.swift"

HEADER = """// GENERATED FILE — DO NOT EDIT BY HAND.
// Source: Database/Schema/schema.sql + Database/Entities/*.swift
// Regenerate: python tools/gen_swift_dao.py
//
// Row decoding and SQL binding for every AyuGram archive record. Generated
// because the shared snapshot record has 35 columns and hand-written mappings
// drift silently. The generator fails if the entities and the schema disagree.

import Foundation

"""

# Swift type -> (row accessor, default for non-optional, sql value expression)
SCALARS = {
    "Int64": ("int64Value", "0", ".integer({v})"),
    "Int32": ("int32Value", "0", ".integer(Int64({v}))"),
    "Int": ("int64Value", "0", ".integer({v})"),
    "Bool": ("boolValue", "false", ".integer({v} ? 1 : 0)"),
    "String": ("stringValue", '""', ".text({v})"),
    "Data": ("dataValue", "Data()", ".blob({v})"),
    "Double": ("doubleValue", "0", ".real({v})"),
}


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


def column_of(clause):
    """Column a DDL clause defines, or None for a table-level constraint.

    A trailing ``PRIMARY KEY (`id`)`` names a column but does not define one —
    treating it as a definition yields a duplicate `id` for `RegexFilter`, whose
    primary key is declared separately from the column.
    """
    clause = clause.strip()
    if clause.upper().startswith(("PRIMARY KEY", "FOREIGN KEY", "UNIQUE", "CHECK", "CONSTRAINT")):
        return None
    m = re.match(r"`([A-Za-z_]+)`", clause)
    return m.group(1) if m else None


def parse_schema():
    sql = SCHEMA.read_text(encoding="utf-8")
    body = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    tables = {}
    for stmt in (s.strip() for s in body.split(";")):
        if not stmt.startswith("CREATE TABLE"):
            continue
        name = re.search(r"`([A-Za-z_]+)`\s*\(", stmt).group(1)
        inner = stmt[stmt.index("(") + 1: stmt.rindex(")")]
        columns = [c for c in (column_of(x) for x in split_top_level(inner)) if c]
        tables[name] = columns
    return tables


# --------------------------------------------------------------------------
# entities
# --------------------------------------------------------------------------

TYPE_RE = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|final\s+)*"
                     r"(struct|enum|class|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)")
PROPERTY_RE = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+)*"
                         r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z0-9_]+)(\?)?\s*$")
CODING_KEYS_RE = re.compile(r"\s*(?:public\s+|internal\s+|private\s+)*enum\s+CodingKeys\b")
CASE_RE = re.compile(r'case\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"')
TABLE_NAME_RE = re.compile(r'static\s+(?:let|var)\s+databaseTableName\s*=\s*"([^"]+)"')
GENERIC_TABLE_RE = re.compile(r"static\s+var\s+databaseTableName:\s*String\s*\{\s*"
                              r"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*databaseTableName\s*\}")
TYPEALIAS_RE = re.compile(r"typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
                          r"([A-Za-z_][A-Za-z0-9_]*)<\s*([A-Za-z_][A-Za-z0-9_]*)\s*>")


def parse_entities():
    records = {}          # type name -> dict
    typealiases = {}      # alias -> (generic, kind)
    table_of_kind = {}    # kind enum -> table

    for path in sorted(ENTITIES.glob("*.swift")):
        current = None
        in_keys = False
        for line in path.read_text(encoding="utf-8").splitlines(keepends=True):
            if CODING_KEYS_RE.match(line):
                in_keys = True
                continue
            if in_keys:
                if line.strip().startswith("}"):
                    in_keys = False
                    continue
                for prop, col in CASE_RE.findall(line):
                    if current and current in records:
                        records[current]["columns"].append((prop, col))
                continue

            m = TYPEALIAS_RE.search(line)
            if m:
                typealiases[m.group(1)] = (m.group(2), m.group(3))
                current = m.group(1)
                continue

            m = TYPE_RE.match(line)
            if m:
                current = m.group(2)
                records.setdefault(current, {
                    "name": current,
                    "table": None,
                    "generic": False,
                    "props": [],
                    "columns": [],
                })
                continue

            m = TABLE_NAME_RE.search(line)
            if m and current and current in records:
                records[current]["table"] = m.group(1)
                table_of_kind[current] = m.group(1)
                continue

            m = GENERIC_TABLE_RE.search(line)
            if m and current and current in records:
                records[current]["generic"] = True
                continue

            m = PROPERTY_RE.match(line)
            if m and current and current in records:
                records[current]["props"].append((m.group(1), m.group(2), m.group(3) == "?"))

    return records, typealiases, table_of_kind


# --------------------------------------------------------------------------
# generation
# --------------------------------------------------------------------------

def swift_identifier(name):
    if name in {"default", "class", "enum", "struct", "func", "var", "let", "repeat", "where"}:
        return f"`{name}`"
    return name


def render_record(name, table, props, columns, generic, bound_tables):
    prop_types = {p: (t, opt) for p, t, opt in props}

    missing = [p for p, _ in columns if p not in prop_types]
    extra = [p for p, _, _ in props if p not in {x for x, _ in columns}]
    if missing:
        raise SystemExit(f"{name}: properties missing for columns {missing}")
    if extra:
        raise SystemExit(f"{name}: properties without a column: {extra}")

    order = {p: i for i, (p, _) in enumerate(columns)}
    ordered = sorted(prop_types.items(), key=lambda kv: order.get(kv[0], 10_000))

    lines = []
    if bound_tables:
        lines.append(f"// MARK: - {name} ({', '.join(bound_tables)})")
    else:
        lines.append(f"// MARK: - {name} ({name})")
    lines.append("")
    lines.append(f"extension {name} {{")

    # --- row decoding -----------------------------------------------------
    lines.append("    /// Builds a record from one row of `" + (bound_tables[0] if bound_tables else table) + "`.")
    lines.append("    public init(row: [String: AyuSqliteValue]) {")
    for prop, (swift_type, optional) in ordered:
        column = dict(columns)[prop]
        accessor, default, _ = SCALARS[swift_type]
        key = swift_identifier(prop)
        if optional:
            lines.append(f'        self.{key} = row["{column}"]?.{accessor}')
        else:
            lines.append(f'        self.{key} = row["{column}"]?.{accessor} ?? {default}')
    lines.append("    }")
    lines.append("")

    # --- sql binding ------------------------------------------------------
    lines.append("    /// Values in `Self.columnNames` order, for INSERT/UPDATE.")
    lines.append("    public var sqlValues: [AyuSqliteValue] {")
    lines.append("        return [")
    for prop, (swift_type, optional) in ordered:
        _, _, template = SCALARS[swift_type]
        key = swift_identifier(prop)
        value = f"self.{key}"
        if optional:
            expression = f"{value}.map {{ " + template.format(v="$0") + " } ?? .null"
        else:
            expression = template.format(v=value)
        lines.append(f"            {expression},")
    lines.append("        ]")
    lines.append("    }")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render():
    tables = parse_schema()
    records, typealiases, table_of_kind = parse_entities()

    # Which tables each generic record is bound to, via typealias.
    bound = {}
    for alias, (generic, kind) in typealiases.items():
        table = table_of_kind.get(kind)
        if table is None:
            raise SystemExit(f"typealias {alias}: unknown table kind {kind}")
        bound.setdefault(generic, []).append(table)

    blocks = []
    for name, record in sorted(records.items()):
        if record["table"] is None and not record["generic"]:
            continue  # DTO / projection
        columns = record["columns"]
        if not columns:
            continue
        if record["generic"]:
            bound_tables = sorted(bound.get(name, []))
            if not bound_tables:
                raise SystemExit(f"generic record {name} is not bound to any table")
            # The generic record is shared: every bound table must have the
            # same column set, otherwise one extension cannot serve them all.
            shapes = {tuple(tables.get(t, [])) for t in bound_tables}
            if len(shapes) != 1:
                raise SystemExit(
                    f"generic record {name}: bound tables have different columns: "
                    + ", ".join(f"{t}({len(tables.get(t, []))})" for t in bound_tables)
                )
            expected = list(tables[bound_tables[0]])
            declared = [c for _, c in columns]
            if declared != expected:
                raise SystemExit(
                    f"generic record {name}: column order differs from schema\n"
                    f"  entity: {declared}\n  schema: {expected}"
                )
            blocks.append(render_record(name, None, record["props"], columns, True, bound_tables))
        else:
            table = record["table"]
            expected = tables.get(table)
            if expected is None:
                raise SystemExit(f"{name}: table {table} not found in schema.sql")
            declared = [c for _, c in columns]
            if declared != expected:
                raise SystemExit(
                    f"{name}: column list differs from schema for {table}\n"
                    f"  entity: {declared}\n  schema: {expected}"
                )
            blocks.append(render_record(name, table, record["props"], columns, False, [table]))

    return HEADER + "\n".join(blocks)


def main():
    check = "--check" in sys.argv
    expected = render()
    if check:
        if not OUT.exists():
            print(f"STALE: {OUT} does not exist")
            return 1
        if OUT.read_text(encoding="utf-8") != expected:
            print("STALE: generated record mapping does not match schema/entities")
            print("       run: python tools/gen_swift_dao.py")
            return 1
        print(f"OK: {OUT.name} matches schema and entities")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(expected, encoding="utf-8", newline="\n")
    print(f"wrote {OUT} ({len(expected.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

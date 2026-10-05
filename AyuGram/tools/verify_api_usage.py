"""Check that the foreign APIs the patch layer uses really exist with those shapes.

The patch layer calls into Postbox, and those calls are the part of the port that
cannot be parsed into correctness: `swiftc -parse` accepts `message.forwardInfo.authorId`
because it never resolves names, and no test on the Mac can cover it because Postbox
cannot be built there.

This pins every such assumption to the declaration in the checkout, and it has
already earned its place: it found two genuine compile errors — a `UInt32` raw value
assigned to an `Int32` column, and a member (`authorId`) that exists on the *store*
type but not on the runtime type the recorder actually receives.

Members are matched inside the named type's own block, not anywhere in the file, so
a same-named member of a different type cannot satisfy the check.

Run:  python tools/verify_api_usage.py
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (file, type, member declaration that must exist inside that type)
EXPECTED_MEMBERS = [
    # --- the deletion funnel reads messages inside the transaction ---
    ("submodules/Postbox/Sources/Postbox.swift", "Transaction", "func getMessage(_ id: MessageId) -> Message?"),

    # --- Message: what the archive snapshot is built from ---
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let id: MessageId"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let threadId: Int64?"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let timestamp: Int32"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let flags: MessageFlags"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let forwardInfo: MessageForwardInfo?"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let author: Peer?"),
    ("submodules/Postbox/Sources/Message.swift", "Message", "public let text: String"),

    # --- MessageFlags.rawValue is UInt32; the column is Int32 ---
    ("submodules/Postbox/Sources/Message.swift", "MessageFlags", "public var rawValue: UInt32"),

    # --- MessageForwardInfo: the runtime forward type, not StoreMessageForwardInfo ---
    ("submodules/Postbox/Sources/Message.swift", "MessageForwardInfo", "public let author: Peer?"),
    ("submodules/Postbox/Sources/Message.swift", "MessageForwardInfo", "public let date: Int32"),
    ("submodules/Postbox/Sources/Message.swift", "MessageForwardInfo", "public let authorSignature: String?"),
    # `Flags` is nested inside MessageForwardInfo and is the only `struct Flags` in
    # the file, so the name alone is unambiguous.
    ("submodules/Postbox/Sources/Message.swift", "Flags", "public var rawValue: Int32"),

    # --- PeerId ---
    ("submodules/Postbox/Sources/Peer.swift", "PeerId", "public func toInt64() -> Int64"),

    # --- MessageId.id is `Id`, which must be Int32 for the archive's Int32 column ---
    ("submodules/Postbox/Sources/Message.swift", "MessageId", "public typealias Id = Int32"),
    ("submodules/Postbox/Sources/Message.swift", "MessageId", "public let id: Id"),
]

# Members that must NOT be used, recorded with the reason. These are the mistakes
# that were made and fixed, kept as regression guards.
FORBIDDEN_USAGE = [
    ("AyuArchive/Sources/AyuArchiveRecorder.swift", "forwardInfo?.authorId",
     "MessageForwardInfo has no authorId; the runtime type exposes author: Peer?"),
    ("AyuArchive/Sources/AyuArchiveRecorder.swift", "flags: message.flags.rawValue",
     "MessageFlags.rawValue is UInt32 and must be reinterpreted with bitPattern"),
]

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def find_checkout():
    candidates = []
    if os.environ.get("AYUGRAM_REPO"):
        candidates.append(Path(os.environ["AYUGRAM_REPO"]))
    candidates += [ROOT.parent / "Telegram-iOS", Path(r"D:\ayugram-src\Telegram-iOS")]
    for candidate in candidates:
        if (candidate / "submodules" / "Postbox").is_dir():
            return candidate
    return None


TYPE_DECL = r"^\s*(?:public\s+|internal\s+|final\s+|open\s+)*(?:struct|class|enum|extension)\s+{name}\b"


def type_block(text, name):
    """Lines belonging to the named type, tracked by brace depth."""
    pattern = re.compile(TYPE_DECL.format(name=re.escape(name)))
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not pattern.match(line):
            continue
        depth = 0
        started = False
        collected = []
        for candidate in lines[index:]:
            depth += candidate.count("{") - candidate.count("}")
            if "{" in candidate:
                started = True
            collected.append(candidate)
            if started and depth <= 0:
                break
        return collected
    return None


def main():
    checkout = find_checkout()
    if checkout is None:
        print("[SKIP] no Telegram-iOS checkout found; API usage not verified")
        print("RESULT: skipped")
        return 0

    print(f"checkout: {checkout}")
    print(f"assumptions to verify: {len(EXPECTED_MEMBERS)} members in "
          f"{len({entry[0] for entry in EXPECTED_MEMBERS})} files\n")

    cache = {}
    for relative, type_name, member in EXPECTED_MEMBERS:
        path = checkout / relative
        if not path.exists():
            check(f"{type_name}: file exists ({relative})", False, "file missing")
            continue
        if relative not in cache:
            cache[relative] = path.read_text(encoding="utf-8")
        block = type_block(cache[relative], type_name)
        if block is None:
            check(f"{type_name}.{member}", False, f"type {type_name} not found in {relative}")
            continue
        found = any(member in line for line in block)
        check(f"{type_name}: {member}", found,
              "" if found else "declaration not found inside the type")

    print()
    for relative, forbidden, reason in FORBIDDEN_USAGE:
        path = ROOT / relative
        if not path.exists():
            check(f"regression guard: {relative} exists", False)
            continue
        present = forbidden in path.read_text(encoding="utf-8")
        check(f"{relative}: still free of `{forbidden}`", not present, reason)

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures[:4]}")
        return 1
    print("RESULT: every foreign API assumption holds")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

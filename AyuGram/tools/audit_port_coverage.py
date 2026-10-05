"""Audit the port against the feature inventory extracted from the APK.

`docs/apk-ayu-inventory.txt` was extracted from the release APK and groups every
AyuGram identifier by area of functionality. Nothing so far checked the port
against it, which leaves the one failure mode that is easy to miss and impossible
to notice later: an entire feature that was never started.

This pairs each inventory group with the code that implements it, verifies that the
claimed code actually exists, and refuses to pass while any group is unaccounted
for — either implemented, partially implemented, delegated to the Swiftgram base,
or explicitly out of scope with a reason.

Run:  python tools/audit_port_coverage.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INVENTORY = ROOT / "docs" / "apk-ayu-inventory.txt"
PATCH_DIR = ROOT / "patches"

SOURCE_DIRS = ["Database", "AyuSettings", "AyuArchive", "AyuFilters", "AyuAds"]

# Inventory group header, e.g. "===== Ghost mode keys (43) =====". The trailing
# count is optional: the checklist section has none.
GROUP_RE = re.compile(r"^=====\s*(.+?)(?:\s*\((\d+)\))?\s*=====$")

# status: implemented | partial | delegated | out-of-scope
FEATURES = [
    {
        "group": "AyuGram db entities",
        "status": "implemented",
        "markers": ["AyuMessageRecord", "DeletedDialog", "DeletedMessageReaction", "SpyMessageRead", "RegexFilter"],
        "note": "one generic record serves DeletedMessage/EditedMessage, as the Android base entity does",
    },
    {
        "group": "AyuGram db daos",
        "status": "implemented",
        "markers": ["AyuArchiveStore", "recordRead", "recordContentRead", "editedHistory", "applicableFilters"],
        "note": "the Room DAOs are folded into one store; the row/column mapping is generated",
    },
    {
        "group": "Ghost mode keys",
        "status": "implemented",
        "markers": ["ghostModeEnabled", "isGhostModeActive", "ghostModeIndividualChats", "suppressesStoryViews"],
        "note": "global switch plus the per-chat overrides Android keeps in ayughostexclusionsconfig",
    },
    {
        "group": "Deleted/edited message",
        "status": "implemented",
        "markers": ["recordDeletions", "recordEdit", "DeletedMessage", "EditedMessage"],
        "note": "both hooked into TelegramCore through the patch set",
    },
    {
        "group": "Spy / read receipts",
        "status": "implemented",
        "markers": ["recordReaders", "recordContentReads", "SpyMessageContentsRead"],
        "note": "read marks from getMessageReadParticipants/getOutboxReadDate, content reads from updateReadMessagesContents",
    },
    {
        "group": "Regex filters",
        "status": "partial",
        "markers": ["AyuFilterEngine", "isReversed", "isFiltered"],
        "note": "engine done and executed in tests; not yet applied to the chat view",
    },
    {
        "group": "Adblock",
        "status": "partial",
        "markers": ["AyuAdPolicy", "shouldHide", "adBlockKeywords"],
        "note": "sponsored messages only; ABP filter lists and web rewriting are deliberately not attempted",
    },
    {
        "group": "Transcription",
        "status": "delegated",
        "markers": [],
        "note": "Swiftgram already ships transcriptionBackend: apple (on-device), so the Vosk path from Android is unnecessary",
    },
    {
        "group": "Settings keys",
        "status": "implemented",
        "markers": ["AyuSettings", "MarkStyle", "ghostModeEnabled", "adBlockEnabled"],
        "note": "including the five deleted-message markers recovered from the APK",
    },
    {
        "group": "AyuGram classes",
        "status": "implemented",
        # Matched against BUILD files, not sources: a module existing is the claim
        # being checked, and a mention of its name in a comment would not prove it.
        "markers": ['module_name = "AyuArchive"', 'module_name = "AyuSettings"',
                    'module_name = "AyuFilters"', 'module_name = "AyuAds"',
                    'module_name = "AyuDatabase"'],
        "note": "the patch layer itself; see the port checklist below for the per-class mapping",
    },
    {
        "group": "PORT CHECKLIST: 75 AyuGram classes",
        "status": "implemented",
        "markers": ["AyuArchiveRecorder", "AyuArchiveStore", "AyuSqlite"],
        "note": "the 75 classes are the same surface as the groups above",
    },
    {
        "group": "exteraGram classes",
        "status": "out-of-scope",
        "markers": ["AyuAdPolicy"],
        "note": "the exteraGram layer is large and mostly unrelated to AyuGram: AI helpers, "
                "translation, backups, supporter screens. Only ad blocking was taken; the rest "
                "is not part of this port and would be a separate project",
    },
]

# Groups too generic to map one-to-one.
IGNORED_GROUPS = set()

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def inventory_groups():
    groups = []
    for line in INVENTORY.read_text(encoding="utf-8").splitlines():
        match = GROUP_RE.match(line.strip())
        if match:
            count = int(match.group(2)) if match.group(2) else 0
            groups.append((match.group(1), count))
    return groups


def port_text():
    """Everything the patch layer ships: our Swift, the generated files, BUILD
    files and the patches."""
    chunks = []
    for directory in SOURCE_DIRS:
        base = ROOT / directory
        if base.is_dir():
            for path in sorted(base.rglob("*.swift")):
                chunks.append((path.relative_to(ROOT).as_posix(), path.read_text(encoding="utf-8")))
    # BUILD files too, so a module's existence can be evidenced by its declaration
    # rather than by a passing mention of its name.
    for path in sorted(ROOT.glob("*/BUILD")) + [ROOT / "BUILD"]:
        if path.is_file():
            chunks.append((path.relative_to(ROOT).as_posix(), path.read_text(encoding="utf-8")))
    if PATCH_DIR.is_dir():
        for path in sorted(PATCH_DIR.glob("*.patch")):
            chunks.append((f"patches/{path.name}", path.read_text(encoding="utf-8")))
    return chunks


def main():
    if not INVENTORY.exists():
        print(f"[FAIL] inventory not found: {INVENTORY}")
        return 1

    groups = inventory_groups()
    check("inventory parsed", bool(groups), f"{len(groups)} groups")
    for name, count in groups:
        print(f"    {count:5d}  {name}")

    chunks = port_text()
    check("port sources collected", bool(chunks), f"{len(chunks)} files")

    print()
    covered = set()
    for feature in FEATURES:
        group = feature["group"]
        covered.add(group)
        status = feature["status"]
        found = []
        for marker in feature["markers"]:
            where = [path for path, text in chunks if marker in text]
            if where:
                found.append((marker, where[0]))
            else:
                found.append((marker, None))

        if status == "implemented":
            check(f"{group}: implemented", all(w is not None for _, w in found),
                  "; ".join(f"{m}->{w or 'MISSING'}" for m, w in found))
        elif status == "partial":
            # At least one marker must exist, or "partial" is an excuse for "absent".
            check(f"{group}: partially implemented", any(w is not None for _, w in found),
                  "; ".join(f"{m}->{w or 'MISSING'}" for m, w in found))
        else:
            print(f"[INFO] {group}: {status}")
        print(f"       {status}: {feature['note']}")
        for marker, where in found:
            if where:
                print(f"         {marker}  ({where})")

    # --- nothing may be silently unaccounted for --------------------------
    print()
    known = {name for name, _ in groups}
    unaccounted = sorted(known - covered - IGNORED_GROUPS)
    check("every inventory group is accounted for", not unaccounted,
          f"unaccounted={unaccounted}" if unaccounted else f"{len(known)} groups")

    stale = sorted(covered - known)
    check("no audit entry refers to a group that no longer exists", not stale, str(stale))

    by_status = {}
    for feature in FEATURES:
        by_status[feature["status"]] = by_status.get(feature["status"], 0) + 1
    print()
    print("summary: " + ", ".join(f"{count} {status}" for status, count in sorted(by_status.items())))

    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: port coverage audited")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

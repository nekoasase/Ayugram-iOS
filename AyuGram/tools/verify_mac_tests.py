"""Compile and run the patch layer's behavioural tests on the Mac mini.

The app cannot be built on the project's machine (a Late 2012 Mac mini on macOS
10.15, where Xcode 12.4 is the newest possible, while the tree demands Xcode
26.2). But that machine has a working `swiftc` and the system `SQLite3` module, so
the parts of the patch layer that depend on Foundation and SQLite alone can be
compiled *and executed* there.

That matters: the schema was recovered from the APK and verified by Python
scripts, but those verify SQL and a model of the records — not the Swift that
ships. These suites run the real Swift.

For the data layer the runner first builds a stub module named `sqlcipher` that
re-exports the genuine system `SQLite3`, so `import sqlcipher` resolves to real
sqlite3 symbols instead of hand-written fakes. Neither the code under test nor the
engine is simulated.

Skips cleanly (exit 0) when the Mac is unreachable, so it is safe in CI.

Configuration:
  AYUGRAM_MAC      host to run on   (default Mac-mini@192.168.31.111)
  AYUGRAM_MAC_KEY  ssh private key  (default ~/.ssh/ayugram_mac)

Run:  python tools/verify_mac_tests.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DEFAULT_HOST = "Mac-mini@192.168.31.111"
REMOTE_ROOT = "/tmp/ayugram-mac-tests"
STUB_MODULE = "sqlcipher"
PASS_MARKER = "ALL TESTS PASSED"

DATA_LAYER_SOURCES = [
    "Database/AyuSqlite.swift",
    "Database/AyuRecord.swift",
    "Database/AyuDatabase.swift",
    "Database/DAO/AyuArchiveStore.swift",
    "Database/DAO/AyuRecords.generated.swift",
    "Database/Schema/AyuSchema.generated.swift",
    "Database/Entities/AyuMessageBase.swift",
    "Database/Entities/DeletedDialog.swift",
    "Database/Entities/DeletedMessageReaction.swift",
    "Database/Entities/RegexFilter.swift",
    "Database/Entities/SpyEntities.swift",
]

# One executable per suite: two `main.swift` files cannot coexist in a module.
# `AyuArchiveRecorder` is deliberately absent — it needs Postbox, which cannot be
# stubbed honestly; it is covered by the syntax parse instead.
SUITES = [
    {
        "name": "AyuSettings",
        "sources": ["AyuSettings/Sources/AyuSettings.swift"],
        "tests": ["AyuSettingsTests.swift"],
        "uses_sqlite": False,
    },
    {
        "name": "filters",
        "sources": ["AyuFilters/Sources/AyuFilterEngine.swift"],
        "tests": ["AyuFilterTests.swift"],
        "uses_sqlite": False,
    },
    {
        "name": "data layer",
        "sources": DATA_LAYER_SOURCES,
        "tests": ["DataLayerTests.swift"],
        "uses_sqlite": True,
    },
]


def host():
    return os.environ.get("AYUGRAM_MAC", DEFAULT_HOST)


def key_path():
    return os.environ.get("AYUGRAM_MAC_KEY") or str(Path.home() / ".ssh" / "ayugram_mac")


def reachable(target, timeout=3.0):
    import socket
    address = target.split("@")[-1]
    try:
        with socket.create_connection((address, 22), timeout=timeout):
            return True
    except OSError:
        return False


def ssh_base():
    return ["ssh", "-i", key_path(), "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10"]


def run_remote(target, command):
    result = subprocess.run(ssh_base() + [target, command], capture_output=True, text=True)
    return (result.stdout or "") + (result.stderr or "")


def main():
    target = host()
    if not reachable(target):
        print(f"[SKIP] Mac not reachable at {target} (port 22 closed); behavioural tests skipped")
        print("RESULT: skipped")
        return 0

    key = key_path()
    if not Path(key).exists():
        print(f"[SKIP] ssh key not found at {key}; behavioural tests skipped")
        print("RESULT: skipped")
        return 0

    test_dir = ROOT / "tools" / "mac_tests"
    print(f"host: {target}")
    print(f"key:  {key}")

    if subprocess.run(ssh_base() + [target, f"rm -rf {REMOTE_ROOT} && mkdir -p {REMOTE_ROOT}"],
                      capture_output=True, text=True).returncode != 0:
        print("[FAIL] could not prepare the remote directory")
        return 1

    # --- build the sqlcipher shim once -------------------------------------
    with tempfile.TemporaryDirectory(prefix="ayugram-stub-") as temp:
        stub = Path(temp) / "sqlcipher_stub.swift"
        stub.write_text("@_exported import SQLite3\n", encoding="utf-8")
        module_dir = f"{REMOTE_ROOT}/modules"
        subprocess.run(ssh_base() + [target, f"mkdir -p {module_dir}"], capture_output=True, text=True)
        subprocess.run(
            ["scp", "-i", key, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
             str(stub), f"{target}:{REMOTE_ROOT}/sqlcipher_stub.swift"],
            capture_output=True, text=True,
        )
        stub_output = run_remote(
            target,
            f"cd {REMOTE_ROOT} && swiftc -emit-module -module-name {STUB_MODULE} "
            f"-emit-module-path {module_dir}/{STUB_MODULE}.swiftmodule sqlcipher_stub.swift 2>&1; "
            f"echo \"STUB_EXIT=$?\"",
        )
        if "STUB_EXIT=0" not in stub_output:
            print("[FAIL] could not build the sqlcipher shim module")
            print(stub_output.strip()[:400])
            return 1
        print(f"shim: module `{STUB_MODULE}` re-exports the system SQLite3")

    total_assertions = 0

    for suite in SUITES:
        name = suite["name"]
        remote_dir = f"{REMOTE_ROOT}/{name.replace(' ', '-')}"
        print(f"\n=== suite: {name} ===")

        with tempfile.TemporaryDirectory(prefix="ayugram-suite-") as temp:
            stage = Path(temp)

            for relative in suite["sources"]:
                source = ROOT / relative
                if not source.exists():
                    print(f"[FAIL] missing source: {relative}")
                    return 1
                destination = stage / Path(relative).name
                shutil.copy2(source, destination)

            for index, test_name in enumerate(suite["tests"]):
                test = test_dir / test_name
                if not test.exists():
                    print(f"[FAIL] missing test: {test_name}")
                    return 1
                # swiftc only allows top-level statements in a file called main.swift.
                shutil.copy2(test, stage / ("main.swift" if index == 0 else test_name))

            subprocess.run(ssh_base() + [target, f"mkdir -p {remote_dir}"], capture_output=True, text=True)
            copy = subprocess.run(
                ["scp", "-i", key, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                 *[str(p) for p in sorted(stage.iterdir())], f"{target}:{remote_dir}/"],
                capture_output=True, text=True,
            )
            if copy.returncode != 0:
                print(f"[FAIL] scp failed: {copy.stderr.strip()[:200]}")
                return 1

            include = f"-I {REMOTE_ROOT}/modules" if suite["uses_sqlite"] else ""
            link = "-lsqlite3" if suite["uses_sqlite"] else ""
            binary = f"{remote_dir}/suite"

            build_output = run_remote(
                target,
                f"cd {remote_dir} && swiftc -warnings-as-errors {include} {link} "
                f"-o {binary} *.swift 2>&1; echo \"BUILD_EXIT=$?\"",
            )
            print("--- compile ---")
            print(build_output.strip())

            if "BUILD_EXIT=0" not in build_output:
                print(f"[FAIL] suite `{name}` did not compile")
                print(f"RESULT: 1 FAILED")
                return 1

            run_output = run_remote(target, f"{binary} 2>&1; echo \"RUN_EXIT=$?\"")
            print("--- run ---")
            print(run_output.strip())

            if PASS_MARKER not in run_output or "RUN_EXIT=0" not in run_output:
                print(f"[FAIL] suite `{name}` failed")
                print("RESULT: 1 FAILED")
                return 1

            passed = run_output.count("  ok   ")
            total_assertions += passed
            print(f"[PASS] {name}: {passed} assertions")

    print()
    print(f"[PASS] {total_assertions} assertions passed across {len(SUITES)} suites")
    print("RESULT: behaviour verified")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

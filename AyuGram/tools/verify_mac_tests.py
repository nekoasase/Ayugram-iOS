"""Compile and run the patch layer's behavioural tests on the Mac mini.

The app itself cannot be built on the project's machine (a Late 2012 Mac mini on
macOS 10.15, where Xcode 12.4 is the newest possible, while the tree demands Xcode
26.2). But that machine has a working `swiftc`, and the parts of the patch layer
that depend on Foundation alone can be compiled *and executed* there.

That is a real step up from `verify_swift_syntax.py`, which only parses: these
tests exercise the Ghost Mode decision logic that the TelegramCore patches consult,
including the per-chat override rules restored from the Android original's
`ayughostexclusionsconfig`.

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

# Foundation-only sources that can be compiled on macOS 10.15.
HOST_SOURCES = ["AyuSettings/Sources/AyuSettings.swift"]
TEST_SOURCES = "mac_tests"

REMOTE_DIR = "/tmp/ayugram-mac-tests"
DEFAULT_HOST = "Mac-mini@192.168.31.111"
BINARY = "/tmp/ayugram-settings-tests"
PASS_MARKER = "ALL TESTS PASSED"


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

    test_dir = ROOT / "tools" / TEST_SOURCES
    tests = sorted(test_dir.glob("*.swift"))
    if not tests:
        print(f"[SKIP] no tests in {test_dir}")
        print("RESULT: skipped")
        return 0

    with tempfile.TemporaryDirectory(prefix="ayugram-mactests-") as temp:
        stage = Path(temp)

        copied = []
        for relative in HOST_SOURCES:
            source = ROOT / relative
            if not source.exists():
                print(f"[FAIL] missing source: {relative}")
                return 1
            destination = stage / Path(relative).name
            shutil.copy2(source, destination)
            copied.append(destination.name)

        # swiftc only allows top-level statements in a file called main.swift.
        for index, test in enumerate(tests):
            name = "main.swift" if index == 0 else test.name
            shutil.copy2(test, stage / name)
            copied.append(name)

        print(f"host:    {target}")
        print(f"sources: {', '.join(copied)}")

        if subprocess.run(ssh_base() + [target, f"rm -rf {REMOTE_DIR} && mkdir -p {REMOTE_DIR}"],
                          capture_output=True, text=True).returncode != 0:
            print("[FAIL] could not prepare the remote directory")
            return 1

        copy = subprocess.run(
            ["scp", "-i", key, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
             "-r", *[str(p) for p in sorted(stage.iterdir())], f"{target}:{REMOTE_DIR}/"],
            capture_output=True, text=True,
        )
        if copy.returncode != 0:
            print(f"[FAIL] scp failed: {copy.stderr.strip()[:200]}")
            return 1

        build = subprocess.run(
            ssh_base() + [target,
                          f"cd {REMOTE_DIR} && swiftc -warnings-as-errors -o {BINARY} *.swift 2>&1; "
                          f"echo \"BUILD_EXIT=$?\""],
            capture_output=True, text=True,
        )
        build_output = (build.stdout or "") + (build.stderr or "")
        print("--- compile ---")
        print(build_output.strip())

        if "BUILD_EXIT=0" not in build_output:
            print()
            print("[FAIL] the tests did not compile")
            print("RESULT: 1 FAILED")
            return 1

        run = subprocess.run(ssh_base() + [target, f"{BINARY} 2>&1; echo \"RUN_EXIT=$?\""],
                             capture_output=True, text=True)
        run_output = (run.stdout or "") + (run.stderr or "")
        print("--- run ---")
        print(run_output.strip())

        print()
        if PASS_MARKER not in run_output or "RUN_EXIT=0" not in run_output:
            print("[FAIL] behavioural tests failed")
            print("RESULT: 1 FAILED")
            return 1

        passed = run_output.count("  ok   ")
        print(f"[PASS] {passed} assertions passed")
        print("RESULT: behaviour verified")
        return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

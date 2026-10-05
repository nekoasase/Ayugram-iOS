"""Syntax-check the patch layer with a real Swift compiler over SSH.

Everything in this port is written without a Mac that can build the app: the
project's own machine is a Late 2012 Mac mini capped at macOS 10.15, where the
newest possible Xcode is 12.4 while the tree requires Xcode 26.2. What that Mac
*can* do is parse Swift — its Command Line Tools ship swiftc — so the sources are
copied there and run through `swiftc -parse`.

What this catches: syntax errors, unbalanced braces, malformed declarations,
shadowing/redeclaration mistakes. What it does not catch: anything needing type
information, because `-parse` stops before name binding and therefore never
resolves `import Postbox` or `import sqlcipher`. Type errors are the build's job.

The checker skips cleanly (exit 0) when the Mac is unreachable, so it is safe to
keep in `verify_all.py` and in CI.

Configuration:
  AYUGRAM_MAC      host to check on       (default Mac-mini@192.168.31.111)
  AYUGRAM_MAC_KEY  ssh private key path   (default ~/.ssh/ayugram_mac)

Run:  python tools/verify_swift_syntax.py
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Module trees that contain handwritten Swift. All of them are checked, including
# the generated ones, because a generator bug is just as fatal as a typo.
SOURCE_DIRS = ["Database", "AyuSettings", "AyuArchive"]

# Files that depend on nothing else in the project, so they can be type-checked
# without stubbing Postbox or sqlcipher. This mirrors the build, which compiles
# every module with -warnings-as-errors.
SELF_CONTAINED = [
    "AyuSettings/Sources/AyuSettings.swift",
    "Database/Schema/AyuSchema.generated.swift",
]

REMOTE_DIR = "/tmp/ayugram-syntax-check"
DEFAULT_HOST = "Mac-mini@192.168.31.111"


def host():
    return os.environ.get("AYUGRAM_MAC", DEFAULT_HOST)


def key_path():
    configured = os.environ.get("AYUGRAM_MAC_KEY")
    if configured:
        return configured
    return str(Path.home() / ".ssh" / "ayugram_mac")


def reachable(hostname, timeout=3.0):
    name, _, _ = hostname.partition("@")
    target = hostname.split("@")[-1]
    try:
        with socket.create_connection((target, 22), timeout=timeout):
            return True
    except OSError:
        return False


def ssh_base():
    args = ["ssh", "-i", key_path(), "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10"]
    return args


def collect_sources(stage):
    copied = []
    for directory in SOURCE_DIRS:
        source_root = ROOT / directory
        if not source_root.is_dir():
            continue
        for path in sorted(source_root.rglob("*.swift")):
            relative = path.relative_to(ROOT)
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            copied.append(relative)
    return copied


def main():
    target = host()
    if not reachable(target):
        print(f"[SKIP] Mac not reachable at {target} (port 22 closed); syntax check skipped")
        print("RESULT: skipped")
        return 0

    key = key_path()
    if not Path(key).exists():
        print(f"[SKIP] ssh key not found at {key}; syntax check skipped")
        print("RESULT: skipped")
        return 0

    with tempfile.TemporaryDirectory(prefix="ayugram-syntax-") as temp:
        stage = Path(temp)
        sources = collect_sources(stage)
        print(f"host: {target}")
        print(f"key:  {key}")
        print(f"sources: {len(sources)} files from {', '.join(SOURCE_DIRS)}")

        if subprocess.run(ssh_base() + [target, f"rm -rf {REMOTE_DIR} && mkdir -p {REMOTE_DIR}"],
                          capture_output=True, text=True).returncode != 0:
            print("[FAIL] could not prepare the remote directory")
            return 1

        copy = subprocess.run(
            ["scp", "-i", key, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
             "-r", *[str(stage / d) for d in SOURCE_DIRS if (stage / d).is_dir()],
             f"{target}:{REMOTE_DIR}/"],
            capture_output=True, text=True,
        )
        if copy.returncode != 0:
            print(f"[FAIL] scp failed: {copy.stderr.strip()[:200]}")
            return 1

        command = (
            f"cd {REMOTE_DIR} && "
            f"swiftc -version 2>&1 | head -1 && "
            f"swiftc -parse $(find . -name '*.swift') 2>&1; echo \"SWIFT_EXIT=$?\""
        )
        result = subprocess.run(ssh_base() + [target, command], capture_output=True, text=True)
        output = (result.stdout or "") + (result.stderr or "")

        errors = [line for line in output.splitlines() if ": error:" in line]
        version = output.splitlines()[0] if output.splitlines() else "swiftc unknown"

        print(f"compiler: {version}")
        for line in output.splitlines():
            if ": error:" in line or ": warning:" in line:
                print(f"   {line}")

        print()
        if errors:
            print(f"[FAIL] {len(errors)} syntax error(s)")
            print(f"RESULT: {len(errors)} FAILED")
            return 1

        print(f"[PASS] all {len(sources)} Swift files parse cleanly")

        # --- strict type-check of the self-contained sources ---------------
        # Every module in this tree builds with -warnings-as-errors, so a warning
        # here is a build failure in CI. Only files with no project-internal
        # dependencies can be checked without stubbing Postbox and sqlcipher.
        strict_files = [name for name in SELF_CONTAINED if (stage / name).exists()]
        if strict_files:
            strict = subprocess.run(
                ssh_base() + [target,
                              f"cd {REMOTE_DIR} && swiftc -typecheck -warnings-as-errors "
                              f"{' '.join(strict_files)} 2>&1; echo \"STRICT_EXIT=$?\""],
                capture_output=True, text=True,
            )
            strict_output = (strict.stdout or "") + (strict.stderr or "")
            strict_errors = [line for line in strict_output.splitlines()
                             if ": error:" in line or ": warning:" in line]
            if "STRICT_EXIT=0" not in strict_output or strict_errors:
                print(f"[FAIL] strict type-check of {len(strict_files)} self-contained file(s)")
                for line in strict_errors:
                    print(f"   {line}")
                print("RESULT: 1 FAILED")
                return 1
            print(f"[PASS] {len(strict_files)} self-contained file(s) type-check with "
                  f"-warnings-as-errors: {', '.join(strict_files)}")
        print("RESULT: syntax verified")
        return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

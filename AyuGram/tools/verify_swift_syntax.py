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
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PATCH_DIR = ROOT / "patches"

# The upstream tree is written for Swift 5.7+, and uses the shorthand
# `if let x {` in hundreds of places. The Mac's parser predates it, so those
# errors are expected — and each one is confirmed against its source line before
# being tolerated, so a genuine "missing initializer" cannot hide among them.
SHORTHAND_MESSAGE = "variable binding in a condition requires an initializer"
SHORTHAND_RE = re.compile(r"\blet\s+[A-Za-z_][A-Za-z0-9_]*\s*(\{|,|else)")
ERROR_RE = re.compile(r"^(?P<file>[^:]+):(?P<line>\d+):(?P<col>\d+): error: (?P<message>.*)$")

# Module trees that contain handwritten Swift. All of them are checked, including
# the generated ones, because a generator bug is just as fatal as a typo.
SOURCE_DIRS = ["Database", "AyuSettings", "AyuArchive", "AyuFilters", "AyuAds"]

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

        # --- the files our patches touch -----------------------------------
        # A patch can break syntax in ways nothing else here would notice: the patch
        # set is checked for *consistency*, never compiled. These files live in the
        # upstream tree and import modules that cannot be built on macOS 10.15, but
        # `-parse` stops before name binding, so it works on them anyway.
        if not check_patched_files(target):
            print("RESULT: 1 FAILED")
            return 1

        print("RESULT: syntax verified")
        return 0


def find_checkout():
    """The Telegram-iOS checkout the patch set applies to."""
    candidates = []
    if os.environ.get("AYUGRAM_REPO"):
        candidates.append(Path(os.environ["AYUGRAM_REPO"]))
    candidates += [ROOT.parent / "Telegram-iOS", Path(r"D:\ayugram-src\Telegram-iOS")]
    for candidate in candidates:
        if (candidate / ".git").exists() and (candidate / "submodules" / "TelegramCore").exists():
            return candidate
    return None


def patched_swift_files():
    """Swift files the patch set modifies, taken from the patches themselves."""
    paths = []
    for patch in sorted(PATCH_DIR.glob("*.patch")):
        for line in patch.read_text(encoding="utf-8").splitlines():
            if line.startswith("+++ b/"):
                path = line[len("+++ b/"):].strip()
                if path.endswith(".swift"):
                    paths.append(path)
    return sorted(set(paths))


def check_patched_files(target):
    """Parse the upstream files our patches touch.

    A patch can break syntax in a way nothing else here would notice: the patch set
    is only ever checked for consistency, never compiled. These files import modules
    that cannot be built on macOS 10.15, but `-parse` stops before name binding, so
    it works on them regardless.
    """
    paths = patched_swift_files()
    print()
    print(f"patched upstream files: {len(paths)} Swift file(s) referenced by the patch set")
    if not paths:
        print("[SKIP] the patch set references no Swift files")
        return True

    checkout = find_checkout()
    if checkout is None:
        print("[SKIP] no Telegram-iOS checkout found; patched files not parsed")
        print("       (set AYUGRAM_REPO to enable it)")
        return True

    remote = f"{REMOTE_DIR}-patched"

    with tempfile.TemporaryDirectory(prefix="ayugram-patched-") as temp:
        stage = Path(temp)
        staged = {}
        for index, relative in enumerate(paths):
            source = checkout / relative
            if not source.exists():
                print(f"[FAIL] patched file missing from the checkout: {relative}")
                return False
            # Flat staging with an index prefix: two patched files could share a
            # basename, and errors have to be mapped back to the right file.
            name = f"{index:02d}_{source.name}"
            shutil.copy2(source, stage / name)
            staged[name] = source

        subprocess.run(ssh_base() + [target, f"rm -rf {remote} && mkdir -p {remote}"],
                       capture_output=True, text=True)
        copy = subprocess.run(
            ["scp", "-i", key_path(), "-o", "BatchMode=yes",
             "-o", "StrictHostKeyChecking=accept-new",
             *[str(p) for p in sorted(stage.iterdir())], f"{target}:{remote}/"],
            capture_output=True, text=True,
        )
        if copy.returncode != 0:
            print(f"[FAIL] scp of patched files failed: {copy.stderr.strip()[:200]}")
            return False

        result = subprocess.run(
            ssh_base() + [target, f"cd {remote} && swiftc -parse *.swift 2>&1; echo \"PARSE_EXIT=$?\""],
            capture_output=True, text=True,
        )
        output = (result.stdout or "") + (result.stderr or "")

    tolerated = 0
    real = []
    for line in output.splitlines():
        match = ERROR_RE.match(line.strip())
        if not match:
            continue
        message = match.group("message")
        source = staged.get(Path(match.group("file")).name)
        if message == SHORTHAND_MESSAGE and source is not None:
            try:
                offending = source.read_text(encoding="utf-8").splitlines()[int(match.group("line")) - 1]
            except (OSError, IndexError):
                offending = ""
            # Only tolerate it when the source line really is the newer shorthand.
            if SHORTHAND_RE.search(offending):
                tolerated += 1
                continue
        real.append((Path(match.group("file")).name, message))

    if tolerated:
        print(f"[PASS] {tolerated} error(s) are Swift 5.7 shorthand bindings that the "
              f"macOS 10.15 parser predates, each confirmed against its source line")
    if real:
        print(f"[FAIL] {len(real)} real syntax error(s) in patched files")
        for name, message in real:
            print(f"   {name}: {message}")
        return False
    print(f"[PASS] all {len(paths)} patched file(s) parse cleanly")
    return True


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
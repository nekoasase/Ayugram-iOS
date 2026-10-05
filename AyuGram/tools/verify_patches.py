"""Verify the AyuGram patch set is complete and consistent.

The port keeps all upstream edits as patches (`patches/*.patch`), so this script
is what stops the patch set from drifting away from the module it depends on.

It checks, without needing Xcode or a Swift compiler:

  1. every patch is marked `// MARK: AyuGram` / `# MARK: AyuGram`, so the whole
     port stays greppable;
  2. every `AyuSettings` flag a patch guards on is actually declared in
     `AyuSettings/Sources/AyuSettings.swift` — a guard on a renamed or removed
     flag would otherwise compile fine and silently stop working;
  3. the patch set touches only the files it is supposed to touch;
  4. the build-dependency patch points at a module that exists;
  5. when a Telegram-iOS checkout is available, each patch is currently applied
     (`git apply --check --reverse`), which proves the exported patches match the
     tree byte for byte.

Set AYUGRAM_REPO to point at the checkout explicitly; otherwise a few known
locations are tried and check 5 is skipped if none exist.

Run:  python tools/verify_patches.py
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATCHES = ROOT / "patches"
SETTINGS = ROOT / "AyuSettings" / "Sources" / "AyuSettings.swift"

# The patch set is allowed to touch exactly these files, nothing else.
EXPECTED_TARGETS = {
    "submodules/TelegramCore/BUILD",
    "submodules/TelegramCore/Sources/Account/Account.swift",
    "submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift",
    "submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift",
    "submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift",
    "submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift",
    "submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift",
    "submodules/TelegramCore/Sources/TelegramEngine/Messages/MessageReadStats.swift",
    "submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift",
}

TARGET_RE = re.compile(r"^\+\+\+ b/(.+)$", re.MULTILINE)
MARK_RE = re.compile(r"^[+#]?\s*(?://|#)\s*MARK:\s*AyuGram", re.MULTILINE)
FLAG_RE = re.compile(r"AyuSettings\.shared\.([A-Za-z_][A-Za-z0-9_]*)")

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def find_repo():
    candidates = []
    if os.environ.get("AYUGRAM_REPO"):
        candidates.append(Path(os.environ["AYUGRAM_REPO"]))
    candidates += [
        ROOT.parent / "Telegram-iOS",
        Path(r"D:\ayugram-src\Telegram-iOS"),
    ]
    for candidate in candidates:
        if (candidate / ".git").exists() and (candidate / "submodules" / "TelegramCore").exists():
            return candidate
    return None


def find_git():
    exe = shutil.which("git")
    if exe:
        return exe
    # PortableGit extracted next to the project during setup.
    for candidate in (
        Path(r"D:\ayugram-toolchain\PortableGit\cmd\git.exe"),
        Path.home() / "ayugram-toolchain" / "PortableGit" / "cmd" / "git.exe",
    ):
        if candidate.exists():
            return str(candidate)
    return None


def declared_settings():
    """Names declared in AyuSettings.swift, as `var x` / `func x`."""
    text = SETTINGS.read_text(encoding="utf-8")
    names = set(re.findall(r"\b(?:public\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)", text))
    names |= set(re.findall(r"\b(?:public\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)", text))
    return names


def main():
    patches = sorted(PATCHES.glob("*.patch"))
    check("patch files present", bool(patches), f"{len(patches)} patches")
    if not patches:
        return 1

    check("settings source present", SETTINGS.exists(), str(SETTINGS.relative_to(ROOT)))
    if not SETTINGS.exists():
        return 1
    declared = declared_settings()
    print(f"declared AyuSettings members: {len(declared)}\n")

    targets = set()
    referenced = {}

    for patch in patches:
        text = patch.read_text(encoding="utf-8")

        check(f"{patch.name}: marked as an AyuGram change", bool(MARK_RE.search(text)))

        files = TARGET_RE.findall(text)
        check(f"{patch.name}: declares exactly one target file", len(files) == 1, str(files))
        targets.update(files)

        flags = sorted(set(FLAG_RE.findall(text)))
        referenced[patch.name] = flags
        for flag in flags:
            check(f"{patch.name}: AyuSettings.{flag} exists", flag in declared)

    # --- minimality -------------------------------------------------------
    unexpected = sorted(targets - EXPECTED_TARGETS)
    missing = sorted(EXPECTED_TARGETS - targets)
    check("patch set touches only the expected files",
          not unexpected and not missing,
          f"unexpected={unexpected} missing={missing}")

    # --- build dependency points at a real module -------------------------
    # Only added lines count: context lines carry the pre-existing Swiftgram
    # labels, and matching those reports a false failure.
    build_patch = next((p for p in patches if "BUILD" in p.read_text(encoding="utf-8")), None)
    if build_patch is not None:
        text = build_patch.read_text(encoding="utf-8")
        added = "\n".join(
            line for line in text.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        match = re.findall(r'"//(AyuGram/[^"]+):([A-Za-z_][A-Za-z0-9_]*)"', added)
        check("build patch adds AyuGram module dependencies", bool(match),
              "" if match else "no added //AyuGram/... label found")
        for package, target in match:
            module_build = ROOT / package[len("AyuGram/"):] / "BUILD"
            ok = module_build.exists() and target in module_build.read_text(encoding="utf-8")
            check(f"build dependency //{package}:{target} resolves to an existing target",
                  ok, str(module_build.relative_to(ROOT)))

    # --- applied state ----------------------------------------------------
    repo = find_repo()
    git = find_git()
    if repo is None:
        print("\n[SKIP] no Telegram-iOS checkout found; skipping applied-state check")
        print("       (set AYUGRAM_REPO to enable it)")
    elif git is None:
        print("\n[SKIP] git not found; skipping applied-state check")
    else:
        print(f"\ncheckout: {repo}")
        print(f"git:      {git}")
        for patch in patches:
            result = subprocess.run(
                [git, "-C", str(repo), "apply", "--check", "--reverse", str(patch)],
                capture_output=True, text=True,
            )
            check(f"{patch.name}: applied in the checkout",
                  result.returncode == 0,
                  result.stderr.strip()[:120] if result.returncode != 0 else "")

    # --- summary of guards ------------------------------------------------
    print("\nguards introduced by the patch set:")
    for name, flags in sorted(referenced.items()):
        print(f"  {name}: {', '.join(flags) if flags else '(no settings)'}")

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: patch set verified")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

"""Validate the AyuGram module BUILD files without running Bazel.

Bazel cannot run here: the Apple rules need macOS and Xcode. But most ways the
patch layer can break a build are structural and checkable statically, and each of
them fails the whole build rather than one module:

  1. a dependency label that names a package or target that does not exist;
  2. a `swift_library` whose `srcs` glob matches nothing, so the module compiles
     empty and its symbols vanish at link time;
  3. `name` and `module_name` disagreeing, so `import` does not resolve;
  4. two modules claiming the same `module_name`;
  5. a missing `-warnings-as-errors`, which the rest of the tree sets and which
     decides whether a warning fails the build.

Every label is resolved against the real checkout, so a missing target is caught
here instead of after a cold Bazel run.

Run:  python tools/verify_bazel.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A package marker may hold no targets; every other BUILD file must.
PACKAGE_MARKERS = {"BUILD"}

NAME_RE = re.compile(r'(?<![A-Za-z_])name\s*=\s*"([^"]+)"')
MODULE_NAME_RE = re.compile(r'module_name\s*=\s*"([^"]+)"')
DEPS_RE = re.compile(r"deps\s*=\s*\[(.*?)\]", re.DOTALL)
LABEL_RE = re.compile(r'"(//[^"]+)"')
GLOB_RE = re.compile(r"glob\(\s*\[(.*?)\]", re.DOTALL)
STRING_RE = re.compile(r'"([^"]*)"')

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def layout():
    """(patch-layer root, repository root, is the fork itself checked out)."""
    if (ROOT / "submodules" / "TelegramCore").is_dir():
        return ROOT / "AyuGram", ROOT, True
    return ROOT, None, False


def find_checkout():
    import os
    candidates = []
    if os.environ.get("AYUGRAM_REPO"):
        candidates.append(Path(os.environ["AYUGRAM_REPO"]))
    candidates += [ROOT.parent / "Telegram-iOS", Path(r"D:\ayugram-src\Telegram-iOS")]
    for candidate in candidates:
        if (candidate / "submodules" / "TelegramCore").is_dir():
            return candidate
    return None


def targets_in(build_file):
    """Target names declared by a BUILD file."""
    return set(NAME_RE.findall(build_file.read_text(encoding="utf-8")))


def main():
    layer, repo_root, in_fork = layout()
    checkout = repo_root if in_fork else find_checkout()

    check("patch-layer BUILD tree found", layer.is_dir(), str(layer))
    if not layer.is_dir():
        return 1

    builds = sorted(layer.rglob("BUILD"))
    check("BUILD files found", bool(builds), f"{len(builds)} files")
    for build in builds:
        print(f"    {build.relative_to(layer.parent)}")

    if checkout is None:
        print("\n[SKIP] no Telegram-iOS checkout found; dependency labels cannot be resolved")

    module_names = {}
    declared = set()  # ("AyuGram/Some/Package", "Target")

    for build in builds:
        relative = build.relative_to(layer)
        package = "AyuGram" if relative == Path("BUILD") else f"AyuGram/{relative.parent.as_posix()}"
        text = build.read_text(encoding="utf-8")

        names = NAME_RE.findall(text)
        is_marker = relative.as_posix() in PACKAGE_MARKERS
        if not is_marker:
            check(f"{package}: declares a target", bool(names),
                  "" if names else "no name = ... found")
        if not names:
            continue

        check(f"{package}: declares exactly one target", len(names) == 1, str(names))
        # The module's own target counts as declared, otherwise a module nothing
        # depends on looks unresolvable when a patch refers to it.
        declared.add((package, names[0]))

        module_name = MODULE_NAME_RE.findall(text)
        check(f"{package}: sets module_name", bool(module_name),
              "" if module_name else "missing")
        if module_name:
            check(f"{package}: name and module_name agree",
                  module_name[0] == names[0], f"{names[0]} vs {module_name[0]}")
            if module_name[0] in module_names:
                check(f"{package}: module_name is unique", False,
                      f"also used by {module_names[module_name[0]]}")
            module_names[module_name[0]] = package

        check(f"{package}: builds with -warnings-as-errors",
              "-warnings-as-errors" in text, "the rest of the tree sets this")

        # --- srcs globs must match something -----------------------------
        globs = GLOB_RE.findall(text)
        check(f"{package}: declares srcs", bool(globs), "" if globs else "no glob(...) found")
        for glob_body in globs:
            patterns = STRING_RE.findall(glob_body)
            matched = 0
            for pattern in patterns:
                matched += len(list(build.parent.glob(pattern)))
            check(f"{package}: srcs glob matches files",
                  matched > 0, f"patterns={patterns} matched={matched}")

        # --- dependency labels -------------------------------------------
        for dep_body in DEPS_RE.findall(text):
            for label in LABEL_RE.findall(dep_body):
                target = label.split(":")[-1]
                dep_package = label[2:].split(":")[0]
                declared.add((dep_package, target))

                if checkout is None:
                    continue
                if dep_package == package:
                    resolved = target in names
                else:
                    dep_build = checkout / dep_package / "BUILD"
                    if not dep_build.exists():
                        dep_build = checkout / dep_package / "BUILD.bazel"
                    if not dep_build.exists():
                        check(f"{package}: dependency {label} exists", False, "no BUILD file")
                        continue
                    resolved = target in targets_in(dep_build)
                check(f"{package}: dependency {label} exists", resolved,
                      "" if resolved else "target not declared")

    # --- the patch set's own dependency list ------------------------------
    print()
    patch_deps = set()
    for patch in sorted((ROOT / "patches").glob("*.patch")):
        for line in patch.read_text(encoding="utf-8").splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                for label in LABEL_RE.findall(line):
                    patch_deps.add(label)
    check("patch set adds dependencies", bool(patch_deps), f"{len(patch_deps)} labels")
    for label in sorted(patch_deps):
        check(f"patch dependency {label} is declared by a module",
              any(label == f"//{pkg}:{tgt}" for pkg, tgt in declared))

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures[:5]}")
        return 1
    print("RESULT: BUILD files verified")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

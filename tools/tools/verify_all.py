"""Run every verification in the repository.

Entry point for CI and for local checks. Verifies the AyuGram patch-layer data
model against the schema extracted from the Android APK, without needing a Swift
toolchain or macOS.

Run:  python tools/verify_all.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CHECKS = [
    ("schema.sql executes and has the expected shape",
     ["tools/verify_schema.py"]),
    ("generated Swift schema matches schema.sql",
     ["tools/gen_swift_schema.py", "--check"]),
    ("Android database importer reaches the final schema",
     ["tools/verify_importer.py"]),
    ("GRDB entities match the verified schema",
     ["tools/verify_models.py"]),
]


def main():
    results = []
    for title, argv in CHECKS:
        script = ROOT / argv[0]
        print("=" * 78)
        print(f"== {title}")
        print(f"== {script.relative_to(ROOT)}{' ' + ' '.join(argv[1:]) if len(argv) > 1 else ''}")
        print("=" * 78)
        proc = subprocess.run([sys.executable, str(script), *argv[1:]], cwd=str(ROOT))
        results.append((title, proc.returncode))
        print()

    print("=" * 78)
    print("SUMMARY")
    print("=" * 78)
    failed = 0
    for title, code in results:
        status = "PASS" if code == 0 else f"FAIL (exit {code})"
        if code != 0:
            failed += 1
        print(f"  [{status}] {title}")

    print()
    if failed:
        print(f"{failed} of {len(results)} checks failed")
        return 1
    print(f"all {len(results)} checks passed")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

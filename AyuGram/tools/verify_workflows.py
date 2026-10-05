"""Validate the GitHub Actions workflows without running them.

The iOS build path is CI-only (the project's Mac mini is a Late 2012 model capped
at macOS 10.15, so no local build is possible), which makes the workflows part of
the product. A typo in them would only surface minutes into an expensive macOS
run, so they are checked here instead:

  1. every workflow parses as YAML and has at least one job;
  2. every job has a runner;
  3. every `inputs.<name>` reference corresponds to a declared `workflow_dispatch`
     input — the classic silent failure, because an undefined input renders as an
     empty string rather than an error;
  4. every embedded Python heredoc compiles;
  5. every embedded shell heredoc has a matching terminator.

Run:  python tools/verify_workflows.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"

failures = []


def check(label, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f"  -- {detail}" if detail else ""))
    if not ok:
        failures.append(label)


def declared_inputs(workflow):
    # PyYAML turns the bare `on:` key into the boolean True, so both spellings
    # have to be accepted.
    triggers = workflow.get("on", workflow.get(True))
    if not isinstance(triggers, dict):
        return set()
    dispatch = triggers.get("workflow_dispatch")
    if not isinstance(dispatch, dict):
        return set()
    inputs = dispatch.get("inputs")
    return set(inputs) if isinstance(inputs, dict) else set()


def iter_run_steps(workflow):
    jobs = workflow.get("jobs") or {}
    for job_name, job in jobs.items():
        steps = (job or {}).get("steps") or []
        for index, step in enumerate(steps):
            if isinstance(step, dict) and isinstance(step.get("run"), str):
                yield job_name, index, step.get("name", f"step {index}"), step["run"]


def check_heredocs(script, label):
    """Verify heredoc pairing and compile embedded Python."""
    open_tag = re.compile(r"<<-?\s*'?([A-Za-z_][A-Za-z0-9_]*)'?")
    lines = script.splitlines()
    i = 0
    while i < len(lines):
        match = open_tag.search(lines[i])
        if not match:
            i += 1
            continue
        tag = match.group(1)
        body = []
        i += 1
        while i < len(lines) and lines[i].strip() != tag:
            body.append(lines[i])
            i += 1
        if i >= len(lines):
            check(f"{label}: heredoc {tag} is terminated", False, "reached end of script")
            return
        i += 1

        if tag.startswith("PY"):
            source = "\n".join(body)
            try:
                compile(source, f"<{label}:{tag}>", "exec")
            except SyntaxError as exc:
                check(f"{label}: inline Python compiles", False, f"line {exc.lineno}: {exc.msg}")
            else:
                check(f"{label}: inline Python compiles", True, f"{len(body)} lines")


def main():
    try:
        import yaml
    except ImportError:
        print("[SKIP] PyYAML is not installed; cannot validate workflows")
        print("RESULT: skipped")
        return 0

    files = sorted(WORKFLOWS.glob("*.yml"))
    check("workflow files found", bool(files), f"{len(files)} files")
    if not files:
        return 1

    for path in files:
        print(f"\n--- {path.name} ---")
        try:
            workflow = yaml.safe_load(path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            check(f"{path.name}: parses as YAML", False, str(exc)[:160])
            continue
        check(f"{path.name}: parses as YAML", isinstance(workflow, dict))

        jobs = workflow.get("jobs") or {}
        check(f"{path.name}: declares jobs", bool(jobs), f"{len(jobs)}")

        for job_name, job in jobs.items():
            runner = (job or {}).get("runs-on")
            check(f"{path.name}: job `{job_name}` has a runner", bool(runner), str(runner))

        inputs = declared_inputs(workflow)
        referenced = set()
        for _, _, _, script in iter_run_steps(workflow):
            referenced |= set(re.findall(r"inputs\.([A-Za-z_][A-Za-z0-9_]*)", script))
        # Inputs are also referenced from `runs-on` / `with`, so scan the raw text.
        raw = path.read_text(encoding="utf-8")
        referenced |= set(re.findall(r"inputs\.([A-Za-z_][A-Za-z0-9_]*)", raw))
        undeclared = sorted(referenced - inputs)
        check(f"{path.name}: every inputs.* reference is declared", not undeclared,
              f"undeclared={undeclared} declared={sorted(inputs)}")

        for job_name, index, name, script in iter_run_steps(workflow):
            check_heredocs(script, f"{path.name}:{job_name}:{name}")

    print()
    if failures:
        print(f"RESULT: {len(failures)} FAILED -> {failures}")
        return 1
    print("RESULT: workflows verified")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())

#!/usr/bin/env python3
"""Native safety gate: run 4D code snippets in a throwaway headless project and report crashes.

A native command that crashes 4D cannot be caught by any error handler (selectors 114/115 crashed
tool4d 21.1 in M2b). Every command must pass this probe before it enters cli/actions.json.
Test tooling only: snippets run with full 4D privileges in a disposable copy of tests/probe.
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def classify(returncode, status, names):
    """Map a probe run to a per-case outcome: passed, error, crashed or not_run."""
    results, values = {}, {}
    cases = (status or {}).get("cases", {})
    started = (status or {}).get("started", "")
    for name in names:
        if name in cases:
            results[name] = cases[name]["status"]
            if "value" in cases[name]:
                values[name] = cases[name]["value"]
        elif name == started and returncode != 0:
            results[name] = "crashed"
        else:
            results[name] = "not_run"
    finished = bool((status or {}).get("finished")) and returncode == 0
    return {"finished": finished, "returncode": returncode, "cases": results, "values": values,
            "crashed": [n for n, r in results.items() if r == "crashed"]}


def probe(root, tool4d, cases, timeout=120):
    names = [c["name"] for c in cases]
    if len(set(names)) != len(names) or not all(isinstance(c.get("code"), str) and c["code"] for c in cases):
        raise ValueError("cases need unique names and non-empty code")
    with tempfile.TemporaryDirectory(prefix="dashboard-probe-") as temp:
        project = Path(temp) / "Probe"
        shutil.copytree(Path(root) / "tests" / "probe", project)
        status_path = Path(temp) / "status.json"
        request = Path(temp) / "request.json"
        request.write_text(json.dumps({"status": str(status_path), "cases": cases}))
        try:
            run = subprocess.run([str(Path(tool4d).resolve()), str(project / "Project" / "Probe.4DProject"),
                                  "--skip-onstartup", "--startup-method=Probe", "--dataless",
                                  "--user-param=" + str(request)], capture_output=True, timeout=timeout)
            returncode = run.returncode
        except subprocess.TimeoutExpired:
            returncode = -1
        status = json.loads(status_path.read_text()) if status_path.exists() else None
        return classify(returncode, status, names)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tool4d", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True, help="JSON list of {name, code}")
    args = parser.parse_args()
    result = probe(args.root, args.tool4d, json.loads(args.cases.read_text()))
    print(json.dumps(result, indent=2))
    return 1 if result["crashed"] or not result["finished"] else 0


if __name__ == "__main__":
    sys.exit(main())

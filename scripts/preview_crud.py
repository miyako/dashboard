#!/usr/bin/env python3
"""Run bounded synthetic CRUD in a fresh, isolated 4D database and serve its dashboard."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

from test_4d import _no_symlinks, _read_json


def verify(report):
    if report.get("success") is not True or report.get("finished") is not True:
        raise ValueError("CRUD host did not finish successfully")
    counts = report.get("counts", {})
    cycles = counts.get("cycles")
    if type(cycles) is not int or cycles < 1 or type(report.get("rows")) is not int or report["rows"] != 0:
        raise ValueError("CRUD requires completed cycles and an empty final table")
    for operation in ("create", "read", "update", "delete"):
        if type(counts.get(operation)) is not int or counts[operation] != cycles * 128:
            raise ValueError("CRUD operation count mismatch: " + operation)
    if report.get("service", {}).get("status") != "stopped":
        raise ValueError("Dashboard did not stop cleanly")
    measures = [report.get("baseline"), *[
        sample.get("measures") for sample in report.get("samples", [])
    ], report.get("final")]
    deltas = {}
    for field in ("diskReadBytes", "diskWriteBytes", "cacheReadBytes",
                  "diskReadCount", "diskWriteCount", "cacheReadCount"):
        values = []
        for measure in measures:
            descriptor = (measure or {}).get("DB", {}).get(field, {})
            value = descriptor.get("value")
            if type(value) in (int, float) and math.isfinite(value) and value >= 0:
                values.append(value)
        final = (report.get("final") or {}).get("DB", {}).get(field, {}).get("value")
        if type(final) not in (int, float) or not math.isfinite(final) or final < 0:
            raise ValueError("Invalid final database counter: " + field)
        if len(values) < 2 or any(b < a for a, b in zip(values, values[1:])):
            raise ValueError("Missing or reset database counter: " + field)
        delta = values[-1] - values[0]
        if delta <= 0:
            raise ValueError("No measured database activity: " + field)
        deltas[field] = delta
    return {"counts": counts, "rows": report["rows"], "counterDeltas": deltas}


def stage(root, component):
    root = Path(root).resolve()
    component = Path(component).absolute()
    _no_symlinks(root, recursive=False)
    _no_symlinks(root / "samples/crud")
    _no_symlinks(component)
    _no_symlinks(root / "build", recursive=False)
    host = root / "build" / ("crud-preview-" + uuid.uuid4().hex)
    ignored = shutil.ignore_patterns("DerivedData", "userPreferences.*", "Data", "Logs")
    shutil.copytree(root / "samples/crud", host, ignore=ignored)
    host.chmod(0o700)
    shutil.copytree(component, host / "Components/dashboard.4dbase",
                    ignore=shutil.ignore_patterns("userPreferences.*", "Data", "Logs"))
    (host / "Data").mkdir()
    return host


def run(root, tool4d, component, seconds):
    root = Path(root).resolve()
    tool4d = Path(tool4d).resolve()
    host = stage(root, component)
    status = host / "preview-status.json"
    request = host / "preview-request.json"
    stop = host / "stop"
    request.write_text(json.dumps({"seconds": seconds, "target":
                                  "Windows-x64" if os.name == "nt" else "macOS-universal"}) + "\n")
    source_hash = hashlib.sha256()
    for path in sorted((host / "Project").rglob("*")):
        if path.is_file():
            source_hash.update(("samples/crud/" + path.relative_to(host).as_posix()).encode() + b"\0")
            source_hash.update(path.read_bytes() + b"\0")
    command = [str(tool4d), str(host / "Project/CrudSample.4DProject"),
               "--data=" + str(host / "Data/CrudSample.4DD"), "--create-data",
               "--skip-onstartup", "--startup-method=CrudPreview",
               "--user-param=" + str(request)]
    log = host / "tool4d.log"
    print(json.dumps({"host": str(host), "status": str(status), "stop": str(stop)}), flush=True)
    with log.open("w", encoding="utf-8") as output:
        child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 45
            while child.poll() is None and time.monotonic() < deadline:
                if status.exists():
                    try:
                        report = _read_json(status)
                    except json.JSONDecodeError:
                        time.sleep(0.1)
                        continue
                    service = report.get("service", {})
                    if report.get("errors") or report.get("error") or service.get("status") == "failed":
                        raise ValueError("CRUD startup failed; inspect " + str(status))
                    if service.get("status") == "running" and service.get("url"):
                        # Keep the private bootstrap token out of console/log output.
                        print(json.dumps({"ready": True, "url": service["url"].split("#")[0],
                                          "status": str(status)}), flush=True)
                        break
                time.sleep(0.1)
            else:
                raise ValueError("CRUD preview not ready; inspect " + str(log))
            child.wait(timeout=seconds + 30)
            if child.returncode != 0:
                raise ValueError("tool4d failed; inspect " + str(log))
            checked = verify(_read_json(status))
            evidence = {**checked, "success": True, "finished": True,
                        "host": str(host), "seconds": seconds,
                        "sample_sha256": source_hash.hexdigest(),
                        "tool4d_sha256": hashlib.sha256(tool4d.read_bytes()).hexdigest()}
            (host / "verification.json").write_text(json.dumps(evidence, indent=2) + "\n")
            print(json.dumps(evidence), flush=True)
            return host
        finally:
            if child.poll() is None:
                stop.touch()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.terminate()
                    child.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tool4d", type=Path, required=True)
    parser.add_argument("--component", type=Path,
                        help="Existing source or unpacked compiled dashboard.4dbase (copied, never edited)")
    parser.add_argument("--seconds", type=int, default=120, help="30..43200 seconds; default 120")
    args = parser.parse_args()
    if not 30 <= args.seconds <= 43200:
        parser.error("--seconds must be between 30 and 43200")
    component = args.component or args.root / "component/dashboard"
    try:
        run(args.root, args.tool4d, component, args.seconds)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print("CRUD verification failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

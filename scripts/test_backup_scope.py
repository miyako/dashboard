#!/usr/bin/env python3
"""Opt-in macOS backup target probe: one BACKUP in a newly staged synthetic host."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

from build_provenance import commit, sha256
from preview_crud import stage
from test_4d import _no_symlinks, _read_json


def prepare(host):
    """Use only documented 4D 21 XML backup keys, inside this freshly created host."""
    _no_symlinks(host)
    if not (host / "Data").is_dir() or any((host / "Data").iterdir()):
        raise ValueError("Backup probe requires the newly staged empty Data directory")
    archives = host / "Archives"
    archives.mkdir()
    settings = host / "Settings"
    settings.mkdir()
    xml = ET.Element("Preferences4D")
    options = ET.SubElement(ET.SubElement(xml, "Backup"), "Settings")
    general = ET.SubElement(options, "General")
    for key, value in {
        "IncludeDataFile": "True", "IncludeStructureFile": "False",
        "IncludeAltStructFile": "False", "JournalFileEnabled": "False",
        "DestinationFolder": str(archives) + "/",
    }.items():
        ET.SubElement(general, key).text = value
    advanced = ET.SubElement(options, "Advanced")
    for key in ("AutomaticRestore", "AutomaticLogIntegration", "AutomaticRestart"):
        ET.SubElement(advanced, key).text = "False"
    content = ET.tostring(xml, encoding="unicode") + "\n"
    backup = settings / "backup.4DSettings"
    backup.write_text(content, encoding="utf-8")
    request = host / "backup-scope-request.json"
    request.write_text(json.dumps({
        "settings": str(backup), "settingsContent": content,
        "data": str(host / "Data/CrudSample.4DD"),
        "logs": str(host / "Data/Logs") + "/",
        "archives": str(archives) + "/", "configureOnly": True,
    }) + "\n")
    return request


def verify(report, archives):
    if (report.get("success") is not True or report.get("finished") is not True
            or type(report.get("backupOK")) is not int or report["backupOK"] != 1):
        raise ValueError("Native BACKUP did not complete; inspect preserved phase/errors")
    direct = report["direct"]
    begin = datetime.strptime(direct["beginUTC"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)
    if begin > datetime.now(timezone.utc) or not direct["lastLocal"]:
        raise ValueError("Native backup did not establish positive recorded history")
    files = [path for path in archives.iterdir() if path.suffix.lower() == ".4bk"]
    if not files or any(not path.is_file() or path.is_symlink() or path.stat().st_size <= 0 for path in files):
        raise ValueError("Native backup did not create an isolated nonempty archive")
    metrics = {item["id"]: item for item in report["component"]}
    for field, host_field in (("lastAt", "lastLocal"), ("statusCode", "statusCode"),
                              ("duration", "duration"), ("beginUTC", "beginUTC")):
        metric = metrics["backup." + field]
        if metric.get("availability") != "available" or metric.get("value") != direct[host_field]:
            raise ValueError("Positive component/host backup target mismatch: " + field)
    return {"status": "passed", "archives": [{"name": path.name, "sha256": sha256(path)} for path in files]}


def run(root, tool4d, component):
    if sys.platform != "darwin":
        raise ValueError("This opt-in isolated probe supports native macOS only")
    root = Path(root).resolve()
    host = stage(root, component)
    request = prepare(host)
    evidence = {"scope": "fresh isolated synthetic host only", "commit": commit(root),
                "tool4d_sha256": sha256(tool4d),
                "positive_host_target": {"status": "not_run"}}
    command = [str(tool4d), str(host / "Project/CrudSample.4DProject"),
               "--data=" + str(host / "Data/CrudSample.4DD"), "--create-data",
               "--skip-onstartup", "--startup-method=BackupScopeProbe", "--user-param=" + str(request)]
    try:
        with (host / "tool4d-backup.log").open("w") as output:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=45)
            paths = _read_json(host / "backup-scope-status.json")
            if paths.get("phase") != "paths verified" or paths.get("success") is not True:
                raise ValueError("Native isolated path discovery failed")
            evidence["path_discovery"] = paths
            options = _read_json(request)
            xml = ET.fromstring(options["settingsContent"])
            xml.find("Backup/Settings/General/DestinationFolder").text = paths["archivePlatformPath"]
            content = ET.tostring(xml, encoding="unicode") + "\n"
            (host / "Settings/backup.4DSettings").write_text(content, encoding="utf-8")
            options.update(settingsContent=content, configureOnly=False)
            request.write_text(json.dumps(options) + "\n")
            evidence["settings_sha256"] = sha256(host / "Settings/backup.4DSettings")
            command.remove("--create-data")
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=45)
        evidence["native"] = _read_json(host / "backup-scope-status.json")
        evidence["positive_host_target"] = verify(evidence["native"], host / "Archives")
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        evidence["positive_host_target"] = {"status": "failed", "reason": str(error)}
        status = host / "backup-scope-status.json"
        if status.exists():
            evidence["native"] = _read_json(status)
    evidence["fixture"] = str(host)
    (host / "backup-scope-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tool4d", type=Path, required=True)
    parser.add_argument("--component", type=Path, required=True, help="Source or exact unpacked compiled component")
    args = parser.parse_args()
    report = run(args.root, args.tool4d.resolve(), args.component)
    return 0 if report["positive_host_target"]["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

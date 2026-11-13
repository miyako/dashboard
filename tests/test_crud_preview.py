import copy
import sys
from pathlib import Path
import unittest
import tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from preview_crud import verify
from test_backup_scope import prepare, verify as verify_backup_scope


class CrudEvidenceTests(unittest.TestCase):
    def setUp(self):
        fields = ("diskReadBytes", "diskWriteBytes", "cacheReadBytes",
                  "diskReadCount", "diskWriteCount", "cacheReadCount")
        self.report = {
            "success": True, "finished": True, "rows": 0,
            "counts": {"cycles": 2, "create": 256, "read": 256, "update": 256, "delete": 256},
            "service": {"status": "stopped"},
            "baseline": {"DB": {field: {"value": 10} for field in fields}},
            "samples": [{"measures": {"DB": {field: {"value": 20} for field in fields}}}],
            "final": {"DB": {field: {"value": 30} for field in fields}},
            "datastore": {
                "datastore." + field: {"id": "datastore." + field, "label": field,
                    "type": "text" if field == "type" else "boolean" if field == "networked" else "number",
                    "unit": "" if field in ("type", "networked") else "dataclasses",
                    "kind": "static", "availability": "available", "value": value}
                for field, value in {"type": "4D", "networked": False, "classes": 1,
                                     "exposed": 0, "unexposed": 1}.items()
            },
            "backup": {
                "backup." + field: {"id": "backup." + field, "label": field,
                    "type": "number" if field in ("statusCode", "duration") else "text",
                    "unit": "ms" if field == "duration" else "", "kind": "static",
                    "availability": "unsupported", "reason": "BACKUP INFO component-to-host data-file scope is unverified; host backup metadata unsupported"}
                for field in ("lastAt", "nextAt", "statusCode", "duration", "beginUTC")
            },
        }
        self.report["backup"]["backup.observedAt"] = {
            "id": "backup.observedAt", "label": "Observed", "type": "text", "unit": "",
            "kind": "static", "availability": "available", "value": "2026-11-14T00:00:00.123Z"}
        self.report["backupHostNative"] = {
            "lastLocal": "", "nextLocal": "", "statusCode": 0, "duration": 0, "beginUTC": ""}
        self.report["backupComponentNative"] = {
            "last": {"ok": True, "data": {"local": ""}},
            "next": {"ok": True, "data": {"local": ""}},
            "status": {"ok": True, "data": {"code": 0}},
            "information": {"ok": True, "data": {"duration": 0, "begin": ""}}}

    def test_no_backup_observation_must_not_approve_zero_or_private_metadata(self):
        for update in ({"value": 0}, {"availability": "available", "value": 0},
                       {"availability": "missing"}, {"path": "/private/backup"},
                       {"kind": "gauge"}):
            bad = copy.deepcopy(self.report)
            bad["backup"]["backup.duration"].update(update)
            with self.subTest(update=update), self.assertRaisesRegex(ValueError, "backup"):
                verify(bad)
        for field in ("backupHostNative", "backupComponentNative"):
            bad = copy.deepcopy(self.report)
            del bad[field]
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "backup"):
                verify(bad)

    def test_backup_probe_only_prepares_an_empty_isolated_data_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            host = Path(directory).resolve()
            (host / "Data").mkdir()
            request = prepare(host)
            self.assertTrue(request.is_file())
            settings = ET.parse(host / "Settings/backup.4DSettings")
            general = settings.find("Backup/Settings/General")
            self.assertEqual(general.findtext("DestinationFolder"), str(host / "Archives") + "/")
            self.assertEqual(general.findtext("IncludeDataFile"), "True")
            self.assertEqual(general.findtext("IncludeStructureFile"), "False")
            self.assertEqual(general.findtext("JournalFileEnabled"), "False")
            self.assertIsNone(general.find("IncludesFiles"))
        with tempfile.TemporaryDirectory() as directory:
            host = Path(directory).resolve()
            (host / "Data").mkdir()
            (host / "Data/existing.4DD").write_bytes(b"do not touch")
            with self.assertRaisesRegex(ValueError, "empty Data"):
                prepare(host)
            self.assertFalse((host / "Settings").exists())
            self.assertEqual((host / "Data/existing.4DD").read_bytes(), b"do not touch")

    def test_incomplete_backup_probe_is_failure_not_positive_target_evidence(self):
        for report in ({"success": False, "finished": False, "phase": "backup"},
                       {"success": True, "finished": True, "backupOK": True}):
            with self.subTest(report=report), self.assertRaisesRegex(ValueError, "did not complete"):
                verify_backup_scope(report, Path("unused"))

    def test_requires_genuine_host_schema_and_no_private_metadata(self):
        for update in ({"value": 0}, {"availability": "unsupported"},
                       {"name": "private-class"}, {"value": True}):
            bad = copy.deepcopy(self.report)
            bad["datastore"]["datastore.classes"].update(update)
            with self.subTest(update=update), self.assertRaisesRegex(ValueError, "datastore"):
                verify(bad)
        bad = copy.deepcopy(self.report)
        del bad["datastore"]
        with self.assertRaisesRegex(ValueError, "Datastore"):
            verify(bad)

    def test_requires_round_trips_and_real_counter_movement(self):
        result = verify(self.report)
        self.assertEqual(result["counterDeltas"]["diskReadBytes"], 20)
        for field, value in (("rows", 1), ("finished", False), ("success", False)):
            with self.subTest(field=field):
                bad = {**self.report, field: value}
                with self.assertRaises(ValueError):
                    verify(bad)
        bad = copy.deepcopy(self.report)
        bad["counts"]["update"] -= 1
        with self.assertRaisesRegex(ValueError, "update"):
            verify(bad)

    def test_missing_and_reset_counters_are_not_zero_or_success(self):
        for values in ((None, None, 30), (10, 10, 10), (10, 5, 30), (10, 20, True)):
            with self.subTest(values=values):
                bad = copy.deepcopy(self.report)
                measures = [bad["baseline"], bad["samples"][0]["measures"], bad["final"]]
                for measure, value in zip(measures, values):
                    measure["DB"]["diskReadBytes"] = {"value": value}
                with self.assertRaises(ValueError):
                    verify(bad)


if __name__ == "__main__":
    unittest.main()

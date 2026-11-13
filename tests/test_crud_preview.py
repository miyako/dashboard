import copy
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from preview_crud import verify


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
        }

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

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import probe_native  # noqa: E402


class ActionCatalogTests(unittest.TestCase):
    def test_go_and_4d_ship_byte_identical_catalogs(self):
        go = (ROOT / "cli" / "actions.json").read_bytes()
        component = (ROOT / "component" / "dashboard" / "Resources" / "actions.json").read_bytes()
        self.assertEqual(go, component, "copy cli/actions.json to component/dashboard/Resources/actions.json")

    def test_catalog_shape_and_tier_rules(self):
        catalog = json.loads((ROOT / "cli" / "actions.json").read_text())
        self.assertEqual(catalog["version"], 1)
        ids = [a["id"] for a in catalog["actions"]]
        self.assertEqual(len(ids), len(set(ids)))
        for action in catalog["actions"]:
            self.assertEqual(set(action), {"id", "tier", "scope", "deadlineMs", "exclusive", "progress", "verify",
                                           "approval", "transport", "args"})
            if action["tier"] != "A":
                self.assertEqual(action["approval"], "operator+host")
                self.assertEqual(action["transport"], "tls_or_loopback_only")
            for spec in action["args"].values():
                if spec["type"] == "text":
                    self.assertTrue(spec["pattern"].startswith("^") and spec["pattern"].endswith("$"))


class ProbeClassificationTests(unittest.TestCase):
    def test_crash_is_attributed_to_the_started_case(self):
        status = {"finished": False, "started": "b", "cases": {"a": {"status": "passed"}}}
        result = probe_native.classify(-11, status, ["a", "b", "c"])
        self.assertEqual(result["cases"], {"a": "passed", "b": "crashed", "c": "not_run"})
        self.assertEqual(result["crashed"], ["b"])
        self.assertFalse(result["finished"])

    def test_clean_run_and_missing_status(self):
        status = {"finished": True, "started": "", "cases": {"a": {"status": "error"}}}
        self.assertEqual(probe_native.classify(0, status, ["a"]), {"finished": True, "returncode": 0, "cases": {"a": "error"}, "values": {}, "crashed": []})
        self.assertEqual(probe_native.classify(1, None, ["a"])["cases"], {"a": "not_run"})


if __name__ == "__main__":
    unittest.main()

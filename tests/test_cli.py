import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION_RESPONSE = b'{"protocol":1,"version":"0.1.4"}\n'
sys.path.insert(0, str(ROOT / "scripts"))
from build_cli import smoke_test
from bump_release import plan


class DashboardCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("TEST_CLI_LANGUAGE") == "none":
            raise unittest.SkipTest("native CLI execution explicitly disabled")
        cls.temp = tempfile.TemporaryDirectory(prefix="dashboard test ")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.binary = Path(cls.temp.name) / ("dashboard.exe" if os.name == "nt" else "dashboard")
        subprocess.run(["go", "build", "-o", str(cls.binary), "."], cwd=ROOT / "cli",
                       check=True, capture_output=True, timeout=180)

    def test_native_contract(self):
        config = json.loads((ROOT / "template.json").read_text())
        smoke_test(self.binary, config["version"], ROOT / "tests/cli-contract.json")

    def test_version(self):
        result = subprocess.run([str(self.binary), "--version"], check=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.stdout, VERSION_RESPONSE)

    def test_destination_version_surfaces(self):
        config = json.loads((ROOT / "template.json").read_text())
        _, changes = plan(ROOT, config["version"], "miyako/dashboard")
        self.assertEqual(changes, {})

    def test_literal_arguments(self):
        for value in ['日本語 "quoted" \\backslash; \'$()\'', "line\nbreak", "trailing\\", "<>&", " "]:
            with self.subTest(value=value):
                result = subprocess.run([str(self.binary), "inspect", "--text", value],
                                        check=True, capture_output=True, timeout=10)
                self.assertEqual(json.loads(result.stdout)["text"], value)
                self.assertEqual(result.stderr, b"")

    def test_eof_shuts_down(self):
        result = subprocess.run([str(self.binary), "serve"], input=b"", capture_output=True,
                                timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, b"")

    def test_malformed_stream_fails(self):
        result = subprocess.run([str(self.binary), "serve"], input=b'{"protocol":false}\n',
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"stdin frame:", result.stderr)


if __name__ == "__main__":
    unittest.main()

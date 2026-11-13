import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import support_components as support


class SupportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, "w") as archive:
            archive.writestr("Project/DerivedData/CompiledCode/classes.json", "{}")
        outer = io.BytesIO()
        with zipfile.ZipFile(outer, "w") as archive:
            archive.writestr("workers.4dbase/workers.4DZ", inner.getvalue())
            archive.writestr("workers.4dbase/Libraries/lib4d-arm64.dylib", b"test library")
        self.archive = outer.getvalue()
        self.component = {"name": "workers", "repository": "miyako/workers", "tag": "20.0.23",
                          "revision": "a" * 40,
                          "sha256": hashlib.sha256(self.archive).hexdigest()}
        self.lock = self.root / "support-components.json"
        self.lock.write_text(json.dumps({"schema": 1, "components": [self.component]}))

    def download(self, url, path):
        self.assertEqual(url, "https://github.com/miyako/workers/releases/download/20.0.23/workers.zip")
        path.write_bytes(self.archive)

    def test_exact_compiled_archive_is_staged_and_bound_in_evidence(self):
        with patch.object(support, "_download", side_effect=self.download):
            evidence = support.stage(self.root, self.root / "host/Components")
        support.validate_evidence(self.root, {"support_components": evidence})
        self.assertTrue((self.root / "host/Components/workers.4dbase/workers.4DZ").is_file())
        with patch.object(support, "_download") as download:
            self.assertEqual(support.stage(self.root, self.root / "host/Components"), evidence)
            download.assert_not_called()
        evidence[0]["sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "evidence"):
            support.validate_evidence(self.root, {"support_components": evidence})

    def test_hash_mismatch_fails_before_installation(self):
        self.component["sha256"] = "b" * 64
        self.lock.write_text(json.dumps({"schema": 1, "components": [self.component]}))
        with patch.object(support, "_download", side_effect=self.download), \
                self.assertRaisesRegex(ValueError, "hash mismatch"):
            support.stage(self.root, self.root / "host/Components")
        self.assertFalse((self.root / "host/Components/workers.4dbase").exists())

    def test_unpinned_or_duplicate_identity_is_rejected_before_download(self):
        for change in ({"tag": "../latest"}, {"revision": "main"}, {"name": "../escape"},
                       {"sha256": "unknown"}, {"extra": "unsupported"}):
            self.lock.write_text(json.dumps({"schema": 1, "components": [{**self.component, **change}]}))
            with self.subTest(change=change), self.assertRaises(ValueError):
                support.expected(self.root)
        self.lock.write_text(json.dumps({"schema": 1, "components": [self.component, self.component]}))
        with self.assertRaises(ValueError):
            support.expected(self.root)

    def test_escaping_archive_entries_are_rejected(self):
        content = io.BytesIO()
        with zipfile.ZipFile(content, "w") as archive:
            archive.writestr("workers.4dbase/../escape", b"bad")
        with zipfile.ZipFile(io.BytesIO(content.getvalue())) as archive, \
                self.assertRaisesRegex(ValueError, "unsafe"):
            list(support._entries(archive, "workers.4dbase"))

    def test_absent_lock_preserves_generic_template_behavior(self):
        self.lock.unlink()
        self.assertEqual(support.stage(self.root, self.root / "host/Components"), [])
        support.validate_evidence(self.root, {})

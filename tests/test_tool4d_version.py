import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from ci_config import tool4d_version  # noqa: E402


def runner(*outcomes):
    calls = []

    def run(args, **kwargs):
        calls.append(args)
        outcome = outcomes[len(calls) - 1]
        if isinstance(outcome, int):
            raise subprocess.CalledProcessError(outcome, args)
        if isinstance(outcome, Exception):
            raise outcome
        return subprocess.CompletedProcess(args, 0, stdout=outcome, stderr="")
    return run, calls


class Tool4dVersionTests(unittest.TestCase):
    def setUp(self):
        self.pauses = []

    def check(self, *outcomes):
        run, calls = runner(*outcomes)
        return tool4d_version("tool4d", runner=run, pause=self.pauses.append), calls

    def test_first_try_success(self):
        (text, attempts), calls = self.check("21.1 build 21.100562\n")
        self.assertEqual((text, attempts, len(calls), self.pauses), ("21.1 build 21.100562", 1, 1, []))

    def test_one_signal_crash_is_retried_once(self):
        (text, attempts), calls = self.check(-11, "21.1 build 21.100562")
        self.assertEqual((text, attempts, len(calls), self.pauses), ("21.1 build 21.100562", 2, 2, [2]))

    def test_second_crash_still_fails(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.check(-11, -11)

    def test_ordinary_error_exit_is_not_retried(self):
        run, calls = runner(1, "unused")
        with self.assertRaises(subprocess.CalledProcessError):
            tool4d_version("tool4d", runner=run, pause=self.pauses.append)
        self.assertEqual((len(calls), self.pauses), (1, []))

    def test_timeout_is_not_retried(self):
        run, calls = runner(subprocess.TimeoutExpired("tool4d", 30), "unused")
        with self.assertRaises(subprocess.TimeoutExpired):
            tool4d_version("tool4d", runner=run, pause=self.pauses.append)
        self.assertEqual(len(calls), 1)

    def test_empty_version_text_fails(self):
        with self.assertRaises(ValueError):
            self.check("  \n")


if __name__ == "__main__":
    unittest.main()

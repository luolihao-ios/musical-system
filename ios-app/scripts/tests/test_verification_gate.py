from pathlib import Path
import unittest

class VerificationGateTests(unittest.TestCase):
    def test_exit_trap_preserves_failure_and_mac_bash_never_expands_empty_array(self):
        source = (Path(__file__).resolve().parents[1] / "verify.sh").read_text(encoding="utf-8")
        self.assertIn('trap \'test_status=$?;', source)
        self.assertIn('exit "$test_status"', source)
        self.assertNotIn('test_selection=()', source)
        self.assertIn('test_selection=(-parallel-testing-enabled NO)', source)

import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "adaptive_runtime.py"
spec = importlib.util.spec_from_file_location("adaptive_runtime", path)
runtime = importlib.util.module_from_spec(spec)


class AdaptiveRuntimeTests(unittest.TestCase):
    def test_duo_only_runtime_is_not_selected_for_ordinary_phone(self):
        spec.loader.exec_module(runtime)
        fixtures = [
            {"identifier": "ios27", "version": "27.0", "isAvailable": True,
             "supportedDeviceTypes": [{"identifier": "phone"}, {"identifier": "ipad"}]},
            {"identifier": "ios271", "version": "27.1", "isAvailable": True,
             "supportedDeviceTypes": [{"identifier": "duo"}]},
        ]
        self.assertEqual(runtime.runtime_for_device(fixtures, "phone"), "ios27")
        self.assertEqual(runtime.runtime_for_device(fixtures, "ipad"), "ios27")
        self.assertEqual(runtime.runtime_for_device(fixtures, "duo"), "ios271")
        with self.assertRaises(ValueError):
            runtime.runtime_for_device(fixtures, "watch")


if __name__ == "__main__":
    unittest.main()

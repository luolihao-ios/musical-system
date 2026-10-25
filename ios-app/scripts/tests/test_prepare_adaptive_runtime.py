import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

path = Path(__file__).resolve().parents[1] / "prepare_adaptive_runtime.py"
spec = importlib.util.spec_from_file_location("prepare_adaptive_runtime", path)
module = importlib.util.module_from_spec(spec)


def runtime(available=True, devices=None):
    return {"runtimes": [{"identifier": "ios271", "version": "27.1", "isAvailable": available,
        "supportedDeviceTypes": [{"identifier": d} for d in (devices if devices is not None else ["com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"])]}]}


class PrepareRuntimeTests(unittest.TestCase):
    def setUp(self):
        spec.loader.exec_module(module)

    def invoke(self, replies):
        calls = []
        def run(args):
            calls.append(args)
            status, data = replies.pop(0)
            return subprocess.CompletedProcess(args, status, json.dumps(data), "")
        return run, calls

    def test_available_compatible_runtime_does_not_invoke_download(self):
        run, calls = self.invoke([(0, runtime())])
        self.assertEqual(module.ensure_runtime(run)["runtimes"][0]["identifier"], "ios271")
        self.assertEqual(calls, [["xcrun", "simctl", "list", "runtimes", "-j"]])

    def test_download_status_70_is_accepted_only_after_runtime_is_available(self):
        run, calls = self.invoke([(0, {"runtimes": []}), (70, "already downloaded"), (0, runtime())])
        self.assertEqual(module.ensure_runtime(run)["runtimes"][0]["identifier"], "ios271")
        self.assertEqual(calls[1], ["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", "27.1", "-architectureVariant", "arm64"])

    def test_download_message_does_not_hide_missing_runtime(self):
        run, _ = self.invoke([(0, {"runtimes": []}), (70, "already downloaded"), (0, runtime(False))])
        with self.assertRaisesRegex(RuntimeError, "不可用"):
            module.ensure_runtime(run)

    def test_wrong_device_runtime_is_not_accepted_even_when_download_succeeds(self):
        run, _ = self.invoke([(0, runtime(devices=["phone"])), (0, "done"), (0, runtime(devices=["phone"]))])
        with self.assertRaisesRegex(RuntimeError, "不可用"):
            module.ensure_runtime(run)

    def test_runtime_inspection_failure_does_not_attempt_download(self):
        run, calls = self.invoke([(70, "inspection failed")])
        with self.assertRaisesRegex(RuntimeError, "读取"):
            module.ensure_runtime(run)
        self.assertEqual(len(calls), 1)

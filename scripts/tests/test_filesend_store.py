"""校验互传 App 定位与构建号，防止操作到音乐播放器或重复上传旧构建。"""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from filesend_store import BUNDLE, LABELS, next_build, resolve_app


class FileSendStoreTests(unittest.TestCase):
    def test_rejects_music_player_identity(self):
        class API:
            def call(self, path):
                return {"data": [{"id": "music", "attributes": {"bundleId": "com.luolihao.musicalsystem"}}]}
        with self.assertRaises(ValueError):
            resolve_app(API())

    def test_resolves_existing_transfer_identity(self):
        class API:
            def call(self, path):
                if f"filter[bundleId]={BUNDLE}" not in path:
                    raise AssertionError(path)
                return {"data": [{"id": "transfer", "attributes": {"bundleId": BUNDLE}}]}
        self.assertEqual(resolve_app(API())["id"], "transfer")

    def test_build_increases_beyond_existing_uploads(self):
        class API:
            def list_all(self, path):
                return [{"attributes": {"version": version}} for version in ["87", "110", "118", "1.0"]]
        self.assertEqual(next_build(API(), "transfer"), 119)

    def test_store_labels_fit_apple_limits(self):
        self.assertEqual(set(LABELS), {"en-US", "zh-Hans", "zh-Hant"})
        for value in LABELS.values():
            self.assertEqual(value["name"], "file send")
            self.assertLessEqual(len(value["subtitle"]), 30)


if __name__ == "__main__":
    unittest.main()

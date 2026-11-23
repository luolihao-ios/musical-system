"""上传前验收整套 file send 成图，要求每张包含对应设备的真实运行界面。"""
import hashlib
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app_store_screenshots import validate_manifest_image

ROOT = Path(__file__).resolve().parents[2] / "marketing/file-send-2026-10-26"


class FileSendCampaignTests(unittest.TestCase):
    def test_fifteen_real_ui_assets_are_complete_and_match_checksums(self):
        manifest = json.loads((ROOT / "文件验收清单.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest), 15)
        self.assertEqual(len({entry["sha256"] for entry in manifest}), 15)
        expected = {"iphone-medium": (5,1206,2622), "iphone-duo": (4,1398,2034), "ipad-13": (4,2064,2752), "creative": (2,5244,2950)}
        for group,(count,width,height) in expected.items():
            entries = [entry for entry in manifest if entry["file"].startswith(group + "/")]
            self.assertEqual(len(entries), count)
            for entry in entries:
                with self.subTest(file=entry["file"]):
                    self.assertEqual((entry["width"],entry["height"]),(width,height))
                    self.assertTrue(entry["actualScreenshotPixelVerified"])
                    validate_manifest_image(ROOT,entry)
        self.assertEqual({entry["placementType"] for entry in manifest if entry.get("category")=="CREATIVE_ASSETS"},
                         {"PRODUCT_PAGE_HEADER_ASSET","APP_STORE_SEARCH_RESULTS_ASSET"})

    def test_original_device_screenshots_have_traceable_cloud_runs(self):
        evidence = json.loads((ROOT / "sources/actual/原图证据.json").read_text(encoding="utf-8"))
        self.assertEqual({item["device"] for item in evidence},{"iphone","ipad","duo"})
        for item in evidence:
            file = ROOT / "sources/actual" / Path(item["file"].replace("\\","/"))
            self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), item["sha256"])
            self.assertGreater(item["sourceRun"], 0)


if __name__ == "__main__":
    unittest.main()

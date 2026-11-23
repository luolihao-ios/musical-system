"""商店图片上传前的离线验收；不使用认证、不访问 Apple。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

SCRIPT = Path(__file__).resolve().parents[1] / "app_store_screenshots.py"
spec = importlib.util.spec_from_file_location("store_artwork", SCRIPT)
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


def png_chunk(kind, content):
    return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content))


def tiny_png(color=2, transparency=False):
    result = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, color, 0, 0, 0))
    if transparency:
        result += png_chunk(b"tRNS", b"\x00\x00" * 3)
    result += png_chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
    return result + png_chunk(b"IEND", b"")


class StoreArtworkTests(unittest.TestCase):
    def test_device_placement_groups_include_native_duo_without_watch(self):
        self.assertEqual(store.screenshot_group("ipad-13/01.png"), "IPAD_13_PROFILE")
        self.assertEqual(store.screenshot_group("iphone-duo/01.png"), "IPHONE_DUO_PROFILE")
        self.assertEqual(store.screenshot_group("iphone-65/01.png"), "IPHONE_FACE_ID_LARGE_PROFILE")
        with self.assertRaises(ValueError):
            store.screenshot_group("watch/01.png")
    def validate(self, data, **changes):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "test.png").write_bytes(data)
            entry = {"file": "test.png", "width": 1, "height": 1,
                "sha256": hashlib.sha256(data).hexdigest(), **changes}
            return store.validate_manifest_image(folder, entry)

    def test_opaque_rgb_png_is_accepted(self):
        self.assertEqual(self.validate(tiny_png()), tiny_png())

    def test_rgba_is_rejected_even_if_pixels_are_opaque(self):
        with self.assertRaisesRegex(ValueError, "无透明"):
            self.validate(tiny_png(color=6))

    def test_rgb_transparent_color_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "透明颜色"):
            self.validate(tiny_png(transparency=True))

    def test_checksum_dimension_and_truncation_are_rejected(self):
        for changes in ({"sha256": "wrong"}, {"height": 2}):
            with self.assertRaises(ValueError):
                self.validate(tiny_png(), **changes)
        with self.assertRaises(ValueError):
            self.validate(tiny_png()[:-12])

    def test_null_image_relationship_is_safe(self):
        self.assertIsNone(store.image_identity({"relationships": {"image": {"data": None}}}))

    def test_placement_query_explicitly_includes_image_relationship(self):
        class RecordingAPI:
            def list_all(self, path):
                self.path = path
                if "include=image" in path:
                    return [{"relationships": {"image": {"data": {"id": "image-1"}}}}]
                return [{}]

        api = RecordingAPI()
        placements = store.list_placements(api, "locale-1", "IPAD_13_PROFILE")
        self.assertEqual(store.image_identity(placements[0]), "image-1")
        self.assertIn("filter[placementGroup]=IPAD_13_PROFILE", api.path)
        self.assertIn("sort=placementGroupPosition", api.path)

    def test_upload_selects_all_requested_store_localizations_in_order(self):
        locales = [{"id": key, "attributes": {"locale": key}} for key in ("zh-Hant", "en-US", "zh-Hans")]
        result = store.select_upload_locales(locales, ("en-US", "zh-Hans", "zh-Hant"))
        self.assertEqual([item["id"] for item in result], ["en-US", "zh-Hans", "zh-Hant"])

    def test_upload_rejects_missing_localization_before_placing_any_assets(self):
        with self.assertRaisesRegex(ValueError, "zh-Hant"):
            store.select_upload_locales([{"id": "en", "attributes": {"locale": "en-US"}}], ("en-US", "zh-Hant"))

    def test_repeated_placement_is_idempotent_and_keeps_locale_isolation(self):
        class API:
            def __init__(self):
                self.items = {}
                self.created = 0
            def list_all(self, path):
                locale_id = path.split("/")[1]
                items = self.items.setdefault(locale_id, [])
                if "filter[placementGroup]=" in path:
                    group = path.split("filter[placementGroup]=")[1].split("&")[0]
                    return [item for item in items if item["attributes"]["placementGroup"] == group]
                return list(items)
            def call(self, path, method, payload):
                data = payload["data"]
                locale_id = data["relationships"]["appStoreVersionLocalization"]["data"]["id"]
                items = self.items.setdefault(locale_id, [])
                if path == "appAssetLibraryPlacements":
                    self.created += 1
                    placed = {"id": str(self.created), "attributes": data["attributes"], "relationships": {"image": data["relationships"]["image"]}}
                    items.append(placed)
                    return {"data": placed}
                if path == "appAssetLibraryPlacementOrderingRequests":
                    ids = [item["id"] for item in data["relationships"]["orderedPlacements"]["data"]]
                    lookup = {item["id"]: item for item in items}
                    self.items[locale_id] = [lookup[key] for key in ids] + [item for item in items if item["id"] not in ids]
                    return {}
                raise AssertionError(path)
        api = API()
        selected = [({"file": "iphone-medium/1.png"}, "image-1"), ({"file": "ipad-13/1.png"}, "image-2")]
        for language in ("en-US", "zh-Hans", "zh-Hant"):
            locale = {"id": language, "attributes": {"locale": language}}
            first = store.place_library_images(api, locale, selected)
            second = store.place_library_images(api, locale, selected)
            self.assertEqual(first, second)
            self.assertEqual(first["placementsVerified"], 2)
            self.assertFalse(first["missingPlacements"])
            self.assertTrue(all(first["orderVerified"].values()))
        self.assertEqual(api.created, 6)

    def test_all_campaign_files_pass_manifest_validation(self):
        folder = store.ROOT / "marketing/app-store-2026-10-24"
        manifest = json.loads((folder / "文件验收清单.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest), 14)
        for group in ("iphone-medium", "iphone-duo", "ipad-13"):
            self.assertEqual(sum(entry["file"].startswith(group+"/") for entry in manifest), 4)
        creative = [entry for entry in manifest if entry.get("category") == "CREATIVE_ASSETS"]
        self.assertEqual({entry["placementType"] for entry in creative},
                         {"PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"})
        self.assertEqual(len({entry["sha256"] for entry in creative}), 2)
        for entry in manifest:
            with self.subTest(file=entry["file"]):
                store.validate_manifest_image(folder, entry)


if __name__ == "__main__":
    unittest.main()

"""校验互传 App 定位与构建号，防止操作到音乐播放器或重复上传旧构建。"""
import sys
from pathlib import Path
import unittest
from copy import deepcopy

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import filesend_store as store
from filesend_store import BUNDLE, LABELS, ensure_draft, next_build, resolve_app


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

    def test_whats_new_updates_every_existing_language_and_only_that_field(self):
        class API:
            def __init__(self):
                self.patches = []
                self.locales = [{"id": lang, "attributes": {"locale": lang, "description": "keep", "whatsNew": None}} for lang in ("en-US", "zh-Hans", "zh-Hant")]
            def call(self, path, method="GET", payload=None):
                if method == "GET":
                    return {"data": deepcopy(self.locales)}
                self.patches.append(payload)
                item = next(item for item in self.locales if item["id"] == payload["data"]["id"])
                item["attributes"].update(payload["data"]["attributes"])
                return {"data": deepcopy(item)}
        api = API()
        state = {"versions": [{"id": "draft", "attributes": {"versionString": "1.0.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}]}
        notes = {lang: "Updates for " + lang for lang in ("en-US", "zh-Hans", "zh-Hant")}
        report = store.update_whats_new(api, state, notes)
        self.assertEqual(set(report), set(notes))
        self.assertEqual(len(api.patches), 3)
        self.assertTrue(all(set(item["data"]["attributes"]) == {"whatsNew"} for item in api.patches))
        self.assertTrue(all(item["attributes"]["description"] == "keep" for item in api.locales))

    def test_whats_new_rejects_published_version_without_writes(self):
        class API:
            def call(self, *args, **kwargs):
                raise AssertionError("不可修改已发布版本")
        state = {"versions": [{"id": "live", "attributes": {"versionString": "1.0.2", "appStoreState": "READY_FOR_SALE"}}]}
        with self.assertRaises(ValueError):
            store.update_whats_new(API(), state, {"en-US": "Updates"})

    def test_whats_new_missing_translation_is_rejected_before_patching(self):
        class API:
            def call(self, path, method="GET", payload=None):
                if method != "GET":
                    raise AssertionError("翻译不全时不可写入")
                return {"data": [{"id": "fr", "attributes": {"locale": "fr-FR"}}]}
        state = {"versions": [{"id": "draft", "attributes": {"versionString": "1.0.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}]}
        with self.assertRaisesRegex(ValueError, "fr-FR"):
            store.update_whats_new(API(), state, {"en-US": "Updates"})

    def test_keywords_update_all_languages_and_preserve_other_version_fields(self):
        class API:
            def __init__(self):
                self.patches = []
                self.locales = [{"id": lang, "attributes": {"locale": lang, "description": "keep description", "whatsNew": "keep notes", "keywords": "old"}} for lang in ("en-US", "zh-Hans", "zh-Hant")]
            def call(self, path, method="GET", payload=None):
                if method == "GET":
                    return {"data": deepcopy(self.locales)}
                self.patches.append(payload)
                item = next(item for item in self.locales if item["id"] == payload["data"]["id"])
                item["attributes"].update(payload["data"]["attributes"])
                return {"data": deepcopy(item)}
        api = API()
        state = {"versions": [{"id": "draft", "attributes": {"versionString": "1.0.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}]}
        report = store.update_keywords(api, state)
        self.assertEqual(report, store.KEYWORDS)
        self.assertTrue(all(set(item["data"]["attributes"]) == {"keywords"} for item in api.patches))
        self.assertTrue(all(item["attributes"]["whatsNew"] == "keep notes" for item in api.locales))
        for keywords in report.values():
            self.assertLessEqual(len(keywords.encode("utf-8")), 100)

    def test_store_labels_fit_apple_limits(self):
        self.assertEqual(set(LABELS), {"en-US", "zh-Hans", "zh-Hant"})
        self.assertEqual(LABELS["en-US"]["name"], "iYue File Transfer")
        for value in LABELS.values():
            self.assertTrue(value["name"])
            self.assertLessEqual(len(value["name"]), 30)
            self.assertLessEqual(len(value["subtitle"]), 30)

    def test_draft_creation_requires_explicit_authorized_version(self):
        class API:
            def call(self, *args):
                raise AssertionError("不可写入其他版本")
        with self.assertRaises(ValueError):
            ensure_draft(API(), {"app": {"id": "transfer"}, "versions": []}, "1.0.3")

    def test_existing_editable_draft_is_reused(self):
        draft = {"id": "draft", "attributes": {"versionString": "1.0.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}
        self.assertEqual(ensure_draft(None, {"versions": [draft]}, "1.0.2"), draft)


if __name__ == "__main__":
    unittest.main()

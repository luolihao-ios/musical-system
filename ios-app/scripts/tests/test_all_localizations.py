import json
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2] / "LocalMusicPlayer"
LANGUAGES = ("zh-Hans", "zh-Hant", "en", "fr")


def parse_strings(path: Path) -> dict[str, str]:
    pairs = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', path.read_text(encoding="utf-8"))
    result = {json.loads(key): json.loads(value) for key, value in pairs}
    if len(result) != len(pairs):
        raise ValueError(f"重复翻译 key: {path}")
    return result


class AllLocalizationsTests(unittest.TestCase):
    def test_all_languages_share_complete_keyset_and_format_specifiers(self):
        bundles = {lang: parse_strings(ROOT / f"Resources/{lang}.lproj/Localizable.strings") for lang in LANGUAGES}
        base_keys = set(bundles["fr"])
        spec_pattern = r"%(?:\d+\$)?(?:ll|l)?[@diuf]"

        for lang, table in bundles.items():
            with self.subTest(lang=lang):
                self.assertEqual(set(table), base_keys, f"{lang} missing keys: {sorted(base_keys - set(table))}")
                for key, value in table.items():
                    self.assertTrue(value.strip(), f"{lang} empty value for {key}")
                    self.assertEqual(
                        sorted(re.findall(spec_pattern, key)),
                        sorted(re.findall(spec_pattern, value)),
                        f"{lang} format mismatch for {key}",
                    )
                if lang in {"en", "fr"}:
                    cjk_keys = [k for k, v in table.items() if re.search(r"[\u4e00-\u9fff]", v)]
                    self.assertEqual(cjk_keys, [], f"{lang} contains untranslated CJK values: {cjk_keys}")

        self.assertEqual(bundles["zh-Hans"]["后台播放"], "后台播放")
        self.assertEqual(bundles["zh-Hant"]["后台播放"], "背景播放")

    def test_all_reachable_swift_chinese_ui_strings_exist_in_all_four_languages(self):
        bundles = {lang: parse_strings(ROOT / f"Resources/{lang}.lproj/Localizable.strings") for lang in LANGUAGES}
        swift_keys = set()
        pat1 = re.compile(
            r'(?:Text|Label|Button|Section|ContentUnavailableView|Picker|LabeledContent|Menu|\.navigationTitle|\.accessibilityLabel|\.accessibilityHint|\.alert|\.confirmationDialog)\(\s*("(?:[^"\\]|\\.)*")'
        )
        pat2 = re.compile(r'(?:String\(localized:|NSLocalizedString\()\s*("(?:[^"\\]|\\.)*")')
        excluded = {"PlayerInteractionTestHarness.swift", "AdaptiveStoreAssetHarness.swift"}
        for file in ROOT.rglob("*.swift"):
            if file.name in excluded:
                continue
            text = file.read_text(encoding="utf-8")
            for pat in (pat1, pat2):
                for raw in pat.findall(text):
                    if "\\(" in raw:
                        continue
                    key = json.loads(raw)
                    if re.search(r"[\u4e00-\u9fff]", key):
                        swift_keys.add(key)

        for lang, table in bundles.items():
            missing = sorted(swift_keys - set(table))
            self.assertEqual(missing, [], f"{lang} missing Swift UI keys: {missing}")

    def test_infoplist_localizations_exist_for_all_languages(self):
        info = plistlib.loads((ROOT / "Info.plist").read_bytes())
        self.assertEqual(set(info["CFBundleLocalizations"]), set(LANGUAGES))
        for lang in LANGUAGES:
            info_strings = parse_strings(ROOT / f"Resources/{lang}.lproj/InfoPlist.strings")
            self.assertIn("CFBundleDisplayName", info_strings)
            self.assertIn("NSAppleMusicUsageDescription", info_strings)
            if lang == "en":
                self.assertIsNone(re.search(r"[\u4e00-\u9fff]", info_strings["NSAppleMusicUsageDescription"]))


if __name__ == "__main__":
    unittest.main()

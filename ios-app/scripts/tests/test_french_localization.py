import json
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2] / "LocalMusicPlayer"

def strings(path):
    pairs = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', path.read_text(encoding="utf-8"))
    result = {json.loads(key): json.loads(value) for key, value in pairs}
    if len(result) != len(pairs):
        raise ValueError("重复翻译 key")
    return result

class FrenchLocalizationTests(unittest.TestCase):
    def test_library_interpolated_statuses_are_localized(self):
        source = (ROOT / "Features/Library/LibraryView.swift").read_text(encoding="utf-8")
        french = strings(ROOT / "Resources/fr.lproj/Localizable.strings")
        for key in ["%lld 首", "暂无%@", "无法获得文件夹访问权限：%@"]:
            self.assertIn(key, french)
            self.assertIn('NSLocalizedString("' + key + '"', source)
        self.assertNotIn('count) 首"', source)
        self.assertNotIn('"暂无\\(title)"', source)

    def test_french_resources_cover_existing_keys_and_preserve_format_arguments(self):
        french = strings(ROOT / "Resources/fr.lproj/Localizable.strings")
        english = strings(ROOT / "Resources/en.lproj/Localizable.strings")
        self.assertTrue(set(english).issubset(french), sorted(set(english) - set(french)))
        for key, value in french.items():
            self.assertTrue(value.strip(), key)
            pattern = r'%(?:\d+\$)?(?:ll|l)?[@diuf]'
            self.assertEqual(sorted(re.findall(pattern, key)), sorted(re.findall(pattern, value)), key)
            self.assertIsNone(re.search(r'[\u4e00-\u9fff]', value), key)

    def test_french_is_declared_and_has_localized_permission_text(self):
        info = plistlib.loads((ROOT / "Info.plist").read_bytes())
        self.assertIn("fr", info["CFBundleLocalizations"])
        permission = strings(ROOT / "Resources/fr.lproj/InfoPlist.strings")
        self.assertIn("musique", permission["NSAppleMusicUsageDescription"])

    def test_reachable_static_ui_labels_have_french_translations(self):
        french = strings(ROOT / "Resources/fr.lproj/Localizable.strings")
        missing = set()
        pattern = r'(?:Text|Label|Button|Section|ContentUnavailableView|Picker|\.navigationTitle|\.accessibilityLabel|\.accessibilityHint|\.alert)\(\s*("(?:[^"\\]|\\.)*")'
        excluded = {"BaiduCoverSettingsView.swift", "PlayerInteractionTestHarness.swift", "AdaptiveStoreAssetHarness.swift"}
        for file in ROOT.rglob("*.swift"):
            if file.name in excluded:
                continue
            for raw in re.findall(pattern, file.read_text(encoding="utf-8")):
                if "\\(" in raw:
                    continue
                key = json.loads(raw)
                if re.search(r'[\u4e00-\u9fff]', key) and key not in french:
                    missing.add(key)
        self.assertEqual(missing, set())

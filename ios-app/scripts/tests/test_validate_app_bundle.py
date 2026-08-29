import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "validate_app_bundle.py"


class ValidateAppBundleTests(unittest.TestCase):
    def make_app(self, *, assets: bool, icon_declaration: bool) -> Path:
        root = Path(self.temp_dir.name)
        app = root / "LoveMusic.app"
        app.mkdir()
        info = {
            "CFBundleIdentifier": "com.example.lovemusic",
            "CFBundleDisplayName": "爱乐之城",
        }
        if icon_declaration:
            info["CFBundleIcons"] = {
                "CFBundlePrimaryIcon": {
                    "CFBundleIconFiles": ["AppIcon60x60"]
                }
            }
        (app / "Info.plist").write_bytes(
            plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
        )
        if assets:
            (app / "Assets.car").write_bytes(b"compiled-assets")
        return app

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_validator(self, app: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(app)],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

    def test_accepts_bundle_with_compiled_assets_and_primary_icon(self):
        result = self.run_validator(
            self.make_app(assets=True, icon_declaration=True)
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_bundle_without_compiled_assets(self):
        result = self.run_validator(
            self.make_app(assets=False, icon_declaration=True)
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Assets.car", result.stderr)

    def test_rejects_bundle_without_primary_icon_declaration(self):
        result = self.run_validator(
            self.make_app(assets=True, icon_declaration=False)
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CFBundleIcons", result.stderr)


if __name__ == "__main__":
    unittest.main()

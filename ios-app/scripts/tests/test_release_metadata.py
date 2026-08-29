from pathlib import Path
import plistlib
import unittest


IOS_ROOT = Path(__file__).resolve().parents[2]


class ReleaseMetadataTests(unittest.TestCase):
    def test_app_store_identity_matches_the_release_record(self) -> None:
        info = plistlib.loads((IOS_ROOT / "LocalMusicPlayer" / "Info.plist").read_bytes())
        project = (IOS_ROOT / "project.yml").read_text(encoding="utf-8")

        self.assertEqual(info["CFBundleDisplayName"], "爱乐之城-musicPlayer")
        self.assertIn('MARKETING_VERSION: "0.1"', project)
        self.assertIn('CURRENT_PROJECT_VERSION: "1"', project)

    def test_app_store_workflow_uses_macos_base64_decode_syntax(self) -> None:
        workflow = (IOS_ROOT.parent / ".github" / "workflows" / "ios-app-store.yml").read_text(
            encoding="utf-8"
        )

        self.assertNotIn("base64 --decode", workflow)
        self.assertEqual(workflow.count("base64 -D"), 3)


if __name__ == "__main__":
    unittest.main()

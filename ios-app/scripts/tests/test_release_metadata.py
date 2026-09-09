from pathlib import Path
import plistlib
import unittest


IOS_ROOT = Path(__file__).resolve().parents[2]


class ReleaseMetadataTests(unittest.TestCase):
    def test_app_store_identity_matches_the_release_record(self) -> None:
        info = plistlib.loads((IOS_ROOT / "LocalMusicPlayer" / "Info.plist").read_bytes())
        project = (IOS_ROOT / "project.yml").read_text(encoding="utf-8")

        self.assertEqual(info["CFBundleDisplayName"], "爱乐之城")
        self.assertFalse(info["ITSAppUsesNonExemptEncryption"])
        self.assertIn('MARKETING_VERSION: "0.2"', project)
        self.assertIn('CURRENT_PROJECT_VERSION: "36"', project)

    def test_app_store_workflow_uses_macos_base64_decode_syntax(self) -> None:
        workflow = (IOS_ROOT.parent / ".github" / "workflows" / "ios-app-store.yml").read_text(
            encoding="utf-8"
        )

        self.assertNotIn("base64 --decode", workflow)
        self.assertEqual(workflow.count("base64 -D"), 3)

    def test_release_documentation_requires_unique_incrementing_build_number(self) -> None:
        progress = (IOS_ROOT.parent / "docs" / "项目进度.md").read_text(encoding="utf-8")
        self.assertIn(
            "构建号必须大于 App Store Connect 中该 Bundle ID 最近一次成功上传的构建号",
            progress,
        )
        self.assertIn("同一个构建号一旦成功上传", progress)
        self.assertIn("不能替代 App 的构建号", progress)

    def test_app_store_signing_settings_are_target_scoped(self) -> None:
        project = (IOS_ROOT / "project.yml").read_text(encoding="utf-8")
        workflow = (IOS_ROOT.parent / ".github" / "workflows" / "ios-app-store.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("CODE_SIGN_ENTITLEMENTS", project)
        self.assertNotIn('PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME"', workflow)
        self.assertIn('AIYUE_PROFILE_NAME="$PROFILE_NAME"', workflow)
        self.assertIn('DEVELOPMENT_TEAM="$TEAM_ID"', workflow)
        self.assertNotIn('CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER"', workflow)
        self.assertIn("Run iOS simulator tests", workflow)
        self.assertIn("./ios-app/scripts/verify.sh", workflow)
        self.assertIn("CODE_SIGNING_ALLOWED=YES", workflow)
        self.assertIn("CODE_SIGNING_REQUIRED=YES", workflow)
        self.assertIn("Verify exported App Group entitlement", workflow)
        self.assertIn("group.com.luolihao.aiyuetransfer", workflow)


if __name__ == "__main__":
    unittest.main()

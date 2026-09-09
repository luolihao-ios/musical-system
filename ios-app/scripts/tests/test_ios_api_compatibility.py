from pathlib import Path
import unittest


IOS_ROOT = Path(__file__).resolve().parents[2]


class IOSAPICompatibilityTests(unittest.TestCase):
    def test_folder_bookmark_does_not_use_macos_only_security_scope_option(self) -> None:
        source = (
            IOS_ROOT
            / "LocalMusicPlayer"
            / "Import"
            / "AuthorizedMusicFolderAccess.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn(".withSecurityScope", source)
        self.assertIn("bookmarkData(options: []", source)
        self.assertIn("options: [.withoutUI]", source)


if __name__ == "__main__":
    unittest.main()

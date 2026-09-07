import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]


class LocalImportPolicyTests(unittest.TestCase):
    def test_import_menu_exposes_only_files_and_local_scan(self):
        source = (ROOT / "LocalMusicPlayer/Features/Library/ImportMenu.swift").read_text(encoding="utf-8")
        self.assertIn("scanLocalAudio", source)
        self.assertNotIn("completeResources", source)
        self.assertNotIn("authorizeFolders", source)

    def test_import_does_not_trigger_online_completion(self):
        source = (ROOT / "LocalMusicPlayer/Features/Library/LibraryModel.swift").read_text(encoding="utf-8")
        self.assertNotIn("Task { await self.completeMissingResources() }", source)

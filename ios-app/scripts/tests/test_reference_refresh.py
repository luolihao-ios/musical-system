"""Windows 静态接线检查；行为用 Swift 测试覆盖。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[2] / "LocalMusicPlayer"


class ReferenceRefreshTests(unittest.TestCase):
    def test_home_routes_shelves_to_the_shared_queue(self):
        view = (ROOT / "Features/Library/DiscoveryView.swift").read_text(encoding="utf-8")
        self.assertIn("recommendations.shelves", view)
        self.assertIn("toggleCatalogPreview(track, in:", view)

    def test_search_has_online_and_local_paths(self):
        view = (ROOT / "Features/Library/OnlineCatalogSearchView.swift").read_text(encoding="utf-8")
        self.assertIn("Picker", view)
        self.assertIn("model.tracks", view)
        self.assertIn("model.play(track", view)

    def test_player_can_switch_appearance_without_switching_engine(self):
        view = (ROOT / "Features/NowPlaying/NowPlayingView.swift").read_text(encoding="utf-8")
        self.assertIn("case .vinyl:", view)
        self.assertIn("case .classic:", view)
        self.assertIn("model.scheduleSleepTimer", view)

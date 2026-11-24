"""Windows 静态接线检查；行为用 Swift 测试覆盖。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[2] / "LocalMusicPlayer"


class ReferenceRefreshTests(unittest.TestCase):
    def test_home_routes_shelves_to_the_shared_queue(self):
        view = (ROOT / "Features/Library/DiscoveryView.swift").read_text(encoding="utf-8")
        self.assertIn("recommendations.shelves", view)
        self.assertIn("toggleCatalogPreview(track, in:", view)

    def test_search_is_online_only_with_visible_search_bar(self):
        view = (ROOT / "Features/Library/OnlineCatalogSearchView.swift").read_text(encoding="utf-8")
        self.assertIn("search.submit", view)
        self.assertIn("OnlineCatalog.shared.search", view)
        self.assertIn("scrollDismissesKeyboard(.immediately)", view)
        self.assertIn("KeyboardDismissTapBridge", view)
        self.assertNotIn('Picker("音乐来源"', view)

    def test_player_can_switch_appearance_without_switching_engine(self):
        view = (ROOT / "Features/NowPlaying/NowPlayingView.swift").read_text(encoding="utf-8")
        self.assertIn("case .vinyl:", view)
        self.assertIn("case .classic:", view)
        self.assertIn("model.scheduleSleepTimer", view)
        self.assertIn("nextTrackPreviewPage", view)
        self.assertIn("nextTrackDragOffset", view)

    def test_cached_remote_image_and_discovery_card_contain_hit_testing(self):
        image = (ROOT / "Features/Shared/CachedRemoteImage.swift").read_text(encoding="utf-8")
        discovery = (ROOT / "Features/Library/DiscoveryView.swift").read_text(encoding="utf-8")
        self.assertIn("allowsHitTesting(false)", image)
        self.assertIn("contentShape(", image)
        self.assertIn("discovery.search", discovery)
        self.assertIn(".contentShape(RoundedRectangle(cornerRadius: 24", discovery)

    def test_recommendation_engine_and_taste_signals_are_wired(self):
        catalog = (ROOT / "Import/OnlineCatalog.swift").read_text(encoding="utf-8")
        playback = (ROOT / "Playback/PlaybackController.swift").read_text(encoding="utf-8")
        container = (ROOT / "App/AppContainer.swift").read_text(encoding="utf-8")
        self.assertIn("RecommendationEngine.rankAndDiversify", catalog)
        self.assertIn("RecommendationEngine.recallPlan", catalog)
        self.assertIn("RecommendationEngine.continuationQueries", catalog)
        self.assertIn("onTrackSessionEnded", playback)
        self.assertIn("TasteProfileStore.shared", container)

    def test_classic_ipod_fullscreen_buttons_and_long_press_skin_picker(self):
        now_playing = (ROOT / "Features/NowPlaying/NowPlayingView.swift").read_text(encoding="utf-8")
        classic = (ROOT / "Features/NowPlaying/ClassicPlayerVisual.swift").read_text(encoding="utf-8")
        self.assertIn("onLongPressGesture", now_playing)
        self.assertIn("chassisBackground", now_playing)
        self.assertIn("ipod.previous", classic)
        self.assertIn("ipod.next", classic)
        self.assertIn("ipod.playPause", classic)
        self.assertIn(".contentShape(Rectangle())", classic)

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

    def test_app_does_not_automatically_rescan_music_during_startup(self) -> None:
        source = (
            IOS_ROOT / "LocalMusicPlayer" / "App" / "LocalMusicPlayerApp.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn(
            ".task { await container.libraryModel.scanLocalAudio() }",
            source,
        )

    def test_mini_player_keeps_hit_target_and_does_not_add_extra_waveform(self) -> None:
        mini_player = (
            IOS_ROOT
            / "LocalMusicPlayer"
            / "Features"
            / "Shared"
            / "MiniPlayerView.swift"
        ).read_text(encoding="utf-8")
        now_playing = (
            IOS_ROOT
            / "LocalMusicPlayer"
            / "Features"
            / "NowPlaying"
            / "NowPlayingView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("coordinateSpace: .global", mini_player)
        self.assertNotIn("DispatchQueue.main.asyncAfter", mini_player)
        self.assertNotIn(".offset(y:", mini_player)
        self.assertIn("bottomLeadingRadius: 0", mini_player)
        self.assertIn("bottomTrailingRadius: 0", mini_player)
        self.assertEqual(now_playing.count("PlaybackWaveformView("), 1)
        self.assertIn("ZStack(alignment: .bottom)", now_playing)

    def test_mini_player_is_bottom_anchored_instead_of_safe_area_inset(self) -> None:
        app_shell = (
            IOS_ROOT
            / "LocalMusicPlayer"
            / "App"
            / "AppShellView.swift"
        ).read_text(encoding="utf-8")

        dock = (IOS_ROOT / "LocalMusicPlayer" / "Features" / "Shared" / "PlayerDockContainer.swift").read_text(encoding="utf-8")
        self.assertIn("PlayerDockContainer(", app_shell)
        self.assertNotIn(".sheet(isPresented: $showNowPlaying)", app_shell)
        self.assertIn(".ignoresSafeArea(.container, edges: .bottom)", dock)
        self.assertNotIn(".safeAreaInset(edge: .bottom", app_shell)


if __name__ == "__main__":
    unittest.main()

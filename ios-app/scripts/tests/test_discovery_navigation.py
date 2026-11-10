"""Windows 上核查产品首页和本地入口的接线；原生交互另有 XCTest。"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[2] / "LocalMusicPlayer"


class DiscoveryNavigationTests(unittest.TestCase):
    def test_home_is_not_a_local_library_or_source_toggle(self):
        shell = (ROOT / "App/AppShellView.swift").read_text(encoding="utf-8")
        home = shell.split('Label("首页"', 1)[0]
        self.assertIn("DiscoveryView(", home)
        self.assertNotIn("LibraryView(", home)
        self.assertNotIn('Picker("音乐来源"', home)

    def test_my_tab_contains_local_library_and_settings(self):
        shell = (ROOT / "App/AppShellView.swift").read_text(encoding="utf-8")
        mine = shell.split('.tag(2)', 1)[1]
        self.assertIn("LibraryView(model: container.libraryModel, personalLibrary: true", mine)
        self.assertIn('Label("我的"', mine)
        self.assertIn('Label("收藏"', mine)
        self.assertIn('Label("设置"', mine)

    def test_production_launch_defaults_to_the_light_gradient(self):
        app = (ROOT / "App/LocalMusicPlayerApp.swift").read_text(encoding="utf-8")
        content = app.split("private var applicationContent:", 1)[1]
        self.assertIn("PlayerAppearance.gradient", app)
        self.assertIn(".preferredColorScheme(appearance.colorScheme)", content)

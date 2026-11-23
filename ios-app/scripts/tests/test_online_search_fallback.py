"""Windows 接线检查，供应商结果、回退和播放限制另有原生测试。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[2] / "LocalMusicPlayer"


class OnlineSearchFallbackTests(unittest.TestCase):
    def test_catalog_streams_results_from_independent_sources(self):
        view = (ROOT / "Features/Library/OnlineCatalogSearchView.swift").read_text(encoding="utf-8")
        service = (ROOT / "Import/OnlineCatalog.swift").read_text(encoding="utf-8")
        self.assertIn("onUpdate:", view)
        self.assertIn("withTaskGroup", service.split("func search(query:", 1)[1].split("private func searchJamendo", 1)[0])

    def test_itunes_is_an_online_search_source_but_not_a_home_source(self):
        service = (ROOT / "Import/OnlineCatalog.swift").read_text(encoding="utf-8")
        self.assertIn("case .itunes:", service)
        self.assertNotIn("searchITunes", service.split("func discoveryFeed", 1)[1].split("private func searchInternetArchive", 1)[0])

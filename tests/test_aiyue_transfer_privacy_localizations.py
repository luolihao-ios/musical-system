from pathlib import Path
import unittest


class AiYueTransferPrivacyLocalizationTests(unittest.TestCase):
    def test_each_app_store_language_has_a_matching_privacy_page(self):
        expected = {
            'docs/aiyuetransfer/privacy/zh-Hans/index.html': '我们不收集你的数据',
            'docs/aiyuetransfer/privacy/zh-Hant/index.html': '我們不收集你的資料',
            'docs/aiyuetransfer/privacy/en/index.html': 'No data is collected',
        }
        for name, heading in expected.items():
            page = Path(name)
            self.assertTrue(page.is_file(), f'缺少本地化隐私政策页：{name}')
            self.assertIn(heading, page.read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()

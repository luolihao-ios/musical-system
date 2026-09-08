from pathlib import Path
import unittest


class AiYueTransferPrivacyPageTests(unittest.TestCase):
    def test_privacy_page_discloses_local_only_processing_and_contact(self):
        page = Path('docs/aiyuetransfer/privacy/index.html')
        self.assertTrue(page.is_file(), '爱乐互传隐私政策页尚未创建')
        content = page.read_text(encoding='utf-8')
        self.assertIn('不收集', content)
        self.assertIn('本地网络', content)
        self.assertIn('mailto:luolihao1234@gmail.com', content)
        self.assertIn('No data is collected', content)


if __name__ == '__main__':
    unittest.main()

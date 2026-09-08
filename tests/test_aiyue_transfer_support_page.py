from pathlib import Path
import unittest


class AiYueTransferSupportPageTests(unittest.TestCase):
    def test_support_page_has_contact_and_usage_help(self):
        page = Path('docs/aiyuetransfer/support/index.html')
        self.assertTrue(page.is_file(), '爱乐互传技术支持页尚未创建')
        content = page.read_text(encoding='utf-8')
        self.assertIn('爱乐互传', content)
        self.assertIn('mailto:luolihao1234@gmail.com', content)
        self.assertIn('同一 Wi-Fi', content)
        self.assertIn('访问码', content)
        self.assertIn('<html lang="zh-CN">', content)


if __name__ == '__main__':
    unittest.main()

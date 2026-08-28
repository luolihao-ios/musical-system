from pathlib import Path
import unittest


PAGES_ROOT = Path(__file__).resolve().parents[2] / "docs"
DEPLOY_WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github" / "workflows" / "deploy-pages.yml"
)


class AppStorePagesTests(unittest.TestCase):
    def test_privacy_policy_discloses_local_only_data_practices(self) -> None:
        privacy_page = (PAGES_ROOT / "privacy" / "index.html").read_text(
            encoding="utf-8"
        )

        self.assertIn("爱乐之城-musicPlayer", privacy_page)
        self.assertIn("不会上传", privacy_page)
        self.assertIn("不会收集", privacy_page)
        self.assertIn("不会跟踪", privacy_page)
        self.assertIn("luolihao1234@gmail.com", privacy_page)

    def test_support_page_provides_contact_and_core_feature_help(self) -> None:
        support_page = (PAGES_ROOT / "support" / "index.html").read_text(
            encoding="utf-8"
        )

        self.assertIn("爱乐之城-musicPlayer", support_page)
        self.assertIn("导入", support_page)
        self.assertIn("本地音乐", support_page)
        self.assertIn("luolihao1234@gmail.com", support_page)

    def test_pages_workflow_publishes_the_docs_directory(self) -> None:
        workflow = DEPLOY_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("actions/upload-pages-artifact", workflow)
        self.assertIn("path: docs", workflow)
        self.assertIn("actions/deploy-pages", workflow)


if __name__ == "__main__":
    unittest.main()

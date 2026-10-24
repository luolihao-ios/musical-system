"""防止发布工作流再次退回仓库专用的旧密钥名。"""
from pathlib import Path
import unittest


class TeamSecretsTests(unittest.TestCase):
    def test_release_workflows_reference_shared_organization_names(self):
        folder = Path(__file__).resolve().parents[2] / ".github/workflows"
        for name in ("ios-app-store.yml", "aiyue-next-release.yml", "aiyue-transfer-release.yml"):
            with self.subTest(workflow=name):
                source = (folder / name).read_text(encoding="utf-8")
                for shared in ("APP_STORE_CONNECT_API_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_API_KEY_BASE64"):
                    self.assertIn("secrets." + shared, source)
                for old in ("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_PRIVATE_KEY_BASE64"):
                    self.assertNotIn("secrets." + old, source)


if __name__ == "__main__":
    unittest.main()

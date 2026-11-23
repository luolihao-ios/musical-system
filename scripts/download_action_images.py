"""按 HTTP Range 只取 GitHub 工件中的截图，避免下载整份大型 xcresult。"""
import argparse
import io
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.request
import zipfile


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


class RemoteZip(io.RawIOBase):
    def __init__(self, artifact):
        self.artifact = artifact
        self.position = 0
        self.refresh()
        with urllib.request.urlopen(urllib.request.Request(self.url, method="HEAD"), timeout=40) as response:
            self.length = int(response.headers["Content-Length"])

    def refresh(self):
        token = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()
        request = urllib.request.Request(f"https://api.github.com/repos/luolihao-ios/musical-system/actions/artifacts/{self.artifact}/zip",
            headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json"})
        opener = urllib.request.build_opener(NoRedirect())
        try:
            opener.open(request, timeout=40)
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307):
                raise RuntimeError(f"GitHub 工件授权失败：HTTP {error.code}") from None
            self.url = error.headers["Location"]
            if not self.url.startswith("https://"):
                raise ValueError("工件下载地址必须为 HTTPS")

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.length + offset
        return self.position

    def read(self, count=-1):
        end = self.length if count < 0 else min(self.length, self.position + count)
        if self.position >= end:
            return b""
        for attempt in range(2):
            request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.position}-{end-1}"})
            try:
                with urllib.request.urlopen(request, timeout=50) as response:
                    if response.status != 206:
                        raise RuntimeError("工件存储不支持局部下载")
                    data = response.read()
                self.position += len(data)
                return data
            except urllib.error.HTTPError as error:
                if error.code == 403 and attempt == 0:
                    self.refresh()
                    continue
                raise RuntimeError(f"工件局部下载失败：HTTP {error.code}") from None
        raise RuntimeError("工件下载失败")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--device", choices=("iphone", "ipad", "duo"), required=True)
    args = parser.parse_args()
    folder = args.device + "-images/"
    with zipfile.ZipFile(RemoteZip(args.artifact)) as archive:
        manifest_name = folder + "manifest.json"
        if manifest_name not in archive.namelist():
            raise ValueError("工件没有对应设备的截图")
        manifest_bytes = archive.read(manifest_name)
        manifest = json.loads(manifest_bytes)
        originals = {attachment["exportedFileName"] for test in manifest for attachment in test["attachments"]
                     if attachment["suggestedHumanReadableName"].startswith("filesend-") and not attachment["isAssociatedWithFailure"]}
        members = [folder + name for name in sorted(originals)]
        for name in members:
            target = args.destination / name
            if not target.resolve().is_relative_to(args.destination.resolve()):
                raise ValueError("截图路径越界")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(name))
            print("已下载截图工件文件：", target.name, flush=True)
        (args.destination / manifest_name).write_bytes(manifest_bytes)


if __name__ == "__main__":
    main()

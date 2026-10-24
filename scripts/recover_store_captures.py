"""从已通过的原生测试工件恢复四页截图，不改动任何截图像素。"""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys

def recover(source: Path, destination: Path):
    records = []
    for device in ("iphone", "ipad", "duo"):
        folder = source / f"{device}-images"
        manifest = json.loads((folder / "manifest.json").read_text())
        attachments = [item for test in manifest
                       if test["testIdentifier"] == "StoreAssetCaptureTests/testCaptureFourProductionPages()"
                       for item in test["attachments"] if not item["isAssociatedWithFailure"]]
        for page in ("01-local", "02-artwork", "03-lyrics", "04-online"):
            matches = [item for item in attachments if item["suggestedHumanReadableName"].startswith(f"adaptive-{page}_")]
            if len(matches) != 1:
                raise ValueError(f"{device}/{page} 缺少唯一成功截图")
            file = folder / matches[0]["exportedFileName"]
            data = file.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError("不是 PNG")
            width, height = struct.unpack_from(">II", data, 16)
            target = destination / device / f"{page}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)
            records.append({"device": device, "file": str(target.relative_to(destination)),
                            "width": width, "height": height, "sourceRun": 40077447803,
                            "sha256": hashlib.sha256(data).hexdigest()})
    for file in source.glob("simctl*help.txt"):
        shutil.copyfile(file, destination / file.name)
    (destination / "原图证据.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(records, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    recover(Path(sys.argv[1]), Path(__file__).resolve().parents[1] / "marketing/app-store-2026-10-24/sources/adaptive")

"""从 file send 原生测试工件提取五种功能截图，保留原像素与来源。"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

PAGES = ("connect", "receive", "send", "edit", "completed")


def recover(source, destination, run_id, devices=("iphone", "ipad", "duo")):
    records = []
    for device in devices:
        folder = source / f"{device}-images"
        manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
        attachments = [attachment for test in manifest
                       if test["testIdentifier"] == "StoreAssetCaptureTests/testFiveProductionTransferPagesFillDevice()"
                       for attachment in test["attachments"] if not attachment["isAssociatedWithFailure"]]
        for page in PAGES:
            matches = [item for item in attachments if item["suggestedHumanReadableName"].startswith(f"filesend-{page}_")]
            if len(matches) != 1:
                raise ValueError(f"{device}/{page} 缺少唯一成功截图")
            original = folder / matches[0]["exportedFileName"]
            data = original.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError("云端截图不是 PNG")
            width, height = struct.unpack_from(">II", data, 16)
            target = destination / device / f"{page}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, target)
            records.append({"device": device, "page": page, "file": str(target.relative_to(destination)),
                            "width": width, "height": height, "sourceRun": run_id,
                            "sha256": hashlib.sha256(data).hexdigest()})
    (destination / "原图证据.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(records, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--device", choices=("iphone", "ipad", "duo"))
    args = parser.parse_args()
    recover(args.source, Path(__file__).resolve().parents[1] / "marketing/file-send-2026-10-26/sources/actual", args.run_id,
            (args.device,) if args.device else ("iphone", "ipad", "duo"))

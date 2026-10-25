"""按实际可用性准备三设备验证需要的运行时，不以下载命令状态代替验收。"""
import argparse
import json
from pathlib import Path
import subprocess

DUO = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"


def ensure_runtime(run):
    def inspect():
        result = run(["xcrun", "simctl", "list", "runtimes", "-j"])
        if result.returncode:
            raise RuntimeError(f"读取模拟器运行时失败（{result.returncode}）：{result.stderr}")
        return json.loads(result.stdout)

    def available(data):
        return any(item.get("isAvailable") and item.get("version") == "27.1"
                   and any(device.get("identifier") == DUO for device in item.get("supportedDeviceTypes", []))
                   for item in data["runtimes"])

    data = inspect()
    if available(data):
        print("iOS 27.1 已安装且支持目标设备，直接复用。", flush=True)
        return data
    result = run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", "27.1", "-architectureVariant", "arm64"])
    print(f"运行时准备命令退出码：{result.returncode}", flush=True)
    if result.stdout:
        print(result.stdout, flush=True)
    if result.stderr:
        print(result.stderr, flush=True)
    data = inspect()
    if not available(data):
        raise RuntimeError(f"iOS 27.1 运行时不可用或不支持目标设备；下载命令退出码 {result.returncode}")
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data = ensure_runtime(lambda command: subprocess.run(command, capture_output=True, text=True, check=False))
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

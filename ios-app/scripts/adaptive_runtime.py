"""选择确实支持目标机型的运行时；iOS 27.1 当前只支持 Duo。"""
import argparse
import json
from pathlib import Path


def runtime_for_device(runtimes, device_type):
    compatible = [runtime for runtime in runtimes if runtime.get("isAvailable") and
        any(device.get("identifier") == device_type for device in runtime.get("supportedDeviceTypes", []))]
    if not compatible:
        raise ValueError(f"没有兼容运行时：{device_type}")
    return max(compatible, key=lambda item: tuple(int(n) for n in item["version"].split(".")))["identifier"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtimes", type=Path, required=True)
    parser.add_argument("--type", required=True)
    args = parser.parse_args()
    print(runtime_for_device(json.loads(args.runtimes.read_text())["runtimes"], args.type))

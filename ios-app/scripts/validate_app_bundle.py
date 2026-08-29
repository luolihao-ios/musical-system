#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: validate_app_bundle.py <App.app>", file=sys.stderr)
        return 2

    app = Path(sys.argv[1])
    if not (app / "Assets.car").is_file():
        print("Missing compiled asset catalog: Assets.car", file=sys.stderr)
        return 1

    info_path = app / "Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        print(f"Cannot read Info.plist: {error}", file=sys.stderr)
        return 1

    icons = info.get("CFBundleIcons")
    primary = icons.get("CFBundlePrimaryIcon") if isinstance(icons, dict) else None
    has_icon = isinstance(primary, dict) and bool(
        primary.get("CFBundleIconFiles") or primary.get("CFBundleIconName")
    )
    if not has_icon:
        print(
            "Missing CFBundleIcons/CFBundlePrimaryIcon declaration",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())

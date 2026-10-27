#!/usr/bin/env python3
"""把商店候选图标应用到各平台（可选步骤）。

当前仓库图标包含浙江大学校徽/校名元素，AppGallery 审核存在第三方商标风险。
本脚本把 store/appgallery/icon 下的原创时钟图标写入 Android、HarmonyOS、
iOS 与 assets/logo.png。执行前请确认这是你想要的产品决策；
旧图标仍可从 git 历史恢复。

鸿蒙单层图标规范要求 1024×1024，包内任何单层图标都不能小于该尺寸，
否则上架检测会报「应用图标单层图尺寸不满足规范」。

用法: python tool/store/apply_store_icon.py
"""

from __future__ import annotations

import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "store" / "appgallery" / "icon" / "helechron_icon_1024.png"

TARGETS: dict[Path, tuple[int, int]] = {
    ROOT / "assets" / "logo.png": (512, 512),
    ROOT / "ohos" / "AppScope" / "resources" / "base" / "media" / "app_icon.png": (1024, 1024),
    # entry 模块图标同样会被打进 HAP，必须满足鸿蒙单层图 1024×1024 规范
    ROOT / "ohos" / "entry" / "src" / "main" / "resources" / "base" / "media" / "icon.png": (1024, 1024),
    ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-mdpi" / "ic_launcher.png": (48, 48),
    ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-hdpi" / "ic_launcher.png": (72, 72),
    ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xhdpi" / "ic_launcher.png": (96, 96),
    ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xxhdpi" / "ic_launcher.png": (144, 144),
    ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xxxhdpi" / "ic_launcher.png": (192, 192),
}

IOS_DIR = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_RE = re.compile(r"Icon-App-([\d.]+)x([\d.]+)@(\d+)x\.png$")


def _save(image: Image.Image, size: tuple[int, int], target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize(size, Image.LANCZOS).convert("RGB").save(target, optimize=True)
    print(f"{target.relative_to(ROOT)}  {size[0]}x{size[1]}")


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"找不到图标母版: {MASTER}")
    master = Image.open(MASTER).convert("RGB")

    for target, size in TARGETS.items():
        _save(master, size, target)

    if IOS_DIR.exists():
        for icon in sorted(IOS_DIR.glob("Icon-App-*.png")):
            match = IOS_RE.match(icon.name)
            if not match:
                continue
            width = round(float(match.group(1)) * int(match.group(3)))
            height = round(float(match.group(2)) * int(match.group(3)))
            _save(master, (width, height), icon)


if __name__ == "__main__":
    main()

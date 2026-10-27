#!/usr/bin/env python3
"""把单层应用图标拆成分层图标（鸿蒙 NEXT Adaptive Icon）。

背景是纯色、前景是透明底上的图形，两者都是 1024×1024，系统会取中间 2/3
区域叠加显示。资源结构与引用方式见 OpenHarmony 官方文档
`application-dev/quick-start/layered-image.md`：

    AppScope/resources/base/media/layered_image.json
    entry/src/main/resources/base/media/layered_image.json
    {
      "layered-image": {
        "background": "$media:background",
        "foreground": "$media:foreground"
      }
    }

用法: python tool/store/make_layered_icon.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "store" / "appgallery" / "icon" / "helechron_icon_1024.png"
SIZE = 1024

LAYERED_JSON = {
    "layered-image": {
        "background": "$media:background",
        "foreground": "$media:foreground",
    }
}

TARGETS = [
    ROOT / "ohos" / "AppScope" / "resources" / "base" / "media",
    ROOT / "ohos" / "entry" / "src" / "main" / "resources" / "base" / "media",
]


def split_layers(master: Image.Image) -> tuple[Image.Image, Image.Image]:
    """按背景色把单层图标拆成前景层与背景层。

    背景是平涂色，前景图形与背景色差距明显，所以按颜色距离生成 alpha 即可，
    边缘的抗锯齿像素会得到 0~255 之间的过渡值。
    """
    rgb = master.convert("RGB")
    arr = np.asarray(rgb, dtype=np.float32)
    bg = arr[0, 0].copy()  # 左上角是背景色

    distance = np.abs(arr - bg).max(axis=2)
    # 0~8 视为纯背景，8~32 线性过渡到完全不透明
    alpha = np.clip((distance - 8.0) / 24.0, 0.0, 1.0) * 255.0

    foreground = np.dstack([arr, alpha]).astype(np.uint8)
    background = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
    background[..., :3] = bg.astype(np.uint8)
    background[..., 3] = 255

    return Image.fromarray(foreground, "RGBA"), Image.fromarray(background, "RGBA")


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"找不到图标母版: {MASTER}")

    master = Image.open(MASTER).convert("RGB")
    if master.size != (SIZE, SIZE):
        raise SystemExit(f"母版尺寸应为 {SIZE}x{SIZE}，实际为 {master.size}")

    foreground, background = split_layers(master)

    for target in TARGETS:
        target.mkdir(parents=True, exist_ok=True)
        foreground.save(target / "foreground.png", optimize=True)
        background.save(target / "background.png", optimize=True)
        (target / "layered_image.json").write_text(
            json.dumps(LAYERED_JSON, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"{target.relative_to(ROOT)}  foreground.png / background.png / layered_image.json")

    # 启动页图标用单层图（官方示例同样用独立的 startIcon.png）
    start_icon = TARGETS[1] / "startIcon.png"
    master.save(start_icon, optimize=True)
    print(f"{start_icon.relative_to(ROOT)}  {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()

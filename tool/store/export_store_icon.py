#!/usr/bin/env python3
"""把选中的 1024 图标母版导出为商店尺寸和宣传图。

用法:
  python tool/store/export_store_icon.py store/appgallery/icon/options2/option_k.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from generate_icon import load_font

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "appgallery" / "icon"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "source",
        nargs="?",
        default=str(OUT / "options2" / "option_k.png"),
        help="1024x1024 图标母版",
    )
    args = parser.parse_args()

    source = Path(args.source)
    if not source.is_absolute():
        source = ROOT / source
    if not source.exists():
        raise SystemExit(f"找不到图标母版: {source}")

    master = Image.open(source).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    master.save(OUT / "helechron_icon_1024.png", optimize=True)
    master.resize((512, 512), Image.LANCZOS).save(OUT / "helechron_icon_512.png", optimize=True)
    master.resize((216, 216), Image.LANCZOS).save(OUT / "helechron_icon_216.png", optimize=True)

    banner = Image.new("RGB", (1080, 450), (247, 250, 255))
    mark = master.resize((330, 330), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", mark.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, mark.width - 1, mark.height - 1], radius=72, fill=255
    )
    banner.paste(mark, (70, 60), mask)
    draw = ImageDraw.Draw(banner)
    draw.text((450, 132), "Helechron", font=load_font(64), fill=(28, 28, 30))
    draw.text((452, 220), "课程表 · 日程 · DDL · 成绩", font=load_font(28), fill=(95, 100, 110))
    draw.text((452, 268), "HarmonyOS NEXT / Android", font=load_font(22), fill=(120, 126, 138))
    banner.save(OUT / "helechron_banner_1080x450.png", optimize=True)

    print(f"exported from {source}")
    print(f"wrote {OUT / 'helechron_icon_1024.png'}")
    print(f"wrote {OUT / 'helechron_icon_512.png'}")
    print(f"wrote {OUT / 'helechron_icon_216.png'}")
    print(f"wrote {OUT / 'helechron_banner_1080x450.png'}")


if __name__ == "__main__":
    main()

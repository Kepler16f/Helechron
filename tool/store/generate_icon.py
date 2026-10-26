#!/usr/bin/env python3
"""图标绘制工具函数与 A 方案原型。

最终商店图标请用 export_store_icon.py 导出，避免覆盖已选定的 K 方案：
  python tool/store/export_store_icon.py store/appgallery/icon/options2/option_k.png
  python tool/store/apply_store_icon.py

输出:
  store/appgallery/icon/options/option_a.png
  store/appgallery/icon/options/option_a_512.png
  store/appgallery/icon/options/option_a_216.png
  store/appgallery/icon/options/option_a_banner.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "appgallery" / "icon" / "options"

SCALE = 4
SIZE = 1024
CANVAS = SIZE * SCALE


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


def gradient(size: int, start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    # 先在小图上生成渐变再放大，避免逐像素处理 4096² 画布。
    small_size = 256
    small = Image.new("RGB", (small_size, small_size))
    pixels = small.load()
    for y in range(small_size):
        for x in range(small_size):
            t = (x + y) / (2 * (small_size - 1))
            pixels[x, y] = lerp(start, end, t)
    return small.resize((size, size), Image.BICUBIC)


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def rounded_line(draw: ImageDraw.ImageDraw, start: tuple[float, float], end: tuple[float, float],
                 width: int, fill: tuple[int, int, int, int]) -> None:
    draw.line([start, end], fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in (start, end):
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


def build_master() -> Image.Image:
    image = gradient(CANVAS, (58, 122, 245), (108, 198, 250)).convert("RGBA")
    draw = ImageDraw.Draw(image, "RGBA")
    center = CANVAS // 2

    # 柔和光晕，避免纯色背景在深色主题下显得单薄
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_center = SIZE // 2
    glow_radius = 430
    glow_draw.ellipse(
        [glow_center - glow_radius, glow_center - glow_radius,
         glow_center + glow_radius, glow_center + glow_radius],
        fill=(255, 255, 255, 40),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    glow = glow.resize((CANVAS, CANVAS), Image.LANCZOS)
    image = Image.alpha_composite(image, glow)

    draw = ImageDraw.Draw(image, "RGBA")

    # 表盘
    radius = 318 * SCALE
    draw.ellipse(
        [center - radius, center - radius, center + radius, center + radius],
        fill=(255, 255, 255, 250),
    )

    # 刻度
    for tick in range(12):
        angle = math.radians(tick * 30 - 90)
        outer = radius - 34 * SCALE
        inner = outer - (34 if tick % 3 == 0 else 20) * SCALE
        width = (14 if tick % 3 == 0 else 9) * SCALE
        x1 = center + math.cos(angle) * inner
        y1 = center + math.sin(angle) * inner
        x2 = center + math.cos(angle) * outer
        y2 = center + math.sin(angle) * outer
        rounded_line(draw, (x1, y1), (x2, y2), width, (73, 137, 240, 235))

    # 指针：10:10，视觉上更平衡
    def hand(angle_deg: float, length: int, width: int) -> None:
        angle = math.radians(angle_deg - 90)
        end = (center + math.cos(angle) * length * SCALE,
               center + math.sin(angle) * length * SCALE)
        rounded_line(draw, (center, center), end, width * SCALE, (45, 103, 226, 255))

    hand(305, 170, 34)   # 时针
    hand(60, 246, 24)    # 分针

    # 中心圆点
    dot = 30 * SCALE
    draw.ellipse([center - dot, center - dot, center + dot, center + dot],
                 fill=(45, 103, 226, 255))
    draw.ellipse([center - dot // 3, center - dot // 3, center + dot // 3, center + dot // 3],
                 fill=(255, 255, 255, 255))

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    master = build_master()
    master.save(OUT / "option_a.png", optimize=True)
    master.resize((512, 512), Image.LANCZOS).save(OUT / "option_a_512.png", optimize=True)
    master.resize((216, 216), Image.LANCZOS).save(OUT / "option_a_216.png", optimize=True)

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
    banner.save(OUT / "option_a_banner.png", optimize=True)
    print(f"wrote prototype icons to {OUT}")
    print("最终商店图标请用 export_store_icon.py 导出，避免覆盖已选方案。")


if __name__ == "__main__":
    main()

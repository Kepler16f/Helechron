#!/usr/bin/env python3
"""第二套图标方案：换配色与主题，供用户选择。

输出:
  store/appgallery/icon/options2/option_g.png ... option_l.png
  store/appgallery/icon/options2/contact_sheet.png / .pdf
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from generate_icon import gradient, load_font, rounded_line

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "appgallery" / "icon" / "options2"

S = 4
SIZE = 1024
CANVAS = SIZE * S
CENTER = CANVAS // 2


def sc(value: float) -> int:
    return int(value * S)


def mesh_glow(image: Image.Image, blobs: list[tuple[tuple[int, int, int, int], tuple[int, int, int, int]]]) -> Image.Image:
    """在 1024 画布上叠柔和色块，再放大，营造渐变/玻璃质感。"""
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    for box, color in blobs:
        draw.ellipse(box, fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(110)).resize((CANVAS, CANVAS), Image.LANCZOS)
    return Image.alpha_composite(image, glow)


def clock_hands(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float,
                color: tuple[int, int, int, int], width: int) -> None:
    # 305° / 60° 对应 10:10，视觉上最平衡
    for deg, ratio, stroke in [(305, 0.50, width), (60, 0.74, int(width * 0.68))]:
        angle = math.radians(deg - 90)
        rounded_line(
            draw,
            (sc(cx), sc(cy)),
            (sc(cx + math.cos(angle) * radius * ratio),
             sc(cy + math.sin(angle) * radius * ratio)),
            sc(stroke),
            color,
        )
    draw.ellipse([sc(cx - width * 0.55), sc(cy - width * 0.55),
                  sc(cx + width * 0.55), sc(cy + width * 0.55)], fill=color)


def design_dark_glass() -> Image.Image:
    image = gradient(CANVAS, (8, 13, 26), (24, 38, 70)).convert("RGBA")
    image = mesh_glow(image, [
        ((140, 80, 880, 820), (34, 211, 238, 70)),
        ((300, 240, 760, 700), (129, 140, 248, 80)),
    ])
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle(
        [sc(212), sc(212), sc(812), sc(812)], radius=sc(168),
        fill=(6, 12, 26, 150), outline=(255, 255, 255, 60), width=sc(3),
    )
    cx = cy = 512
    radius = 196
    draw.ellipse(
        [sc(cx - radius), sc(cy - radius), sc(cx + radius), sc(cy + radius)],
        outline=(255, 255, 255, 235), width=sc(26),
    )
    for deg in (-90, 0, 90, 180):
        angle = math.radians(deg - 90)
        rounded_line(
            draw,
            (sc(cx + math.cos(angle) * (radius - 36)), sc(cy + math.sin(angle) * (radius - 36))),
            (sc(cx + math.cos(angle) * (radius - 8)), sc(cy + math.sin(angle) * (radius - 8))),
            sc(15), (103, 232, 249, 255),
        )
    clock_hands(draw, cx, cy, radius, (103, 232, 249, 255), 36)
    draw.ellipse([sc(cx - 12), sc(cy - 12), sc(cx + 12), sc(cy + 12)], fill=(255, 255, 255, 255))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_warm_clock() -> Image.Image:
    image = gradient(CANVAS, (255, 102, 74), (255, 196, 92)).convert("RGBA")
    image = mesh_glow(image, [
        ((80, 60, 620, 600), (255, 255, 255, 55)),
        ((560, 500, 1000, 980), (190, 60, 20, 50)),
    ])
    draw = ImageDraw.Draw(image, "RGBA")
    cx = cy = 512
    radius = 218
    draw.ellipse(
        [sc(cx - radius - 10), sc(cy - radius - 10), sc(cx + radius + 10), sc(cy + radius + 10)],
        fill=(120, 45, 15, 45),
    )
    draw.ellipse(
        [sc(cx - radius), sc(cy - radius), sc(cx + radius), sc(cy + radius)],
        fill=(255, 247, 234, 255),
    )
    for tick in range(12):
        angle = math.radians(tick * 30 - 90)
        outer = radius - 26
        inner = outer - (26 if tick % 3 == 0 else 14)
        rounded_line(
            draw,
            (sc(cx + math.cos(angle) * inner), sc(cy + math.sin(angle) * inner)),
            (sc(cx + math.cos(angle) * outer), sc(cy + math.sin(angle) * outer)),
            sc(13 if tick % 3 == 0 else 8),
            (255, 138, 61, 245),
        )
    clock_hands(draw, cx, cy, radius, (74, 44, 26, 255), 38)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_mint_grid() -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), (223, 245, 233, 255))
    # 轻微纸张颗粒
    noise = Image.new("L", (SIZE, SIZE), 0)
    pixels = noise.load()
    random.seed(7)
    for y in range(SIZE):
        for x in range(0, SIZE, 2):
            pixels[x, y] = random.randint(0, 18)
    noise = noise.resize((CANVAS, CANVAS), Image.BILINEAR)
    texture = Image.new("RGBA", (CANVAS, CANVAS), (14, 77, 58, 0))
    texture.putalpha(noise)
    image = Image.alpha_composite(image, texture)

    draw = ImageDraw.Draw(image, "RGBA")
    block, gap, cols, rows = 138, 38, 3, 4
    total_w = cols * block + (cols - 1) * gap
    total_h = rows * block + (rows - 1) * gap
    x0 = (SIZE - total_w) / 2
    y0 = (SIZE - total_h) / 2
    for row in range(rows):
        for col in range(cols):
            x = x0 + col * (block + gap)
            y = y0 + row * (block + gap)
            highlighted = row == 1 and col == 1
            color = (255, 138, 61, 255) if highlighted else (14, 77, 58, 235)
            draw.rounded_rectangle(
                [sc(x), sc(y), sc(x + block), sc(y + block)],
                radius=sc(30), fill=color,
            )
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_neon_h() -> Image.Image:
    image = gradient(CANVAS, (14, 14, 17), (30, 31, 38)).convert("RGBA")
    image = mesh_glow(image, [
        ((180, 140, 860, 820), (217, 255, 67, 26)),
    ])
    draw = ImageDraw.Draw(image, "RGBA")
    white = (247, 247, 242, 255)
    draw.rounded_rectangle([sc(314), sc(286), sc(442), sc(738)], radius=sc(64), fill=white)
    draw.rounded_rectangle([sc(582), sc(286), sc(710), sc(738)], radius=sc(64), fill=white)
    draw.rounded_rectangle([sc(314), sc(460), sc(710), sc(564)], radius=sc(52), fill=white)
    draw.ellipse([sc(462), sc(462), sc(562), sc(562)], fill=(217, 255, 67, 255))
    draw.ellipse([sc(492), sc(492), sc(532), sc(532)], fill=(14, 14, 17, 255))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_notebook() -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), (251, 244, 230, 255))
    noise = Image.new("L", (SIZE, SIZE), 0)
    pixels = noise.load()
    random.seed(19)
    for y in range(0, SIZE, 2):
        for x in range(0, SIZE, 2):
            pixels[x, y] = random.randint(0, 16)
    noise = noise.resize((CANVAS, CANVAS), Image.BILINEAR)
    texture = Image.new("RGBA", (CANVAS, CANVAS), (120, 90, 50, 0))
    texture.putalpha(noise)
    image = Image.alpha_composite(image, texture)

    draw = ImageDraw.Draw(image, "RGBA")
    # 荧光笔横条
    rounded_line(draw, (sc(250), sc(640)), (sc(774), sc(600)), sc(120), (255, 170, 80, 90))
    # 手绘感双圈
    navy = (31, 58, 95, 255)
    draw.ellipse([sc(286), sc(266), sc(738), sc(718)], outline=(31, 58, 95, 230), width=sc(26))
    draw.ellipse([sc(280), sc(260), sc(744), sc(724)], outline=(31, 58, 95, 80), width=sc(8))
    clock_hands(draw, 512, 492, 226, navy, 34)
    # 小勾
    rounded_line(draw, (sc(690), sc(740)), (sc(730), sc(786)), sc(18), (255, 138, 61, 255))
    rounded_line(draw, (sc(730), sc(786)), (sc(806), sc(688)), sc(18), (255, 138, 61, 255))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_liquid_glass() -> Image.Image:
    image = gradient(CANVAS, (196, 181, 253), (125, 211, 252)).convert("RGBA")
    image = mesh_glow(image, [
        ((60, 80, 620, 640), (255, 255, 255, 80)),
        ((540, 380, 1060, 1000), (251, 207, 232, 120)),
        ((300, 600, 820, 1080), (167, 243, 208, 90)),
    ])
    draw = ImageDraw.Draw(image, "RGBA")
    cx = cy = 512
    radius = 236
    # 玻璃外环 + 柔和阴影
    draw.ellipse(
        [sc(cx - radius - 26), sc(cy - radius - 18), sc(cx + radius + 26), sc(cy + radius + 34)],
        fill=(80, 70, 140, 35),
    )
    draw.ellipse(
        [sc(cx - radius - 12), sc(cy - radius - 12), sc(cx + radius + 12), sc(cy + radius + 12)],
        outline=(255, 255, 255, 120), width=sc(10),
    )
    draw.ellipse(
        [sc(cx - radius), sc(cy - radius), sc(cx + radius), sc(cy + radius)],
        fill=(255, 255, 255, 205),
        outline=(255, 255, 255, 230), width=sc(4),
    )
    for tick in range(12):
        angle = math.radians(tick * 30 - 90)
        outer = radius - 30
        inner = outer - (24 if tick % 3 == 0 else 12)
        rounded_line(
            draw,
            (sc(cx + math.cos(angle) * inner), sc(cy + math.sin(angle) * inner)),
            (sc(cx + math.cos(angle) * outer), sc(cy + math.sin(angle) * outer)),
            sc(12 if tick % 3 == 0 else 7),
            (67, 56, 202, 220),
        )
    clock_hands(draw, cx, cy, radius, (67, 56, 202, 255), 36)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


DESIGNS = [
    ("G", "深色光感", design_dark_glass),
    ("H", "暖色时钟", design_warm_clock),
    ("I", "薄荷课表", design_mint_grid),
    ("J", "黑白荧光", design_neon_h),
    ("K", "手绘笔记本", design_notebook),
    ("L", "液态玻璃", design_liquid_glass),
]


def contact_sheet(images: list[tuple[str, str, Image.Image]]) -> Image.Image:
    cell_w, cell_h = 360, 430
    pad = 24
    cols, rows = 3, 2
    width = cols * cell_w + (cols + 1) * pad
    height = 96 + rows * cell_h + (rows + 1) * pad
    sheet = Image.new("RGB", (width, height), (247, 250, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((pad + 8, 28), "Helechron 图标方案 · 第二组", font=load_font(36), fill=(28, 28, 30))
    for index, (key, label, image) in enumerate(images):
        row, col = divmod(index, cols)
        x = pad + col * (cell_w + pad)
        y = 96 + pad + row * (cell_h + pad)
        icon = image.resize((320, 320), Image.LANCZOS)
        sheet.paste(icon, (x + 20, y), icon)
        draw.text((x + 24, y + 336), f"{key}  {label}", font=load_font(28), fill=(40, 40, 44))
    return sheet


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rendered: list[tuple[str, str, Image.Image]] = []
    for key, label, builder in DESIGNS:
        image = builder()
        image.save(OUT / f"option_{key.lower()}.png", optimize=True)
        rendered.append((key, label, image))
        print(f"wrote option_{key.lower()}.png")
    sheet = contact_sheet(rendered)
    sheet.save(OUT / "contact_sheet.png", optimize=True)
    sheet.convert("RGB").save(OUT / "contact_sheet.pdf", "PDF", resolution=150.0)
    print(f"wrote contact_sheet.png / .pdf ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()

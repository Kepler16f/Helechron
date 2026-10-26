#!/usr/bin/env python3
"""生成多套 AppGallery 图标方案，并输出对比图。

输出:
  store/appgallery/icon/options/option_a.png ... option_f.png
  store/appgallery/icon/options/contact_sheet.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from generate_icon import gradient, load_font, rounded_line

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "appgallery" / "icon" / "options"

S = 4
SIZE = 1024
CANVAS = SIZE * S
CENTER = CANVAS // 2
PRIMARY = (52, 120, 246, 255)
WHITE = (255, 255, 255, 255)


def sc(value: float) -> int:
    return int(value * S)


def base() -> Image.Image:
    image = gradient(CANVAS, (58, 122, 245), (108, 198, 250)).convert("RGBA")
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse([82, 82, SIZE - 82, SIZE - 82], fill=(255, 255, 255, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(70)).resize((CANVAS, CANVAS), Image.LANCZOS)
    return Image.alpha_composite(image, glow)


def _clock_face(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float,
                face: tuple[int, int, int, int], hands: tuple[int, int, int, int]) -> None:
    draw.ellipse(
        [sc(cx - radius), sc(cy - radius), sc(cx + radius), sc(cy + radius)],
        fill=face,
    )
    rounded_line(
        draw,
        (sc(cx), sc(cy)),
        (sc(cx + math.cos(math.radians(-60)) * radius * 0.52),
         sc(cy + math.sin(math.radians(-60)) * radius * 0.52)),
        sc(24),
        hands,
    )
    rounded_line(
        draw,
        (sc(cx), sc(cy)),
        (sc(cx + math.cos(math.radians(30)) * radius * 0.74),
         sc(cy + math.sin(math.radians(30)) * radius * 0.74)),
        sc(18),
        hands,
    )
    draw.ellipse([sc(cx - 18), sc(cy - 18), sc(cx + 18), sc(cy + 18)], fill=hands)


def design_clock() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    radius = 318
    draw.ellipse(
        [CENTER - sc(radius), CENTER - sc(radius), CENTER + sc(radius), CENTER + sc(radius)],
        fill=WHITE,
    )
    for tick in range(12):
        angle = math.radians(tick * 30 - 90)
        outer = radius - 34
        inner = outer - (34 if tick % 3 == 0 else 20)
        width = 14 if tick % 3 == 0 else 9
        rounded_line(
            draw,
            (CENTER + math.cos(angle) * sc(inner), CENTER + math.sin(angle) * sc(inner)),
            (CENTER + math.cos(angle) * sc(outer), CENTER + math.sin(angle) * sc(outer)),
            sc(width),
            (73, 137, 240, 235),
        )
    for angle_deg, length, width in [(305, 170, 34), (60, 246, 24)]:
        angle = math.radians(angle_deg - 90)
        rounded_line(
            draw,
            (CENTER, CENTER),
            (CENTER + math.cos(angle) * sc(length), CENTER + math.sin(angle) * sc(length)),
            sc(width),
            PRIMARY,
        )
    draw.ellipse([CENTER - sc(30), CENTER - sc(30), CENTER + sc(30), CENTER + sc(30)], fill=PRIMARY)
    draw.ellipse([CENTER - sc(10), CENTER - sc(10), CENTER + sc(10), CENTER + sc(10)], fill=WHITE)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_calendar() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle(
        [sc(230), sc(210), sc(794), sc(814)], radius=sc(88), fill=(255, 255, 255, 252)
    )
    draw.rounded_rectangle(
        [sc(230), sc(210), sc(794), sc(372)], radius=sc(88), fill=PRIMARY
    )
    draw.rectangle([sc(230), sc(320), sc(794), sc(372)], fill=PRIMARY)
    _clock_face(draw, 512, 580, 146, PRIMARY, WHITE)
    for x in (438, 512, 586):
        draw.ellipse([sc(x - 11), sc(744), sc(x + 11), sc(766)], fill=(52, 120, 246, 190))
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_h() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle([sc(316), sc(286), sc(440), sc(738)], radius=sc(62), fill=WHITE)
    draw.rounded_rectangle([sc(584), sc(286), sc(708), sc(738)], radius=sc(62), fill=WHITE)
    draw.rounded_rectangle([sc(316), sc(460), sc(708), sc(564)], radius=sc(52), fill=WHITE)
    draw.ellipse([sc(466), sc(466), sc(558), sc(558)], fill=PRIMARY)
    draw.ellipse([sc(494), sc(494), sc(530), sc(530)], fill=WHITE)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_grid() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    block, gap, cols, rows = 118, 34, 3, 4
    total_w = cols * block + (cols - 1) * gap
    total_h = rows * block + (rows - 1) * gap
    x0 = (SIZE - total_w) / 2
    y0 = (SIZE - total_h) / 2
    for row in range(rows):
        for col in range(cols):
            x = x0 + col * (block + gap)
            y = y0 + row * (block + gap)
            highlighted = row == 1 and col == 1
            fill = WHITE if highlighted else (255, 255, 255, 95)
            draw.rounded_rectangle(
                [sc(x), sc(y), sc(x + block), sc(y + block)],
                radius=sc(30),
                fill=fill,
            )
    cx = x0 + 1 * (block + gap) + block / 2
    cy = y0 + 1 * (block + gap) + block / 2
    draw.ellipse([sc(cx - 27), sc(cy - 27), sc(cx + 27), sc(cy + 27)], fill=PRIMARY)
    draw.ellipse([sc(cx - 8), sc(cy - 8), sc(cx + 8), sc(cy + 8)], fill=WHITE)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_arc() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    draw.arc([sc(252), sc(252), sc(772), sc(772)], start=180, end=360,
             fill=WHITE, width=sc(62))
    draw.ellipse([sc(470), sc(208), sc(554), sc(292)], fill=WHITE)
    for index, width in enumerate((360, 260, 170)):
        y = 604 + index * 74
        draw.rounded_rectangle(
            [sc(512 - width / 2), sc(y), sc(512 + width / 2), sc(y + 34)],
            radius=sc(17),
            fill=(255, 255, 255, 230),
        )
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def design_book() -> Image.Image:
    image = base()
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rounded_rectangle([sc(232), sc(320), sc(500), sc(760)], radius=sc(42), fill=(255, 255, 255, 250))
    draw.rounded_rectangle([sc(524), sc(320), sc(792), sc(760)], radius=sc(42), fill=(255, 255, 255, 250))
    draw.rectangle([sc(478), sc(320), sc(546), sc(760)], fill=(58, 122, 245, 255))
    draw.ellipse([sc(552), sc(204), sc(824), sc(476)], fill=PRIMARY)
    draw.ellipse([sc(596), sc(248), sc(780), sc(432)], fill=WHITE)
    rounded_line(draw, (sc(688), sc(340)), (sc(636), sc(302)), sc(20), PRIMARY)
    rounded_line(draw, (sc(688), sc(340)), (sc(736), sc(292)), sc(15), PRIMARY)
    draw.ellipse([sc(672), sc(324), sc(704), sc(356)], fill=PRIMARY)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


DESIGNS = [
    ("A", "时钟", design_clock),
    ("B", "日历 + 时钟", design_calendar),
    ("C", "H 字母", design_h),
    ("D", "课程表格子", design_grid),
    ("E", "弧线 + 日程", design_arc),
    ("F", "书本 + 时钟", design_book),
]


def contact_sheet(images: list[tuple[str, str, Image.Image]]) -> Image.Image:
    cell_w, cell_h = 360, 430
    pad = 24
    cols = 3
    rows = 2
    width = cols * cell_w + (cols + 1) * pad
    height = 96 + rows * cell_h + (rows + 1) * pad
    sheet = Image.new("RGB", (width, height), (247, 250, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((pad + 8, 28), "Helechron 图标方案", font=load_font(36), fill=(28, 28, 30))
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
    print(f"wrote contact_sheet.png ({sheet.width}x{sheet.height})")


if __name__ == "__main__":
    main()

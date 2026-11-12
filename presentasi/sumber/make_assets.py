"""Gambar pendukung deck: bingkai HP, latar gradasi, logo."""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SHOTS = Path(sys.argv[1])
BRAND = Path(sys.argv[2])
OUT = Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)

BG = (13, 18, 30)
PANEL_TOP = (20, 27, 43)
BLUE = (10, 111, 208)
CYAN = (8, 189, 240)
NAVY = (11, 46, 94)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, stops):
    """stops: [(posisi 0..1, warna)]"""
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                column.putpixel((0, y), lerp(c0, c1, (t - p0) / (p1 - p0)))
                break
    return column.resize((w, h))


def rounded_mask(size, radius, scale=3):
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=255
    )
    return big.resize((w, h), Image.LANCZOS)


def phone(name, crop=None):
    shot = Image.open(SHOTS / f"{name}.png").convert("RGB")
    if crop:
        shot = shot.crop(crop)
    scale = 0.55
    w, h = round(shot.width * scale), round(shot.height * scale)
    shot = shot.resize((w, h), Image.LANCZOS)
    bezel, radius = 16, 62
    fw, fh = w + bezel * 2, h + bezel * 2
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    body = Image.new("RGBA", (fw, fh), (6, 9, 15, 255))
    frame.paste(body, (0, 0), rounded_mask((fw, fh), radius + bezel))
    # Garis tepi tipis supaya bingkai terlihat di latar gelap.
    edge = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    scale_up = 3
    big = Image.new("RGBA", (fw * scale_up, fh * scale_up), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (2, 2, fw * scale_up - 3, fh * scale_up - 3),
        (radius + bezel) * scale_up,
        outline=(92, 108, 138, 255),
        width=6,
    )
    edge = big.resize((fw, fh), Image.LANCZOS)
    frame.alpha_composite(edge)
    screen = shot.convert("RGBA")
    screen.putalpha(rounded_mask((w, h), radius))
    frame.alpha_composite(screen, (bezel, bezel))
    frame.save(OUT / f"phone_{name}.png", optimize=True)
    print(name, frame.size)


def panel_background(name, glow, inset=44, radius=44):
    """Latar slide: bidang gelap dengan panel membulat yang bawahnya biru."""
    w, h = 1920, 1080
    canvas = Image.new("RGB", (w, h), BG)
    pw, ph = w - inset * 2, h - inset * 2
    grad = vertical_gradient(
        (pw, ph), [(0, PANEL_TOP), (0.45, PANEL_TOP), (1, glow)]
    )
    canvas.paste(grad, (inset, inset), rounded_mask((pw, ph), radius))
    big = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (inset * 2, inset * 2, (w - inset) * 2 - 1, (h - inset) * 2 - 1),
        radius * 2,
        outline=(70, 96, 140, 255),
        width=3,
    )
    canvas = canvas.convert("RGBA")
    canvas.alpha_composite(big.resize((w, h), Image.LANCZOS))
    canvas.convert("RGB").save(OUT / f"{name}.png", optimize=True)


def cover_background():
    """Sampul: bingkai gradasi biru terang, panel dalam biru tua."""
    w, h = 1920, 1080
    outer = vertical_gradient((w, h), [(0, (22, 132, 226)), (1, CYAN)])
    inset, radius = 56, 48
    pw, ph = w - inset * 2, h - inset * 2
    inner = vertical_gradient((pw, ph), [(0, (9, 34, 74)), (1, (10, 86, 170))])
    outer.paste(inner, (inset, inset), rounded_mask((pw, ph), radius))
    outer.save(OUT / "bg_cover.png", optimize=True)


def glow_card(name, size, top, bottom, radius=36):
    card = vertical_gradient(size, [(0, top), (1, bottom)]).convert("RGBA")
    card.putalpha(rounded_mask(size, radius))
    card.save(OUT / f"{name}.png", optimize=True)


def logo_card():
    """Simbol logo di kartu putih membulat, untuk slide arti logo."""
    icon = Image.open(BRAND / "icon.png").convert("RGBA")
    icon = icon.resize((720, 720), Image.LANCZOS)
    icon.putalpha(rounded_mask((720, 720), 150))
    icon.save(OUT / "logo_card.png", optimize=True)


for shot in [
    "splash", "beranda", "legend", "detail", "sensor", "sensor2",
    "lapor", "lapor_isi", "hasil1", "notif",
]:
    phone(shot)

panel_background("bg_panel", (12, 78, 156))
panel_background("bg_panel_soft", (14, 52, 104))
cover_background()
glow_card("card_blue", (900, 260), (16, 120, 214), CYAN)
glow_card("card_dark", (900, 260), (26, 36, 58), (22, 30, 48))
logo_card()

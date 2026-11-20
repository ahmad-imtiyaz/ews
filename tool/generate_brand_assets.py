"""Membuat logo transparan dan sumber ikon aplikasi dari tool/brand/.

Jalankan dari akar proyek: python tool/generate_brand_assets.py
Lalu: dart run flutter_launcher_icons

Gambar asli berlatar putih. Putih itu diubah jadi transparan dengan cara
"color to alpha", jadi tepi logo tetap halus di latar apa pun.
"""

import colorsys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tool" / "brand"
OUT = ROOT / "assets" / "brand"

# Latar gambar asli bukan putih murni (254, 253, 253) dan ada sedikit derau.
NOISE = 0.04
ICON = 1024
LIFT_TO = 0.45


def remove_white(image):
    image = image.convert("RGB")
    out = Image.new("RGBA", image.size)
    pixels = []
    for r, g, b in image.get_flattened_data():
        raw = max(255 - r, 255 - g, 255 - b) / 255
        if raw <= NOISE:
            pixels.append((0, 0, 0, 0))
            continue
        # Warna asli sebelum dicampur putih, supaya tampilan di atas putih
        # sama persis dengan gambar sumber.
        unmix = [round(255 - (255 - v) / raw) for v in (r, g, b)]
        alpha = min(1.0, (raw - NOISE) / (1 - NOISE) * 1.15)
        pixels.append((*unmix, round(alpha * 255)))
    out.putdata(pixels)
    return out


def trim(image, margin=4):
    left, top, right, bottom = image.getchannel("A").point(
        lambda a: 255 if a > 24 else 0
    ).getbbox()
    return image.crop((
        max(0, left - margin),
        max(0, top - margin),
        min(image.width, right + margin),
        min(image.height, bottom + margin),
    ))


def text_starts_at(image):
    """Kolom pertama tulisan, setelah celah kosong di kanan gambar gunung."""
    alpha = image.getchannel("A")
    filled = [
        alpha.crop((x, 0, x + 1, image.height)).getextrema()[1] > 24
        for x in range(image.width)
    ]
    x = filled.index(True)
    while filled[x]:
        x += 1
    while not filled[x]:
        x += 1
    return x


def for_dark_background(image):
    """Untuk splash hitam: tulisan jadi putih, biru tua gunung dicerahkan.

    Biru tua aslinya hampir hilang di atas hitam. Hanya kecerahannya yang
    dinaikkan, jadi gradasi gunung tetap utuh.
    """
    split = text_starts_at(image)
    out = []
    for i, (r, g, b, a) in enumerate(image.get_flattened_data()):
        if i % image.width >= split:
            out.append((255, 255, 255, a))
            continue
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if l < LIFT_TO:
            l += (LIFT_TO - l) * 0.85
        out.append((*(round(v * 255) for v in colorsys.hls_to_rgb(h, l, s)), a))
    light = Image.new("RGBA", image.size)
    light.putdata(out)
    return light


def centered(mark, width_share, background):
    canvas = Image.new("RGBA", (ICON, ICON), background)
    width = round(ICON * width_share)
    height = round(mark.height * width / mark.width)
    scaled = mark.resize((width, height), Image.LANCZOS)
    canvas.alpha_composite(
        scaled, ((ICON - width) // 2, (ICON - height) // 2)
    )
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    wordmark = trim(remove_white(Image.open(SRC / "logo_wordmark.png")))
    wordmark.save(OUT / "logo_wordmark.png", optimize=True)
    for_dark_background(wordmark).save(
        OUT / "logo_wordmark_light.png", optimize=True
    )

    mark = trim(remove_white(Image.open(SRC / "logo.png")), margin=0)
    # Ikon lama dan iOS: kotak putih penuh, logo 78% lebar.
    centered(mark, 0.78, (255, 255, 255, 255)).convert("RGB").save(
        OUT / "icon.png", optimize=True
    )
    # Ikon adaptif Android dipotong launcher menjadi lingkaran, kotak, atau
    # bentuk lain. Hanya lingkaran 66/108 di tengah yang pasti terlihat,
    # jadi logo dibuat lebih kecil.
    centered(mark, 0.58, (255, 255, 255, 0)).save(
        OUT / "icon_foreground.png", optimize=True
    )
    print(f"wordmark {wordmark.size}, mark {mark.size}")


if __name__ == "__main__":
    main()

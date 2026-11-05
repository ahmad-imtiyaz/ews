"""Membuat assets/animations/splash.json.

Jalankan dari akar proyek: python tool/generate_splash.py
Alur: tanah retak, kamera bergeser ke sirene, lalu ke warga yang melapor.
Kamera bergeser di dunia yang sama supaya ketiga adegan tersambung.
"""

import json
import math
from pathlib import Path

W = 1080
H = 2400
# Dunia digambar di koordinat persegi, lalu digeser ke tengah layar tinggi.
SCENE_Y = 520
FPS = 30
END = 96

# Pergeseran kamera antaradegan, dalam piksel dunia.
PAN = 480
CRACK_X = 540
SIREN_X = CRACK_X + PAN
PERSON_X = CRACK_X + PAN * 2

SMOOTH = ((0.42, 0.0), (0.58, 1.0))
OUT = ((0.16, 0.8), (0.24, 1.0))
IN = ((0.55, 0.05), (0.85, 0.3))
LINEAR = ((0.25, 0.25), (0.75, 0.75))


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)] + [1]


WHITE = rgb("#FFFFFF")
BLACK = rgb("#000000")
FAR = rgb("#1C1C1C")
MID = rgb("#2A2A2A")
PROP = rgb("#3D3D3D")
WINDOW = rgb("#9A9A9A")
LIGHT = rgb("#D9D9D9")
SHADE = rgb("#BDBDBD")
DUST = rgb("#6E6E6E")
INK = rgb("#111111")
RED = rgb("#E5352B")
RED_SOFT = rgb("#A91F1A")
YELLOW = rgb("#F2B60C")
GREEN = rgb("#2FA866")


def ground_y(x):
    return 780 + 24 * math.sin(x / 380) - 0.012 * (x - CRACK_X)


def as_list(value):
    return list(value) if isinstance(value, (list, tuple)) else [value]


def static(value):
    return {"a": 0, "k": value}


def anim(keys, default_ease=SMOOTH):
    """keys: (frame, nilai) atau (frame, nilai, easing keluar dari frame itu)."""
    frames = []
    for index, key in enumerate(keys):
        frame = {"t": key[0], "s": as_list(key[1])}
        if index < len(keys) - 1:
            ease = key[2] if len(key) > 2 else default_ease
            frame["o"] = {"x": ease[0][0], "y": ease[0][1]}
            frame["i"] = {"x": ease[1][0], "y": ease[1][1]}
        frames.append(frame)
    return {"a": 1, "k": frames}


def prop(value):
    if isinstance(value, dict):
        return value
    return static(value)


def transform(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    def point(v):
        if isinstance(v, dict):
            return v
        return static(list(v) + [0])

    return {
        "o": prop(o),
        "r": prop(r),
        "p": point(p),
        "a": point(a),
        "s": point(s),
    }


def pos_keys(keys):
    """Mengubah (frame, x, y[, easing]) menjadi animasi posisi."""
    converted = []
    for key in keys:
        item = (key[0], [key[1], key[2], 0])
        converted.append(item + (key[3],) if len(key) > 3 else item)
    return anim(converted)


def scale_keys(keys):
    converted = []
    for key in keys:
        item = (key[0], [key[1], key[1], 100])
        converted.append(item + (key[2],) if len(key) > 2 else item)
    return anim(converted)


def fill(color, opacity=100):
    return {"ty": "fl", "c": prop(color), "o": prop(opacity), "r": 1}


def stroke(color, width, opacity=100):
    return {
        "ty": "st",
        "c": prop(color),
        "o": prop(opacity),
        "w": static(width),
        "lc": 2,
        "lj": 2,
        "ml": 4,
    }


def trim(end, start=0):
    return {
        "ty": "tm",
        "s": prop(start),
        "e": prop(end),
        "o": static(0),
        "m": 1,
    }


def path(points, closed=False, tangents=None):
    if tangents is None:
        tangents = [((0, 0), (0, 0))] * len(points)
    return {
        "ty": "sh",
        "ks": static(
            {
                "i": [list(t[0]) for t in tangents],
                "o": [list(t[1]) for t in tangents],
                "v": [list(p) for p in points],
                "c": closed,
            }
        ),
    }


def smooth_path(points):
    """Kurva halus yang melewati semua titik."""
    tangents = []
    for index in range(len(points)):
        before = points[max(index - 1, 0)]
        after = points[min(index + 1, len(points) - 1)]
        dx = (after[0] - before[0]) / 6
        dy = (after[1] - before[1]) / 6
        tangents.append(((-dx, -dy), (dx, dy)))
    return path(points, tangents=tangents)


def closed_terrain(profile):
    """Permukaan halus yang ditutup sampai bawah kanvas."""
    last, first = profile[-1], profile[0]
    points = profile + [(last[0], H + 400), (first[0], H + 400)]
    tangents = []
    for index in range(len(profile)):
        before = profile[max(index - 1, 0)]
        after = profile[min(index + 1, len(profile) - 1)]
        dx = (after[0] - before[0]) / 6
        dy = (after[1] - before[1]) / 6
        tangents.append(((-dx, -dy), (dx, dy)))
    tangents += [((0, 0), (0, 0)), ((0, 0), (0, 0))]
    return path(points, closed=True, tangents=tangents)


def ellipse(center, size):
    return {
        "ty": "el",
        "p": static(list(center)),
        "s": static(list(size)),
        "d": 1,
    }


def rect(center, size, radius=0):
    return {
        "ty": "rc",
        "p": static(list(center)),
        "s": static(list(size)),
        "r": static(radius),
        "d": 1,
    }


def group(*items):
    return {
        "ty": "gr",
        "it": list(items)
        + [
            {
                "ty": "tr",
                "p": static([0, 0]),
                "a": static([0, 0]),
                "s": static([100, 100]),
                "r": static(0),
                "o": static(100),
                "sk": static(0),
                "sa": static(0),
            }
        ],
    }


class Composition:
    def __init__(self):
        self.layers = []

    def _add(self, name, layer_type, ks, parent, ip, op, extra):
        layer = {
            "ddd": 0,
            "ind": len(self.layers) + 1,
            "ty": layer_type,
            "nm": name,
            "sr": 1,
            "ks": ks,
            "ao": 0,
            "ip": ip,
            "op": op,
            "st": 0,
            "bm": 0,
        }
        if parent is not None:
            layer["parent"] = parent
        layer.update(extra)
        self.layers.append(layer)
        return layer["ind"]

    def null(self, name, parent=None, **kwargs):
        return self._add(name, 3, transform(**kwargs), parent, 0, END, {})

    def shape(self, name, shapes, parent=None, ip=0, op=END, **kwargs):
        return self._add(
            name, 4, transform(**kwargs), parent, ip, op, {"shapes": shapes}
        )

    def solid(self, name, color):
        return self._add(
            name,
            1,
            transform(),
            None,
            0,
            END,
            {"sc": color, "sw": W, "sh": H},
        )

    def to_json(self):
        # Lottie menggambar lapisan pertama di paling atas.
        return {
            "v": "5.7.4",
            "fr": FPS,
            "ip": 0,
            "op": END,
            "w": W,
            "h": H,
            "nm": "EWS Lumeneng splash",
            "ddd": 0,
            "assets": [],
            "layers": list(reversed(self.layers)),
        }


def camera_keys(factor):
    pan = PAN * factor
    return pos_keys(
        [
            (0, 0, 0),
            (27, 0, 0),
            (37, -pan, 0),
            (56, -pan, 0),
            (66, -2 * pan, 0),
            (END, -2 * pan, 0),
        ]
    )


def build():
    comp = Composition()
    comp.solid("Latar", "#000000")

    scene = comp.null("Adegan", p=(0, SCENE_Y))
    shake = comp.null(
        "Guncangan",
        parent=scene,
        p=anim(
            [
                (0, [0, 0, 0]),
                (13, [0, 0, 0], LINEAR),
                (15, [-10, 6, 0], LINEAR),
                (17, [9, -6, 0], LINEAR),
                (19, [-8, 5, 0], LINEAR),
                (21, [7, -4, 0], LINEAR),
                (23, [-5, 3, 0], LINEAR),
                (25, [4, -2, 0], LINEAR),
                (27, [-2, 1, 0], LINEAR),
                (29, [0, 0, 0]),
                (END, [0, 0, 0]),
            ]
        ),
    )
    cam_far = comp.null("Kamera jauh", parent=shake, p=camera_keys(0.35))
    cam_mid = comp.null("Kamera tengah", parent=shake, p=camera_keys(0.7))
    cam = comp.null("Kamera", parent=shake, p=camera_keys(1))

    add_landscape(comp, cam_far, cam_mid)
    add_siren(comp, cam)
    add_ground(comp, cam)
    add_crack(comp, cam)
    add_person(comp, cam)
    add_flash(comp)
    return comp


def add_landscape(comp, cam_far, cam_mid):
    far_profile = [
        (x, 500 - 150 * max(0, math.sin(x / 210)) - 40 * math.sin(x / 90))
        for x in range(-300, 1900, 70)
    ]
    comp.shape(
        "Gunung jauh",
        [group(closed_terrain(far_profile), fill(FAR))],
        parent=cam_far,
        p=pos_keys([(0, 0, 150, OUT), (22, 0, 0), (END, 0, 0)]),
        o=anim([(0, 0), (12, 100), (END, 100)]),
    )

    def mid_y(x):
        return 620 + 42 * math.sin(x / 300 + 1)

    mid_profile = [(x, mid_y(x)) for x in range(-300, 2500, 80)]
    props = [group(closed_terrain(mid_profile), fill(MID))]

    for x, size in [
        (60, 62), (250, 84), (455, 58), (690, 90), (880, 66), (1130, 86),
        (1350, 60), (1530, 88), (1760, 70), (1990, 82), (2230, 64),
    ]:
        y = mid_y(x) + 6
        props.append(
            group(
                rect((x, y - size * 0.35), (size * 0.16, size * 0.8), 3),
                ellipse((x, y - size), (size, size * 1.15)),
                fill(PROP),
            )
        )

    for x in [350, 1000, 1660, 2120]:
        y = mid_y(x) + 8
        props.append(group(rect((x, y - 34), (104, 68), 4), fill(PROP)))
        props.append(
            group(
                path(
                    [(x - 66, y - 64), (x, y - 112), (x + 66, y - 64)],
                    closed=True,
                ),
                fill(PROP),
            )
        )
        props.append(group(rect((x - 22, y - 34), (22, 24), 2), fill(WINDOW)))
        props.append(group(rect((x + 24, y - 24), (22, 44), 2), fill(WINDOW)))

    comp.shape(
        "Bukit dan rumah",
        list(reversed(props)),
        parent=cam_mid,
        p=pos_keys([(2, 0, 130, OUT), (24, 0, 0), (END, 0, 0)]),
        o=anim([(2, 0), (14, 100), (END, 100)]),
    )


def add_siren(comp, cam):
    ground = ground_y(SIREN_X)
    root = comp.null(
        "Sirene",
        parent=cam,
        p=pos_keys(
            [
                (0, SIREN_X, ground + 520),
                (30, SIREN_X, ground + 520, OUT),
                (40, SIREN_X, ground - 18, SMOOTH),
                (45, SIREN_X, ground + 6, SMOOTH),
                (49, SIREN_X, ground),
                (END, SIREN_X, ground),
            ]
        ),
    )

    dome_y = -392
    swing = [(36, -75), (62, 75, LINEAR)]
    for name, offset in [("Sorot kiri", 0), ("Sorot kanan", 180)]:
        comp.shape(
            name,
            [
                group(
                    path(
                        [(0, 0), (-340, -2000), (340, -2000)],
                        closed=True,
                    ),
                    fill(YELLOW, opacity=24),
                )
            ],
            parent=root,
            p=(0, dome_y),
            r=anim(
                [
                    (36, swing[0][1] + offset, LINEAR),
                    (62, swing[1][1] + offset),
                ]
            ),
            o=anim([(36, 0), (40, 100), (58, 100), (66, 0)]),
            ip=34,
            op=68,
        )

    ring_starts = [(40, YELLOW), (46, RED), (52, YELLOW), (58, RED)]
    for index, (start, color) in enumerate(ring_starts):
        comp.shape(
            f"Gelombang {index + 1}",
            [group(ellipse((0, 0), (170, 170)), stroke(color, 10))],
            parent=root,
            p=(0, dome_y),
            s=scale_keys([(start, 30, OUT), (start + 20, 280)]),
            o=anim([(start, 85), (start + 20, 0)]),
            ip=start,
            op=start + 21,
        )

    comp.shape(
        "Tiang",
        [
            group(rect((0, -175), (26, 350), 6), fill(LIGHT)),
            group(rect((0, -350), (118, 26), 10), fill(WHITE)),
        ],
        parent=root,
    )

    flash = anim(
        [
            (36, RED, LINEAR),
            (42, YELLOW, LINEAR),
            (48, RED, LINEAR),
            (54, YELLOW, LINEAR),
            (60, RED),
        ]
    )
    radius = 78
    k = radius * 0.5523
    dome = path(
        [(-radius, -362), (0, -362 - radius), (radius, -362)],
        closed=True,
        tangents=[
            ((0, 0), (0, -k)),
            ((-k, 0), (k, 0)),
            ((0, -k), (0, 0)),
        ],
    )
    comp.shape(
        "Kubah",
        [
            group(
                smooth_path([(-40, -392), (-22, -414), (0, -422)]),
                stroke(WHITE, 8, opacity=80),
            ),
            group(dome, fill(flash)),
        ],
        parent=root,
    )


def add_ground(comp, cam):
    profile = [(x, ground_y(x)) for x in range(-300, 2701, 120)]
    outline_end = 100 * (1080 + 300) / 3000
    comp.shape(
        "Tanah",
        [
            group(
                smooth_path(profile),
                trim(
                    anim(
                        [
                            (0, 0, OUT),
                            (14, outline_end, LINEAR),
                            (15, 100),
                            (END, 100),
                        ]
                    )
                ),
                stroke(WHITE, 10),
            ),
            group(closed_terrain(profile), fill(BLACK)),
        ],
        parent=cam,
    )


def add_crack(comp, cam):
    top = ground_y(CRACK_X)

    def crack_line(name, points, start, finish, width):
        comp.shape(
            name,
            [
                group(
                    path([(CRACK_X + x, top + y) for x, y in points]),
                    trim(anim([(start, 0, OUT), (finish, 100), (END, 100)])),
                    stroke(WHITE, width),
                )
            ],
            parent=cam,
        )

    crack_line(
        "Retakan utama",
        [(0, 0), (-26, 62), (22, 112), (-20, 170), (28, 225), (-4, 282)],
        12,
        27,
        10,
    )
    crack_line("Retakan kiri", [(-26, 62), (-74, 96), (-98, 148)], 17, 27, 7)
    crack_line("Retakan kanan", [(22, 112), (72, 138), (104, 190)], 20, 29, 7)
    crack_line("Retakan kecil", [(-20, 170), (-62, 204)], 23, 30, 5)

    for index, (dx, size, delay) in enumerate(
        [(-70, 74, 0), (64, 88, 1), (-132, 56, 3), (128, 62, 4)]
    ):
        start = 14 + delay
        comp.shape(
            f"Debu {index + 1}",
            [group(ellipse((0, 0), (size, size)), fill(DUST))],
            parent=cam,
            p=pos_keys(
                [
                    (start, CRACK_X + dx * 0.25, top - 8, OUT),
                    (start + 20, CRACK_X + dx, top - 42),
                ]
            ),
            s=scale_keys([(start, 15, OUT), (start + 20, 120)]),
            o=anim([(start, 75), (start + 20, 0)]),
            ip=start,
            op=start + 21,
        )

    rocks = [
        (-110, 150, 16, 14), (-60, 210, 22, 15), (-22, 250, 12, 14),
        (40, 230, 18, 16), (92, 180, 24, 15), (150, 120, 14, 17),
    ]
    for index, (dx, height, size, start) in enumerate(rocks):
        peak = start + 8
        finish = start + 18
        comp.shape(
            f"Kerikil {index + 1}",
            [group(rect((0, 0), (size, size * 0.8), 3), fill(WHITE))],
            parent=cam,
            p=pos_keys(
                [
                    (start, CRACK_X, top, OUT),
                    (peak, CRACK_X + dx * 0.6, top - height, IN),
                    (finish, CRACK_X + dx, top - 6),
                ]
            ),
            r=anim([(start, 0, LINEAR), (finish, 200 if dx > 0 else -200)]),
            o=anim([(start, 100), (finish - 2, 100), (finish, 0)]),
            ip=start,
            op=finish + 1,
        )


def add_person(comp, cam):
    ground = ground_y(PERSON_X)
    root = comp.null(
        "Warga",
        parent=cam,
        p=pos_keys(
            [
                (0, PERSON_X + 520, ground),
                (54, PERSON_X + 520, ground, SMOOTH),
                (71, PERSON_X, ground),
                (END, PERSON_X, ground),
            ]
        ),
    )

    hip_y = -150
    swings = [(54, 24), (58, -24), (62, 24), (66, -20), (70, 0), (END, 0)]
    comp.shape(
        "Kaki belakang",
        [group(path([(0, 0), (0, 150)]), stroke(SHADE, 32))],
        parent=root,
        p=(14, hip_y),
        r=anim([(t, -a) for t, a in swings]),
    )
    comp.shape(
        "Kaki depan",
        [group(path([(0, 0), (0, 150)]), stroke(WHITE, 32))],
        parent=root,
        p=(-14, hip_y),
        r=anim(swings),
    )

    body = comp.null(
        "Badan",
        parent=root,
        p=anim(
            [
                (54, [0, 0, 0]),
                (56, [0, -9, 0]),
                (58, [0, 0, 0]),
                (60, [0, -9, 0]),
                (62, [0, 0, 0]),
                (64, [0, -9, 0]),
                (66, [0, 0, 0]),
                (68, [0, -7, 0]),
                (70, [0, 0, 0]),
                (END, [0, 0, 0]),
            ]
        ),
    )

    comp.shape(
        "Lengan belakang",
        [group(path([(0, 0), (0, 118)]), stroke(SHADE, 26))],
        parent=body,
        p=(34, -282),
        r=anim(
            [
                (54, -22),
                (58, 22),
                (62, -22),
                (66, 18),
                (70, 6),
                (END, 6),
            ]
        ),
    )
    comp.shape(
        "Tubuh dan kepala",
        [
            group(ellipse((0, -354), (92, 92)), fill(WHITE)),
            group(rect((0, -226), (98, 176), 42), fill(WHITE)),
        ],
        parent=body,
    )

    arm_keys = [
        (54, 22),
        (58, -22),
        (62, 22),
        (66, -18),
        (68, 4),
        (75, 142),
        (79, 122),
        (82, 128),
        (END, 128),
    ]
    arm = comp.shape(
        "Lengan HP",
        [group(path([(0, 0), (0, 118)]), stroke(LIGHT, 26))],
        parent=body,
        p=(-34, -282),
        r=anim(arm_keys),
    )
    comp.shape(
        "HP",
        [
            group(
                rect((0, 0), (46, 82), 5),
                fill(
                    anim(
                        [
                            (68, PROP),
                            (74, WHITE),
                            (END, WHITE),
                        ]
                    )
                ),
            ),
            group(rect((0, 0), (64, 108), 12), fill(INK)),
            group(rect((0, 0), (70, 114), 14), stroke(WHITE, 5)),
        ],
        parent=arm,
        p=(0, 128),
        r=anim([(t, -a - 8) for t, a in arm_keys]),
    )

    add_report_bubble(comp, cam, ground)


def add_report_bubble(comp, cam, ground):
    tail_x = PERSON_X - 98
    tail_y = ground - 452

    for index, start in enumerate([73, 76, 79]):
        comp.shape(
            f"Sinyal {index + 1}",
            [group(ellipse((0, 0), (16, 16)), fill(WHITE))],
            parent=cam,
            p=pos_keys(
                [
                    (start, tail_x + 8, tail_y + 16, SMOOTH),
                    (start + 7, tail_x - 8, tail_y - 44),
                ]
            ),
            o=anim([(start, 0), (start + 2, 100), (start + 7, 0)]),
            ip=start,
            op=start + 8,
        )

    bubble = comp.null(
        "Pesan",
        parent=cam,
        p=(tail_x, tail_y - 26),
        s=scale_keys(
            [
                (0, 0),
                (73, 0, OUT),
                (79, 110, SMOOTH),
                (82, 96, SMOOTH),
                (85, 100),
                (END, 100),
            ]
        ),
    )
    comp.shape(
        "Gelembung",
        [
            group(
                path(
                    [(-22, -18), (22, -18), (0, 26)],
                    closed=True,
                ),
                fill(WHITE),
            ),
            group(rect((0, -112), (280, 190), 34), fill(WHITE)),
        ],
        parent=bubble,
    )

    for index, (y, half, start) in enumerate(
        [(-158, 86, 76), (-112, 86, 78), (-66, 52, 80)]
    ):
        comp.shape(
            f"Baris laporan {index + 1}",
            [
                group(
                    path([(-86, y), (-86 + half * 2, y)]),
                    trim(anim([(start, 0, OUT), (start + 5, 100), (END, 100)])),
                    stroke(INK, 14),
                )
            ],
            parent=bubble,
            o=anim([(start, 100), (84, 100), (87, 0), (END, 0)]),
        )

    comp.shape(
        "Lingkaran centang",
        [group(ellipse((0, 0), (112, 112)), fill(GREEN))],
        parent=bubble,
        p=(0, -112),
        s=scale_keys(
            [
                (0, 0),
                (85, 0, OUT),
                (90, 116, SMOOTH),
                (93, 100),
                (END, 100),
            ]
        ),
    )
    comp.shape(
        "Centang",
        [
            group(
                path([(-26, -112), (-8, -92), (30, -134)]),
                trim(anim([(87, 0, OUT), (93, 100), (END, 100)])),
                stroke(WHITE, 13),
            )
        ],
        parent=bubble,
        ip=87,
    )


def add_flash(comp):
    # Dua kilatan lembut, di bawah batas tiga kilatan per detik.
    comp.shape(
        "Kilatan merah",
        [group(rect((W / 2, H / 2), (W, H)), fill(RED_SOFT))],
        o=anim(
            [
                (36, 0),
                (42, 16),
                (48, 0),
                (54, 16),
                (60, 0),
            ]
        ),
        ip=36,
        op=61,
    )


def main():
    out = Path("assets/animations/splash.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(build().to_json(), separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"{out}: {out.stat().st_size} byte, {END / FPS:.1f} detik")


if __name__ == "__main__":
    main()

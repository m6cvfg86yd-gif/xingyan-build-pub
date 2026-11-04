from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "server" / "public" / "emoji" / "star-orbit"

SIZE = 320
SUPERSAMPLE = 2
S = SIZE * SUPERSAMPLE
FRAME_COUNT = 18
FRAME_MS = 80

GREEN_LIGHT = (190, 255, 132, 255)
GREEN = (101, 222, 62, 255)
GREEN_DARK = (34, 139, 52, 255)
GREEN_EDGE = (225, 255, 214, 214)
INK = (7, 35, 22, 255)
WHITE = (247, 255, 242, 255)
ORBIT = (213, 255, 207, 196)


STICKERS = [
    ("收到", "shou-dao", "check"),
    ("在呢", "zai-ne", "presence"),
    ("等等", "deng-deng", "wait"),
    ("谢谢", "xie-xie", "thanks"),
    ("笑死", "xiao-si", "laugh"),
    ("震惊", "zhen-jing", "shock"),
    ("无语", "wu-yu", "speechless"),
    ("抱抱", "bao-bao", "hug"),
    ("晚安", "wan-an", "night"),
    ("听歌", "ting-ge", "music"),
    ("开车", "kai-che", "drive"),
    ("想你", "xiang-ni", "miss"),
]


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return float(value >= edge1)
    x = clamp((value - edge0) / (edge1 - edge0))
    return x * x * (3 - 2 * x)


def mix(a: tuple[int, ...], b: tuple[int, ...], amount: float) -> tuple[int, ...]:
    return tuple(round(a[i] + (b[i] - a[i]) * amount) for i in range(4))


def periodic(value: float, turns: float = 1.0, phase: float = 0.0) -> float:
    return math.sin((value * turns + phase) * math.tau)


def orb_gradient() -> Image.Image:
    gradient = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pixels = gradient.load()
    for y in range(S):
        p = y / max(1, S - 1)
        if p < 0.48:
            color = mix(GREEN_LIGHT, GREEN, smoothstep(0.0, 0.48, p))
        else:
            color = mix(GREEN, GREEN_DARK, smoothstep(0.48, 1.0, p))
        for x in range(S):
            vignette = clamp(1 - 0.09 * abs(x / S - 0.5) * 2)
            pixels[x, y] = (*color[:3], round(color[3] * vignette))
    return gradient


ORB_GRADIENT = orb_gradient()


def draw_arc(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    start: float,
    end: float,
    fill: tuple[int, ...],
    width: int,
    tilt: float = 0.0,
) -> None:
    steps = max(8, int(abs(end - start) * 36))
    points: list[tuple[float, float]] = []
    ct, st = math.cos(tilt), math.sin(tilt)
    for i in range(steps + 1):
        angle = start + (end - start) * i / steps
        x = rx * math.cos(angle)
        y = ry * math.sin(angle)
        points.append((cx + x * ct - y * st, cy + x * st + y * ct))
    if len(points) > 1:
        draw.line(points, fill=fill, width=width, joint="curve")


def draw_star(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float, color: tuple[int, ...]) -> None:
    cut = radius * 0.18
    points = [
        (cx, cy - radius),
        (cx + cut, cy - cut),
        (cx + radius, cy),
        (cx + cut, cy + cut),
        (cx, cy + radius),
        (cx - cut, cy + cut),
        (cx - radius, cy),
        (cx - cut, cy - cut),
    ]
    draw.polygon(points, fill=color)


def draw_heart(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, color: tuple[int, ...]) -> None:
    radius = 13 * scale
    draw.ellipse((cx - 2 * radius, cy - radius, cx, cy + radius), fill=color)
    draw.ellipse((cx, cy - radius, cx + 2 * radius, cy + radius), fill=color)
    draw.polygon(
        [(cx - 2 * radius + 1, cy + 4 * scale),
         (cx + 2 * radius - 1, cy + 4 * scale),
         (cx, cy + 2.2 * radius)],
        fill=color,
    )


def draw_check(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, color: tuple[int, ...]) -> None:
    width = max(2, round(13 * scale))
    draw.line(
        [(cx - 31 * scale, cy + 1 * scale),
         (cx - 9 * scale, cy + 23 * scale),
         (cx + 36 * scale, cy - 29 * scale)],
        fill=color,
        width=width,
        joint="curve",
    )


def draw_music_note(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, color: tuple[int, ...]) -> None:
    draw.ellipse((cx - 13 * scale, cy + 15 * scale, cx + 3 * scale, cy + 29 * scale), fill=color)
    draw.ellipse((cx + 12 * scale, cy + 9 * scale, cx + 28 * scale, cy + 23 * scale), fill=color)
    draw.line((cx + 2 * scale, cy + 21 * scale, cx + 2 * scale, cy - 30 * scale), fill=color, width=max(2, round(5 * scale)))
    draw.line((cx + 27 * scale, cy + 16 * scale, cx + 27 * scale, cy - 35 * scale), fill=color, width=max(2, round(5 * scale)))
    draw.line((cx + 2 * scale, cy - 30 * scale, cx + 27 * scale, cy - 35 * scale), fill=color, width=max(2, round(7 * scale)))


def draw_moon(frame: Image.Image, cx: float, cy: float, scale: float, color: tuple[int, ...]) -> None:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    r = 29 * scale
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    offset_x = 12 * scale
    offset_y = -8 * scale
    cut = 27 * scale
    draw.ellipse((cx - cut + offset_x, cy - cut + offset_y, cx + cut + offset_x, cy + cut + offset_y), fill=(0, 0, 0, 0))
    frame.alpha_composite(layer)


def draw_orb(
    frame: Image.Image,
    t: float,
    mood: str,
    *,
    cx: float,
    cy: float,
    scale: float,
    blink: float = 0.0,
    blush: float = 0.0,
    look: tuple[float, float] = (0.0, 0.0),
) -> None:
    side = 356 * scale
    left = round(cx - side / 2)
    top = round(cy - side / 2)

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = side * 0.53
    gd.ellipse((cx - gr, cy - gr, cx + gr, cy + gr), fill=(91, 239, 76, 78))
    glow = glow.filter(ImageFilter.GaussianBlur(24 * SUPERSAMPLE))
    frame.alpha_composite(glow)

    body_mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(body_mask)
    radius = round(side * 0.27)
    md.rounded_rectangle((left, top, left + side, top + side), radius=radius, fill=255)

    body = ORB_GRADIENT.resize((round(side), round(side)), Image.Resampling.LANCZOS)
    mask_crop = body_mask.crop((left, top, left + round(side), top + round(side)))
    frame.paste(body, (left, top), mask_crop)

    d = ImageDraw.Draw(frame, "RGBA")
    d.rounded_rectangle(
        (left, top, left + side, top + side),
        radius=radius,
        outline=GREEN_EDGE,
        width=max(2, round(3.4 * SUPERSAMPLE * scale)),
    )

    highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse(
        (cx - side * 0.28, cy - side * 0.34, cx + side * 0.05, cy - side * 0.08),
        fill=(255, 255, 255, 82),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(11 * SUPERSAMPLE))
    frame.alpha_composite(highlight)

    eye_y = cy - side * 0.035
    eye_dx = side * 0.145
    eye_w = side * 0.082
    eye_h = side * 0.175
    lx = look[0] * side * 0.018
    ly = look[1] * side * 0.018
    window = max(0.04, 1.0 - blink)

    for idx in (-1, 1):
        ex = cx + idx * eye_dx + lx
        ey = eye_y + ly
        if mood in {"speechless", "night"} or (mood == "presence" and idx == 1 and t > 0.50 and t < 0.66):
            d.line(
                [(ex - eye_w * 0.58, ey), (ex + eye_w * 0.58, ey)],
                fill=INK,
                width=max(3, round(7 * SUPERSAMPLE * scale)),
            )
        elif mood == "laugh":
            draw_arc(
                d,
                ex,
                ey + eye_h * 0.16,
                eye_w * 0.58,
                eye_h * 0.36,
                math.pi * 1.08,
                math.pi * 1.92,
                INK,
                max(3, round(7 * SUPERSAMPLE * scale)),
            )
        else:
            wide = 1.18 if mood == "shock" else 1.0
            height = eye_h * window * (1.12 if mood == "shock" else 1.0)
            width = eye_w * wide
            d.rounded_rectangle(
                (ex - width / 2, ey - height / 2, ex + width / 2, ey + height / 2),
                radius=min(width, height) / 2,
                fill=INK,
            )
            if window > 0.42:
                glint = max(1.5, 2.8 * SUPERSAMPLE * scale)
                d.ellipse(
                    (ex - width * 0.12 - glint, ey - height * 0.20 - glint,
                     ex - width * 0.12 + glint, ey - height * 0.20 + glint),
                    fill=(231, 255, 221, 225),
                )

    if blush > 0.01:
        for idx in (-1, 1):
            bx = cx + idx * side * 0.258
            by = cy + side * 0.092
            d.ellipse(
                (bx - side * 0.060, by - side * 0.022, bx + side * 0.060, by + side * 0.022),
                fill=(255, 220, 180, round(92 * blush)),
            )

    mouth_y = cy + side * 0.145
    if mood == "shock":
        d.ellipse(
            (cx - side * 0.035, mouth_y - side * 0.032, cx + side * 0.035, mouth_y + side * 0.032),
            fill=INK,
        )
    elif mood == "speechless":
        d.line(
            [(cx - side * 0.062, mouth_y), (cx + side * 0.062, mouth_y)],
            fill=INK,
            width=max(2, round(4.5 * SUPERSAMPLE * scale)),
        )
    elif mood == "laugh":
        d.arc(
            (cx - side * 0.10, mouth_y - side * 0.05, cx + side * 0.10, mouth_y + side * 0.08),
            start=8,
            end=172,
            fill=INK,
            width=max(3, round(5 * SUPERSAMPLE * scale)),
        )
    elif mood not in {"night"}:
        d.arc(
            (cx - side * 0.065, mouth_y - side * 0.045, cx + side * 0.065, mouth_y + side * 0.045),
            start=18,
            end=162,
            fill=INK,
            width=max(2, round(4.2 * SUPERSAMPLE * scale)),
        )


def draw_orbit(frame: Image.Image, t: float, cx: float, cy: float, *, strong: float = 1.0) -> None:
    d = ImageDraw.Draw(frame, "RGBA")
    rotation = t * math.tau
    for start, length, alpha in [
        (-2.78, 1.30, 0.92),
        (-0.98, 0.78, 0.72),
        (0.38, 1.05, 0.82),
    ]:
        draw_arc(
            d,
            cx,
            cy,
            154 * SUPERSAMPLE,
            67 * SUPERSAMPLE,
            start + rotation * 0.06,
            (start + length) + rotation * 0.06,
            (*ORBIT[:3], round(ORBIT[3] * alpha * strong)),
            max(2, round(3.3 * SUPERSAMPLE)),
            tilt=-0.24,
        )
    for i, phase in enumerate((0.0, 2.1, 4.3)):
        angle = t * math.tau + phase
        x = cx + math.cos(angle) * 154 * SUPERSAMPLE
        y = cy + math.sin(angle) * 67 * SUPERSAMPLE
        dx = x - cx
        dy = y - cy
        ct, st = math.cos(-0.24), math.sin(-0.24)
        px = cx + dx * ct - dy * st
        py = cy + dx * st + dy * ct
        radius = (3.0 + i * 1.0) * SUPERSAMPLE
        d.ellipse((px - radius, py - radius, px + radius, py + radius), fill=WHITE)


def draw_effect(frame: Image.Image, kind: str, t: float, cx: float, cy: float) -> None:
    d = ImageDraw.Draw(frame, "RGBA")
    enter = smoothstep(0.0, 0.18, t)
    exit_at = 1 - smoothstep(0.78, 1.0, t)
    visible = enter * exit_at

    if kind == "check":
        pulse = 1 + 0.08 * periodic(t, 1)
        draw_check(d, cx + 105 * SUPERSAMPLE, cy - 95 * SUPERSAMPLE,
                   2.4 * SUPERSAMPLE * pulse, (238, 255, 229, round(255 * visible)))
        draw_star(d, cx - 130 * SUPERSAMPLE, cy + 83 * SUPERSAMPLE,
                  8 * SUPERSAMPLE * visible, (241, 255, 232, round(210 * visible)))
    elif kind == "presence":
        radius = (0.55 + 0.45 * abs(periodic(t, 1))) * 20 * SUPERSAMPLE
        d.ellipse((cx + 111 * SUPERSAMPLE - radius, cy + 82 * SUPERSAMPLE - radius,
                   cx + 111 * SUPERSAMPLE + radius, cy + 82 * SUPERSAMPLE + radius),
                  fill=(223, 255, 210, round(78 * visible)))
        d.ellipse((cx + 102 * SUPERSAMPLE, cy + 73 * SUPERSAMPLE,
                   cx + 120 * SUPERSAMPLE, cy + 91 * SUPERSAMPLE),
                  fill=(245, 255, 235, round(230 * visible)))
    elif kind == "wait":
        for i in range(3):
            phase = (t + i / 3) % 1.0
            alpha = round(210 * (0.35 + 0.65 * math.sin(phase * math.pi)))
            x = cx + (66 + i * 34) * SUPERSAMPLE
            y = cy + 114 * SUPERSAMPLE - math.sin(phase * math.pi) * 8 * SUPERSAMPLE
            r = 6 * SUPERSAMPLE
            d.ellipse((x - r, y - r, x + r, y + r), fill=(246, 255, 238, alpha))
    elif kind == "thanks":
        for i, (angle, dist, size) in enumerate([(-2.35, 146, 10), (-0.60, 157, 8), (0.55, 139, 7), (2.45, 156, 6)]):
            twinkle = 0.55 + 0.45 * periodic(t, 2, i * 0.17)
            x = cx + math.cos(angle + t * 0.7) * dist * SUPERSAMPLE
            y = cy + math.sin(angle + t * 0.7) * dist * SUPERSAMPLE
            draw_star(d, x, y, size * SUPERSAMPLE * twinkle, (245, 255, 234, round(235 * visible)))
        draw_heart(d, cx, cy - 132 * SUPERSAMPLE, 1.7 * SUPERSAMPLE, (245, 255, 235, round(210 * visible)))
    elif kind == "laugh":
        for side in (-1, 1):
            x = cx + side * 117 * SUPERSAMPLE
            y = cy - 102 * SUPERSAMPLE + side * 7 * SUPERSAMPLE
            draw_star(d, x, y, (9 + 3 * abs(periodic(t, 3))) * SUPERSAMPLE,
                      (246, 255, 235, round(225 * visible)))
    elif kind == "shock":
        x = cx + 114 * SUPERSAMPLE
        y = cy - 105 * SUPERSAMPLE
        d.rounded_rectangle(
            (x - 6 * SUPERSAMPLE, y - 30 * SUPERSAMPLE, x + 6 * SUPERSAMPLE, y + 7 * SUPERSAMPLE),
            radius=6 * SUPERSAMPLE,
            fill=(247, 255, 236, round(255 * visible)),
        )
        d.ellipse(
            (x - 6 * SUPERSAMPLE, y + 16 * SUPERSAMPLE, x + 6 * SUPERSAMPLE, y + 28 * SUPERSAMPLE),
            fill=(247, 255, 236, round(255 * visible)),
        )
    elif kind == "speechless":
        for i in range(3):
            alpha = round(235 * visible * (0.55 + 0.45 * math.sin((t + i * 0.08) * math.tau)))
            x = cx + (72 + i * 30) * SUPERSAMPLE
            y = cy + 112 * SUPERSAMPLE
            d.ellipse((x - 5 * SUPERSAMPLE, y - 5 * SUPERSAMPLE, x + 5 * SUPERSAMPLE, y + 5 * SUPERSAMPLE),
                      fill=(246, 255, 237, alpha))
    elif kind == "hug":
        offset = (1 - smoothstep(0.0, 0.30, t)) * 38 * SUPERSAMPLE
        for side in (-1, 1):
            x = cx + side * (67 * SUPERSAMPLE + offset)
            y = cy + 105 * SUPERSAMPLE
            r = 17 * SUPERSAMPLE
            d.ellipse((x - r, y - r, x + r, y + r), fill=(164, 247, 112, round(235 * visible)))
            d.rounded_rectangle(
                (x - 7 * SUPERSAMPLE, y - 5 * SUPERSAMPLE, x - 3 * SUPERSAMPLE, y + 5 * SUPERSAMPLE),
                radius=2 * SUPERSAMPLE,
                fill=INK,
            )
            d.rounded_rectangle(
                (x + 3 * SUPERSAMPLE, y - 5 * SUPERSAMPLE, x + 7 * SUPERSAMPLE, y + 5 * SUPERSAMPLE),
                radius=2 * SUPERSAMPLE,
                fill=INK,
            )
        pulse = 1 + 0.08 * math.sin(t * math.tau)
        draw_heart(d, cx, cy - 139 * SUPERSAMPLE, 1.35 * SUPERSAMPLE * pulse,
                   (241, 255, 229, round(205 * visible)))
    elif kind == "night":
        orbit_x = cx + math.cos(t * math.tau) * 117 * SUPERSAMPLE
        orbit_y = cy - 122 * SUPERSAMPLE + math.sin(t * math.tau) * 12 * SUPERSAMPLE
        draw_moon(frame, orbit_x, orbit_y, 0.95 * SUPERSAMPLE, (244, 255, 235, round(240 * visible)))
        for i in range(4):
            twinkle = 0.45 + 0.55 * abs(periodic(t, 2, i * 0.21))
            x = cx + (-126 + i * 84) * SUPERSAMPLE
            y = cy + (-132 + (i % 2) * 74) * SUPERSAMPLE
            draw_star(d, x, y, (5 + i % 2 * 2) * SUPERSAMPLE * twinkle,
                      (226, 255, 214, round(190 * visible)))
    elif kind == "music":
        bounce = math.sin(t * math.tau * 2) * 4 * SUPERSAMPLE
        draw_music_note(d, cx + 116 * SUPERSAMPLE, cy - 94 * SUPERSAMPLE + bounce,
                        1.42 * SUPERSAMPLE, (246, 255, 236, round(235 * visible)))
        draw_arc(d, cx, cy - 28 * SUPERSAMPLE, 118 * SUPERSAMPLE, 117 * SUPERSAMPLE,
                 math.pi * 1.07, math.pi * 1.92, (240, 255, 230, round(205 * visible)),
                 max(3, 5 * SUPERSAMPLE))
        for side in (-1, 1):
            x = cx + side * 116 * SUPERSAMPLE
            y = cy - 28 * SUPERSAMPLE
            d.rounded_rectangle(
                (x - 9 * SUPERSAMPLE, y - 16 * SUPERSAMPLE, x + 9 * SUPERSAMPLE, y + 42 * SUPERSAMPLE),
                radius=8 * SUPERSAMPLE,
                fill=(240, 255, 230, round(215 * visible)),
            )
    elif kind == "drive":
        wheel_y = cy + 114 * SUPERSAMPLE
        r = 23 * SUPERSAMPLE
        width = max(3, 4 * SUPERSAMPLE)
        d.ellipse((cx - r, wheel_y - r, cx + r, wheel_y + r), outline=(244, 255, 235, round(235 * visible)), width=width)
        d.ellipse((cx - 7 * SUPERSAMPLE, wheel_y - 7 * SUPERSAMPLE,
                   cx + 7 * SUPERSAMPLE, wheel_y + 7 * SUPERSAMPLE),
                  fill=(244, 255, 235, round(235 * visible)))
        for angle in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6):
            d.line(
                [(cx, wheel_y),
                 (cx + math.cos(angle) * r, wheel_y + math.sin(angle) * r)],
                fill=(244, 255, 235, round(235 * visible)),
                width=width,
            )
        for i in range(3):
            x = cx + (-58 + i * 58) * SUPERSAMPLE
            y = cy + 67 * SUPERSAMPLE
            d.line([(x - 6 * SUPERSAMPLE, y), (x + 6 * SUPERSAMPLE, y)],
                   fill=(217, 255, 202, round(90 * visible)), width=2 * SUPERSAMPLE)
    elif kind == "miss":
        pulse = 1 + 0.14 * math.sin(t * math.tau)
        draw_heart(d, cx, cy - 136 * SUPERSAMPLE, 2.0 * SUPERSAMPLE * pulse,
                   (241, 255, 229, round(245 * visible)))
        for i, side in enumerate((-1, 1)):
            twinkle = 0.55 + 0.45 * periodic(t, 2, i * 0.25)
            draw_star(d, cx + side * 119 * SUPERSAMPLE, cy - 60 * SUPERSAMPLE,
                      (6 + i) * SUPERSAMPLE * twinkle,
                      (240, 255, 231, round(205 * visible)))


def drawer_for(kind: str, t: float) -> tuple[float, float, float, float, float, tuple[float, float], str]:
    idle_y = periodic(t, 1) * 3.0 * SUPERSAMPLE
    x = 0.0
    y = idle_y
    scale = 1.0
    blink = 0.0
    blush = 0.0
    look = (0.0, 0.0)
    mood = "normal"

    if kind == "check":
        y += abs(periodic(t, 1)) * 5 * SUPERSAMPLE
        look = (0.25, -0.2)
    elif kind == "presence":
        look = (periodic(t, 1) * 0.8, 0.0)
        blink = smoothstep(0.44, 0.48, t) * (1 - smoothstep(0.52, 0.58, t))
        blush = 0.45
    elif kind == "wait":
        look = (periodic(t, 2) * 0.7, periodic(t, 1, 0.25) * 0.25)
    elif kind == "thanks":
        y += 3 * SUPERSAMPLE * abs(periodic(t, 1))
        blush = 0.85
        look = (0.0, 0.25)
        mood = "normal"
    elif kind == "laugh":
        x += periodic(t, 3) * 7 * SUPERSAMPLE
        y += abs(periodic(t, 2)) * 8 * SUPERSAMPLE
        mood = "laugh"
        blush = 1.0
    elif kind == "shock":
        impact = math.sin(clamp(t * 3.2) * math.pi) if t < 0.75 else 0.0
        scale = 1.0 + 0.09 * impact
        x += periodic(t, 4) * 3 * SUPERSAMPLE * impact
        mood = "shock"
        look = (0.0, -0.25)
    elif kind == "speechless":
        x += periodic(t, 1) * 8 * SUPERSAMPLE
        mood = "speechless"
        look = (-0.65, -0.15)
    elif kind == "hug":
        scale = 1.0 + periodic(t, 2) * 0.025
        blush = 1.0
        y += 2 * SUPERSAMPLE * periodic(t, 1)
        look = (0.0, 0.3)
    elif kind == "night":
        mood = "night"
        y += 4 * SUPERSAMPLE * periodic(t, 1)
        blink = 0.88
        blush = 0.25
    elif kind == "music":
        x += periodic(t, 2) * 5 * SUPERSAMPLE
        y += periodic(t, 2, 0.1) * 5 * SUPERSAMPLE
        blink = smoothstep(0.46, 0.49, t) * (1 - smoothstep(0.52, 0.56, t))
        look = (0.5, 0.0)
    elif kind == "drive":
        x += periodic(t, 1) * 4 * SUPERSAMPLE
        look = (0.8, 0.0)
        mood = "normal"
    elif kind == "miss":
        scale = 1.0 + 0.035 * periodic(t, 1)
        blush = 0.95
        look = (periodic(t, 1, 0.25) * 0.4, -0.15)

    return x, y, scale, blink, blush, look, mood


def render_frame(index: int, kind: str) -> Image.Image:
    t = index / FRAME_COUNT
    frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = S / 2
    cy = S / 2 - 2 * SUPERSAMPLE
    x, y, scale, blink, blush, look, mood = drawer_for(kind, t)

    draw_orbit(frame, t, cx, cy)
    draw_orb(
        frame,
        t,
        mood,
        cx=cx + x,
        cy=cy + y,
        scale=scale,
        blink=blink,
        blush=blush,
        look=look,
    )
    draw_effect(frame, kind, t, cx, cy)
    return frame.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def make_gif(kind: str, path: Path) -> Image.Image:
    frames: list[Image.Image] = []
    for i in range(FRAME_COUNT):
        rgba = render_frame(i, kind)
        alpha = rgba.getchannel("A").point(lambda a: 0 if a < 14 else 255)
        rgba.putalpha(alpha)
        pal = rgba.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        pal.paste(255, mask=Image.eval(rgba.getchannel("A"), lambda a: 255 if a == 0 else 0))
        frames.append(pal)

    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_MS,
        loop=0,
        disposal=2,
        transparency=255,
        optimize=True,
        comment=b"Original Xingyan star-orbit emoji. Generated in-repo.",
    )
    return frames[0].convert("RGBA")


def preview_sheet(icons: list[tuple[str, Image.Image]], path: Path) -> None:
    columns = 4
    cell_w, cell_h = 300, 340
    sheet = Image.new("RGBA", (columns * cell_w, math.ceil(len(icons) / columns) * cell_h), (15, 21, 17, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        from PIL import ImageFont

        font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 24)
        small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 15)
    except Exception:
        font = None
        small = None

    for i, (name, icon) in enumerate(icons):
        col = i % columns
        row = i // columns
        x = col * cell_w
        y = row * cell_h
        draw.rounded_rectangle((x + 12, y + 12, x + cell_w - 12, y + cell_h - 12),
                               radius=28, fill=(26, 36, 29, 255), outline=(93, 154, 78, 255), width=1)
        thumb = icon.copy().resize((176, 176), Image.Resampling.LANCZOS)
        sheet.alpha_composite(thumb, (x + 62, y + 29))
        label = f"星言 · {name}"
        if font:
            box = draw.textbbox((0, 0), label, font=font)
            draw.text((x + (cell_w - (box[2] - box[0])) / 2, y + 220), label, font=font, fill=(240, 255, 235, 255))
            technical = f"{SIZE}px · {FRAME_COUNT}f · {FRAME_MS}ms"
            box = draw.textbbox((0, 0), technical, font=small)
            draw.text((x + (cell_w - (box[2] - box[0])) / 2, y + 266), technical, font=small, fill=(150, 190, 146, 255))
        else:
            draw.text((x + 110, y + 230), f"Xingyan / {name}", fill=(240, 255, 235, 255))

    sheet.convert("RGB").save(path, quality=94)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icons: list[tuple[str, Image.Image]] = []
    files: list[str] = []
    for name, slug, kind in STICKERS:
        path = OUT_DIR / f"{slug}.gif"
        icons.append((name, make_gif(kind, path)))
        files.append(path.name)

    (OUT_DIR / "icon.gif").write_bytes((OUT_DIR / "shou-dao.gif").read_bytes())

    catalog = {
        "categories": [
            {"id": "star", "name": "星言"}
        ],
        "packs": [
            {
                "id": "star-orbit-daily",
                "name": "星言日常",
                "category": "star",
                "dir": "/emoji/star-orbit",
                "icon": "/emoji/star-orbit/icon.gif",
                "files": files,
            }
        ],
    }
    (OUT_DIR / "pack.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    manifest = {
        "name": "星言日常",
        "version": 1,
        "author": "Xingyan / original in-house artwork",
        "license": "All rights reserved by the Xingyan project. Generated from code in this repository.",
        "source": "tools/generate_star_emojis.py",
        "canvas": {"width": SIZE, "height": SIZE, "frames": FRAME_COUNT, "frame_ms": FRAME_MS, "loop": True},
        "items": [{"name": name, "file": f"{slug}.gif", "animation": kind} for name, slug, kind in STICKERS],
    }
    (OUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT_DIR / "README.txt").write_text(
        "星言原创动态表情\n"
        "================\n\n"
        "本目录中的 GIF 由本仓库 tools/generate_star_emojis.py 程序化生成，"
        "不包含微信、QQ 或其他第三方 IP、角色或表情素材。\n\n"
        "用途：星言 App 表情商店和聊天消息。\n"
        "规格：320 x 320，18 帧，80ms/帧，无限循环，透明背景。\n"
        "重新生成：使用 Pillow 运行 tools/generate_star_emojis.py。\n",
        encoding="utf-8",
    )
    preview_sheet(icons, OUT_DIR / "preview.png")
    print(f"Generated {len(STICKERS)} animated stickers in {OUT_DIR}")


if __name__ == "__main__":
    main()

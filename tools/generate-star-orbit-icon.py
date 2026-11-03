from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SIZE = 2048
CENTER = SIZE / 2


def diagonal_gradient(
    size: int,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size]
    t = np.clip((x * 0.36 + y * 0.64) / (size - 1), 0, 1)
    t = t * t * (3 - 2 * t)
    arr = np.zeros((size, size, 3), dtype=np.uint8)
    for channel in range(3):
        arr[..., channel] = (
            top[channel] + (bottom[channel] - top[channel]) * t
        ).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def star_mask(size: int, outer: float, inner: float) -> Image.Image:
    """Four-point star with softly curved arms, centered on a transparent canvas."""
    center = size / 2
    points = [
        (center, center - outer),
        (center + inner, center - inner * 0.95),
        (center + outer * 0.84, center),
        (center + inner, center + inner * 0.95),
        (center, center + outer),
        (center - inner, center + inner * 0.95),
        (center - outer * 0.84, center),
        (center - inner, center - inner * 0.95),
    ]

    def catmull_rom(p0, p1, p2, p3, t: float):
        t2, t3 = t * t, t * t * t
        return (
            0.5
            * (
                2 * p1[0]
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            ),
            0.5
            * (
                2 * p1[1]
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            ),
        )

    curve = []
    for index in range(len(points)):
        p0 = points[(index - 1) % len(points)]
        p1 = points[index]
        p2 = points[(index + 1) % len(points)]
        p3 = points[(index + 2) % len(points)]
        for step in range(32):
            curve.append(catmull_rom(p0, p1, p2, p3, step / 32))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(curve, fill=255)
    return mask


def add_vignette(image: Image.Image) -> Image.Image:
    radial = Image.radial_gradient("L").resize((SIZE, SIZE), Image.Resampling.BICUBIC)
    edge_alpha = ImageOps.invert(radial).point(lambda value: int(value * 0.14))
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 69, 43, 255))
    shade.putalpha(edge_alpha)
    return Image.alpha_composite(image, shade)


def build_icon(
    top: tuple[int, int, int] = (100, 255, 178),
    bottom: tuple[int, int, int] = (24, 205, 126),
) -> Image.Image:
    background = diagonal_gradient(
        SIZE,
        top,
        bottom,
    ).convert("RGBA")
    background = add_vignette(background)

    # Diffuse top-left light gives the green material depth without a glossy bevel.
    ambient = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ambient_draw = ImageDraw.Draw(ambient)
    ambient_draw.ellipse((190, 110, 1640, 1560), fill=(104, 255, 184, 72))
    ambient = ambient.filter(ImageFilter.GaussianBlur(250))
    background = Image.alpha_composite(background, ambient)

    # The orbit is deliberately restrained so the mark stays legible at 60 pt.
    orbit = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    orbit_draw = ImageDraw.Draw(orbit)
    orbit_draw.ellipse(
        (326, 704, 1722, 1344),
        outline=(232, 255, 245, 112),
        width=23,
    )
    orbit = orbit.rotate(-25, resample=Image.Resampling.BICUBIC, center=(CENTER, CENTER))
    orbit = orbit.filter(ImageFilter.GaussianBlur(0.55))
    background = Image.alpha_composite(background, orbit)

    accent_orbit = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    accent_draw = ImageDraw.Draw(accent_orbit)
    accent_draw.arc(
        (420, 760, 1628, 1302),
        198,
        337,
        fill=(255, 226, 163, 146),
        width=18,
    )
    accent_orbit = accent_orbit.rotate(
        -25,
        resample=Image.Resampling.BICUBIC,
        center=(CENTER, CENTER),
    )
    background = Image.alpha_composite(background, accent_orbit)

    star_size = 1536
    mask = star_mask(star_size, 650, 192)
    star = Image.new("RGBA", (star_size, star_size), (0, 0, 0, 0))
    star_fill = diagonal_gradient(
        star_size,
        (255, 255, 253),
        (220, 255, 240),
    ).convert("RGBA")
    star_fill.putalpha(mask)
    star.alpha_composite(star_fill)
    star = star.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 45, 29, 92), (0, 0), star.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(46))
    shadow = ImageChops.offset(shadow, 6, 28)
    background = Image.alpha_composite(background, shadow)
    background = Image.alpha_composite(background, star)

    # One soft clipped highlight keeps the star from looking like flat vector art.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.ellipse((700, 250, 1280, 830), fill=(255, 255, 255, 36))
    highlight.putalpha(
        ImageChops.multiply(highlight.getchannel("A"), star.getchannel("A"))
    )
    background = Image.alpha_composite(background, highlight)

    detail = ImageDraw.Draw(background)
    # Two restrained eyes sit inside the widest part of the star.
    detail.rounded_rectangle(
        (954, 974, 998, 1042),
        radius=22,
        fill=(3, 111, 69, 255),
    )
    detail.rounded_rectangle(
        (1050, 974, 1094, 1042),
        radius=22,
        fill=(3, 111, 69, 255),
    )
    detail.ellipse((1514, 500, 1590, 576), fill=(255, 255, 252, 244))
    detail.ellipse((1488, 474, 1616, 602), outline=(236, 255, 245, 42), width=8)
    detail.ellipse((486, 1416, 542, 1472), fill=(188, 255, 221, 224))

    rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(
        (4, 4, SIZE - 5, SIZE - 5),
        radius=446,
        outline=(245, 255, 250, 32),
        width=5,
    )
    return Image.alpha_composite(background, rim).convert("RGB")


def main() -> None:
    icon = build_icon()
    icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(
        ROOT / "app-icon-starorbit-1024.png",
        optimize=True,
    )
    icon.resize((120, 120), Image.Resampling.LANCZOS).save(
        ROOT / "AppIcon60x60@2x.png",
        optimize=True,
    )
    icon.resize((180, 180), Image.Resampling.LANCZOS).save(
        ROOT / "AppIcon60x60@3x.png",
        optimize=True,
    )


if __name__ == "__main__":
    main()

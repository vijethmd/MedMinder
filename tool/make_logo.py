"""Render the MedMinder logo to PNGs.

Same geometry as res/drawable/ic_launcher_foreground.xml (108-unit canvas,
visible area = central 72 units, like an adaptive icon).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

BG_START = (0x2A, 0x5F, 0xA6)
BG_END = (0x17, 0x3E, 0x73)
FACE = (0x3B, 0x73, 0xBD, 255)
TICK = (255, 255, 255, 204)
WHITE = (255, 255, 255, 255)
AMBER = (0xF4, 0xB4, 0x3A, 255)

SS = 4  # supersampling for smooth edges


def render(size: int, rounded: bool) -> Image.Image:
    big = size * SS
    k = big / 72.0  # pixels per unit

    def px(v):  # icon unit (0..108) -> pixel, cropping the 18-unit margin
        return (v - 18) * k

    # Diagonal gradient background (top-left light -> bottom-right dark)
    grad = Image.new("L", (256, 256))
    grad.putdata([(x + y) // 2 for y in range(256) for x in range(256)])
    grad = grad.resize((big, big), Image.BILINEAR)
    bg = Image.composite(Image.new("RGBA", (big, big), BG_END + (255,)),
                         Image.new("RGBA", (big, big), BG_START + (255,)), grad)

    art = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    # Clock face (centre 54,54 radius 26)
    d.ellipse([px(28), px(28), px(80), px(80)], fill=FACE)

    # Hour marks at 12, 3, 6, 9
    for x0, y0, x1, y1 in [
        (52.75, 31.5, 55.25, 37.0),   # 12
        (71.0, 52.75, 76.5, 55.25),   # 3
        (52.75, 71.0, 55.25, 76.5),   # 6
        (31.5, 52.75, 37.0, 55.25),   # 9
    ]:
        d.rectangle([px(x0), px(y0), px(x1), px(y1)], fill=TICK)

    # Capsule drawn level, then tilted 45 degrees (top-right end amber).
    # Each half is a full capsule clipped at the middle.
    r = 8 * k
    top, bottom = px(46), px(62)
    left, mid, right = px(36), px(54), px(72)

    def half(color, keep_left):
        layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle([left, top, right, bottom], radius=r, fill=color)
        clip = Image.new("L", (big, big), 0)
        x0, x1 = (0, mid) if keep_left else (mid, big)
        ImageDraw.Draw(clip).rectangle([x0, 0, x1, big], fill=255)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(layer, (0, 0), clip)
        return out

    pill = Image.alpha_composite(half(WHITE, True), half(AMBER, False))
    pill = pill.rotate(45, resample=Image.BICUBIC, center=(px(54), px(54)))
    art = Image.alpha_composite(art, pill)

    icon = Image.alpha_composite(bg, art)

    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1],
                                               radius=big * 0.23, fill=255)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(icon, (0, 0), mask)
        icon = out

    return icon.resize((size, size), Image.LANCZOS)


def main(project: Path, preview_dir: Path):
    res = project / "android/app/src/main/res"
    for folder, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                         "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(size, rounded=True).save(res / f"mipmap-{folder}/ic_launcher.png")

    (project / "assets/images").mkdir(parents=True, exist_ok=True)
    render(512, rounded=True).save(project / "assets/images/logo.png")
    render(1024, rounded=True).save(preview_dir / "medminder_logo_1024.png")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))

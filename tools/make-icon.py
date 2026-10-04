#!/usr/bin/env python3
"""Draw Ref's app icon — drawn here, not borrowed from anyone.

Two cards, a yellow and a red, on pitch-dark green: the referee's toolkit in
one glance.

    python3 tools/make-icon.py

Writes the same 1024x1024 PNG into both asset catalogs (the iOS one and the
watch one). Xcode's actool reads the platform out of each Contents.json and
compiles the catalog in the macOS build, so the PNG can be shared and there is
no committed Assets.car to maintain. RGB, no alpha — iOS rounds the corners
itself. The shape of this file follows brisaloca-ios tools/make-icons.py.
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
BG = (11, 61, 46)        # pitch-dark green
LIGHT = (18, 86, 63)     # the soft top light
YELLOW = (255, 214, 10)
RED = (255, 59, 48)
EDGE = (6, 40, 30)       # a darker rim, so the cards read against the green

HERE = Path(__file__).resolve().parent.parent
CATALOGS = (
    "Apps/Ref/Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "Apps/Ref/Resources/Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
)


def card(color, angle):
    """One rounded card, drawn at 4x on its own layer, rotated, and scaled."""
    s = SIZE * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = int(s * 0.30), int(s * 0.42)
    x, y = (s - w) // 2, (s - h) // 2
    d.rounded_rectangle(
        [x, y, x + w, y + h],
        radius=int(w * 0.12),
        fill=color + (255,),
        outline=EDGE + (255,),
        width=int(s * 0.008),
    )
    img = img.rotate(angle, resample=Image.BICUBIC, center=(s // 2, s // 2))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    icon = Image.new("RGB", (SIZE, SIZE), BG)
    # A soft vertical light, so the green does not read flat.
    mask = Image.new("L", (1, SIZE))
    for y in range(SIZE):
        mask.putpixel((0, y), int(30 * (1 - y / SIZE)))
    icon = Image.composite(Image.new("RGB", (SIZE, SIZE), LIGHT), icon,
                           mask.resize((SIZE, SIZE)))

    for color, angle, dx in ((YELLOW, 10, -70), (RED, -8, 70)):
        layer = card(color, angle)
        icon.paste(layer, (dx, 0), layer)

    for rel in CATALOGS:
        out = HERE / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        icon.save(out)
        print(f"{rel} {icon.size[0]}x{icon.size[1]}")


if __name__ == "__main__":
    main()

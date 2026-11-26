#!/usr/bin/env python3
"""Adds an app's icon to Console as a rounded square.

    python3 tool/add_app_icon.py <service id> <path to the app's square icon>

Writes assets/apps/<service id>.png (256x256, rounded corners, transparent
outside). Console uses it on the Apps page, the app's page, in-app banners and
on the right side of that app's notifications. `service id` is the `id` of the
app's ConsoleService in lib/services.dart.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 256
RADIUS = 0.225  # of the side, like a phone home-screen icon
SUPERSAMPLE = 4  # smooth corners


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    service_id, source = sys.argv[1], Path(sys.argv[2])
    out = Path(__file__).resolve().parent.parent / "assets" / "apps" / f"{service_id}.png"

    img = Image.open(source).convert("RGBA")
    side = min(img.size)  # center-crop to a square
    left, top = (img.width - side) // 2, (img.height - side) // 2
    img = img.crop((left, top, left + side, top + side)).resize((SIZE, SIZE), Image.LANCZOS)

    big = SIZE * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * RADIUS), fill=255)
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)

    alpha = Image.composite(img.getchannel("A"), Image.new("L", img.size, 0), mask)
    img.putalpha(alpha)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, optimize=True)
    print(f"Wrote {out.relative_to(out.parent.parent.parent)}")


if __name__ == "__main__":
    main()

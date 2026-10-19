#!/usr/bin/env python3
"""Draw the One Roof app icon (roof over three status dots) → Resources/AppIcon.icns."""
import os, subprocess, tempfile
from PIL import Image, ImageDraw

def draw(size):
    s = size / 1024
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = int(100 * s)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, size - m, size - m], radius=int(185 * s), fill=255)
    tile = Image.new("RGBA", (size, size), (24, 27, 34, 255))
    # light "sidebar" strip on the left: the light-panel-next-to-dark-panel idea
    ImageDraw.Draw(tile).rectangle([0, 0, int(390 * s), size], fill=(244, 243, 238, 255))
    im.paste(tile, (0, 0), mask)
    d = ImageDraw.Draw(im)
    # roof
    w = int(46 * s)
    d.line([(int(215 * s), int(520 * s)), (int(512 * s), int(250 * s)), (int(809 * s), int(520 * s))],
           fill=(110, 168, 255, 255), width=w, joint="curve")
    # three status dots: needs you · done · running
    for x, c in [(355, (255, 107, 97)), (512, (91, 212, 138)), (669, (110, 168, 255))]:
        r = int(52 * s)
        cx, cy = int(x * s), int(660 * s)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c + (255,))
    return im

out = os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIcon.icns")
with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    for base in [16, 32, 128, 256, 512]:
        draw(base).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
        draw(base * 2).save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    draw(512).save(os.path.join(os.path.dirname(out), "AppIcon-preview.png"))
print("wrote", os.path.abspath(out))

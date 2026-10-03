#!/usr/bin/env python3
"""Generate a 1024x1024 placeholder app icon using only Python stdlib.
Gradient rounded square (deep blue-purple -> indigo) + white cloud / download arrow.
Writes AppIcon.png and Contents.json next to this script's output dir.
"""
import os
import struct
import zlib

SIZE = 1024
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "YxiOS", "Assets.xcassets", "AppIcon.appiconset",
)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


TOP = (43, 16, 85)      # deep blue-purple
BOTTOM = (67, 56, 202)  # indigo


def inside_rounded(x, y, x0, y0, x1, y1, r):
    if x0 + r <= x <= x1 - r and y0 <= y <= y1:
        return True
    if x0 <= x < x0 + r and y0 + r <= y <= y1 - r:
        return True
    if x1 - r < x <= x1 and y0 + r <= y <= y1 - r:
        return True
    # corners
    for cx, cy in ((x0 + r, y0 + r), (x1 - r, y0 + r),
                   (x0 + r, y1 - r), (x1 - r, y1 - r)):
        dx = x - cx
        dy = y - cy
        if dx * dx + dy * dy <= r * r:
            return True
    return False


def in_cloud(x, y, cx, cy):
    """White cloud silhouette centered at (cx,cy)."""
    # base rounded rect
    if abs(x - cx) <= 190 and abs(y - (cy + 60)) <= 95:
        return True
    bumps = [
        (cx - 130, cy + 10, 95),
        (cx, cy - 45, 120),
        (cx + 130, cy + 15, 85),
    ]
    for bx, by, br in bumps:
        dx = x - bx
        dy = y - by
        if dx * dx + dy * dy <= br * br:
            return True
    return False


def in_arrow(x, y, cx, cy):
    """Downward arrow inside the cloud, centered."""
    # stem
    if abs(x - cx) <= 26 and cy - 70 <= y <= cy + 20:
        return True
    # triangular head
    tip_y = cy + 95
    base_y = cy + 15
    if base_y <= y <= tip_y:
        half_w = 95 * (y - base_y) / (tip_y - base_y)
        if abs(x - cx) <= half_w:
            return True
    return False


def build():
    cx = cy = SIZE // 2
    # rounded square bounds
    bx0, by0, bx1, by1 = 0, 0, SIZE - 1, SIZE - 1
    radius = 224

    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type 0
        for x in range(SIZE):
            if inside_rounded(x, y, bx0, by0, bx1, by1, radius):
                t = (x + y) / (2 * SIZE)  # diagonal gradient
                r, g, b = lerp(TOP, BOTTOM, t)
                if in_cloud(x, y, cx, cy):
                    if in_arrow(x, y, cx, cy):
                        # arrow = indigo on white cloud
                        r, g, b = BOTTOM
                    else:
                        r, g, b = 255, 255, 255
                a = 255
            else:
                r = g = b = a = 0
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))

    png_path = os.path.join(OUT_DIR, "AppIcon.png")
    with open(png_path, "wb") as f:
        f.write(png)

    contents = (
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "AppIcon.png",\n'
        '      "idiom" : "universal",\n'
        '      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        f.write(contents)

    print("Wrote", png_path, len(png), "bytes")


if __name__ == "__main__":
    build()

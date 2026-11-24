#!/usr/bin/env python3
"""Draw Satchel's original app icon: a leather bag on a deep green square."""
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..", "Satchel", "Assets.xcassets", "AppIcon.appiconset")


def write_png(path, width, height, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride:(y + 1) * stride])
    blob = b"\x89PNG\r\n\x1a\n"
    blob += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    blob += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    blob += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(blob)


def blend(buf, x, y, size, r, g, b, a):
    if x < 0 or y < 0 or x >= size or y >= size or a <= 0:
        return
    i = (y * size + x) * 4
    src = a / 255.0
    dst = buf[i + 3] / 255.0
    out = src + dst * (1 - src)
    if out <= 0:
        return
    buf[i] = int((r * src + buf[i] * dst * (1 - src)) / out)
    buf[i + 1] = int((g * src + buf[i + 1] * dst * (1 - src)) / out)
    buf[i + 2] = int((b * src + buf[i + 2] * dst * (1 - src)) / out)
    buf[i + 3] = int(out * 255)


def fill_rect(buf, size, x, y, w, h, radius, color):
    r, g, b, a = color
    x0 = max(0, int(x) - 2)
    y0 = max(0, int(y) - 2)
    x1 = min(size, int(x + w) + 3)
    y1 = min(size, int(y + h) + 3)
    cx = x + w / 2
    cy = y + h / 2
    hx = w / 2 - radius
    hy = h / 2 - radius
    for py in range(y0, y1):
        for px in range(x0, x1):
            dx = abs(px + 0.5 - cx) - hx
            dy = abs(py + 0.5 - cy) - hy
            outside = (max(dx, 0) ** 2 + max(dy, 0) ** 2) ** 0.5
            inside = min(max(dx, dy), 0)
            sd = outside + inside - radius
            if sd < 1.2:
                cov = 1.0 if sd < -0.8 else max(0.0, 0.5 - sd * 0.5)
                blend(buf, px, py, size, r, g, b, a * cov)


def fill_circle(buf, size, cx, cy, radius, color):
    r, g, b, a = color
    x0 = max(0, int(cx - radius) - 2)
    y0 = max(0, int(cy - radius) - 2)
    x1 = min(size, int(cx + radius) + 3)
    y1 = min(size, int(cy + radius) + 3)
    for py in range(y0, y1):
        for px in range(x0, x1):
            d = ((px + 0.5 - cx) ** 2 + (py + 0.5 - cy) ** 2) ** 0.5 - radius
            if d < 1.2:
                cov = 1.0 if d < -0.8 else max(0.0, 0.5 - d * 0.5)
                blend(buf, px, py, size, r, g, b, a * cov)


def fill_poly(buf, size, pts, color):
    r, g, b, a = color
    ys = [p[1] for p in pts]
    xs = [p[0] for p in pts]
    y0 = max(0, int(min(ys)))
    y1 = min(size - 1, int(max(ys)))
    n = len(pts)
    for py in range(y0, y1 + 1):
        y = py + 0.5
        nodes = []
        for i in range(n):
            x_a, y_a = pts[i]
            x_b, y_b = pts[(i + 1) % n]
            if (y_a <= y < y_b) or (y_b <= y < y_a):
                if y_b != y_a:
                    nodes.append(x_a + (y - y_a) * (x_b - x_a) / (y_b - y_a))
        nodes.sort()
        for i in range(0, len(nodes) - 1, 2):
            left = int(nodes[i])
            right = int(nodes[i + 1])
            for px in range(max(0, left), min(size, right + 1)):
                blend(buf, px, py, size, r, g, b, a)


def render(size):
    buf = bytearray(size * size * 4)
    s = size / 1024.0

    def p(v):
        return v * s

    for y in range(size):
        for x in range(size):
            i = (y * size + x) * 4
            buf[i] = 22
            buf[i + 1] = 78
            buf[i + 2] = 70
            buf[i + 3] = 255
    fill_rect(buf, size, p(48), p(48), p(928), p(928), p(210), (28, 96, 86, 255))
    fill_poly(buf, size, [
        (p(340), p(460)), (p(400), p(250)), (p(470), p(250)), (p(420), p(480)),
    ], (214, 176, 122, 255))
    fill_poly(buf, size, [
        (p(684), p(460)), (p(624), p(250)), (p(554), p(250)), (p(604), p(480)),
    ], (214, 176, 122, 255))
    fill_rect(buf, size, p(400), p(200), p(224), p(78), p(36), (236, 204, 150, 255))
    fill_rect(buf, size, p(200), p(400), p(624), p(430), p(78), (236, 205, 158, 255))
    fill_rect(buf, size, p(200), p(300), p(624), p(230), p(78), (186, 140, 96, 255))
    fill_rect(buf, size, p(250), p(508), p(524), p(16), p(8), (150, 108, 70, 255))
    fill_rect(buf, size, p(452), p(455), p(120), p(156), p(24), (176, 116, 46, 255))
    fill_rect(buf, size, p(486), p(490), p(52), p(86), p(14), (22, 78, 70, 255))
    for i in range(6):
        fill_circle(buf, size, p(290 + i * 88), p(760), p(9), (150, 108, 70, 255))
    return buf


def downscale(src, source, size):
    buf = bytearray(size * size * 4)
    factor = source / size
    for y in range(size):
        for x in range(size):
            x0 = int(x * factor)
            x1 = max(x0 + 1, int((x + 1) * factor))
            y0 = int(y * factor)
            y1 = max(y0 + 1, int((y + 1) * factor))
            acc = [0, 0, 0, 0]
            n = 0
            for py in range(y0, min(source, y1)):
                row = py * source
                for px in range(x0, min(source, x1)):
                    i = (row + px) * 4
                    acc[0] += src[i]
                    acc[1] += src[i + 1]
                    acc[2] += src[i + 2]
                    acc[3] += src[i + 3]
                    n += 1
            o = (y * size + x) * 4
            if n:
                buf[o] = acc[0] // n
                buf[o + 1] = acc[1] // n
                buf[o + 2] = acc[2] // n
                buf[o + 3] = acc[3] // n
    return buf


def main():
    os.makedirs(ROOT, exist_ok=True)
    big = render(1024)
    write_png(os.path.join(ROOT, "icon_1024.png"), 1024, 1024, big)
    for size in (16, 32, 64, 128, 256, 512):
        small = downscale(big, 1024, size)
        write_png(os.path.join(ROOT, f"icon_{size}.png"), size, size, small)
    contents = """{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
    with open(os.path.join(ROOT, "Contents.json"), "w", encoding="utf-8") as handle:
        handle.write(contents)
    parent = os.path.dirname(ROOT)
    with open(os.path.join(parent, "Contents.json"), "w", encoding="utf-8") as handle:
        handle.write('{ "info" : { "author" : "xcode", "version" : 1 } }\n')


if __name__ == "__main__":
    main()

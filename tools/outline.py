#!/usr/bin/env python3
"""Trace Kliner's own outline out of the drawing of it.

The line that travels while you wait has to lie on the shape, not near it, so
it is not a circle and it is not a list of radii either: a radius per angle
cannot hold the notch at the bottom. This walks the boundary of the drawing and
writes it out as points, in fractions of the shape's own width, which is what
makes the ring one to one with the face at any size.

    outline.py assets/app/outline.png --print
    outline.py assets/app/outline.png app/Sources/main.swift
"""
import math
import re
import struct
import sys
import zlib
from collections import deque

POINTS = 180


def pixels(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    i, idat, w, h, depth, colour = 8, b'', None, None, None, None
    while i < len(data):
        size = struct.unpack('>I', data[i:i + 4])[0]
        kind = data[i + 4:i + 8]
        body = data[i + 8:i + 8 + size]
        if kind == b'IHDR':
            w, h, depth, colour = struct.unpack('>IIBB', body[:10])
        elif kind == b'IDAT':
            idat += body
        i += 8 + size + 4
    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    step = channels * depth // 8
    stride = w * step
    out, prev, p = bytearray(), bytearray(stride), 0
    for _ in range(h):
        filt = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        for x in range(stride):
            a = line[x - step] if x >= step else 0
            b = prev[x]
            c = prev[x - step] if x >= step else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif filt == 4:
                guess = a + b - c
                da, db, dc = abs(guess - a), abs(guess - b), abs(guess - c)
                near = a if (da <= db and da <= dc) else (b if db <= dc else c)
                line[x] = (line[x] + near) & 255
        out += line
        prev = line
    return w, h, channels, bytes(out)


def trace(path):
    w0, h0, channels, px = pixels(path)

    def drawn(x, y):
        i = (y * w0 + x) * channels
        r, g, b = px[i], px[i + 1], px[i + 2]
        a = px[i + 3] if channels == 4 else 255
        if a < 100:
            return False
        # The line is drawn in a colour, on white, and the eyes inside it are
        # so faint they are all but white. Anything with more green or blue in
        # it than red is the line.
        return (g - r > 25 or b - r > 25) and r < 220

    pad = 6
    W, H = w0 + 2 * pad, h0 + 2 * pad
    wall = [[False] * W for _ in range(H)]
    for y in range(h0):
        for x in range(w0):
            if drawn(x, y):
                wall[y + pad][x + pad] = True

    # Whatever a flood from the corner cannot reach is the shape, line and all.
    out = [[False] * W for _ in range(H)]
    q = deque([(0, 0)])
    out[0][0] = True
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and not out[ny][nx] and not wall[ny][nx]:
                out[ny][nx] = True
                q.append((nx, ny))
    inside = [[not out[y][x] for x in range(W)] for y in range(H)]

    start = None
    for y in range(H):
        for x in range(W):
            if inside[y][x]:
                start = (x, y)
                break
        if start:
            break
    if not start:
        raise SystemExit('nothing drawn in ' + path)

    around = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    contour = [start]
    here, back = start, 4
    for _ in range(200000):
        moved = False
        for k in range(8):
            d = (back + 1 + k) % 8
            nx, ny = here[0] + around[d][0], here[1] + around[d][1]
            if 0 <= nx < W and 0 <= ny < H and inside[ny][nx]:
                back = (d + 5) % 8
                here = (nx, ny)
                contour.append(here)
                moved = True
                break
        if not moved:
            break
        if here == start and len(contour) > 10:
            break

    # Evenly spaced points, then smoothed twice, because a boundary walked a
    # pixel at a time is a staircase.
    def far(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    whole = sum(far(contour[i], contour[(i + 1) % len(contour)])
                for i in range(len(contour)))
    spread, want, gone, i = [], 0.0, 0.0, 0
    while len(spread) < POINTS and i < len(contour):
        a, b = contour[i], contour[(i + 1) % len(contour)]
        step = far(a, b)
        while gone + step >= want and len(spread) < POINTS:
            t = (want - gone) / step if step else 0
            spread.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            want += whole / POINTS
        gone += step
        i += 1

    for _ in range(2):
        spread = [((spread[j - 1][0] + spread[j][0] * 2 + spread[(j + 1) % POINTS][0]) / 4,
                   (spread[j - 1][1] + spread[j][1] * 2 + spread[(j + 1) % POINTS][1]) / 4)
                  for j in range(POINTS)]

    xs = [p[0] for p in spread]
    ys = [p[1] for p in spread]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    # AppKit's y grows upward and the file's grows downward.
    return [((p[0] - mx) / span, -(p[1] - my) / span) for p in spread]


def swift(shape):
    rows = []
    for i in range(0, len(shape), 3):
        rows.append('        ' + ', '.join('(%.4f, %.4f)' % (x, y)
                                           for x, y in shape[i:i + 3]) + ',')
    return '\n'.join(rows)


def main():
    art = sys.argv[1]
    shape = trace(art)

    if '--print' in sys.argv:
        print(swift(shape))
        return 0

    source = open(sys.argv[2]).read()
    block = re.search(r'static let outline: \[\(CGFloat, CGFloat\)\] = \[(.*?)\n    \]',
                      source, re.S)
    if not block:
        print('no outline in', sys.argv[2])
        return 1
    have = [float(n) for n in re.findall(r'-?[\d.]+', block.group(1))]
    if len(have) != POINTS * 2:
        print('the outline has %d numbers, the drawing gives %d'
              % (len(have), POINTS * 2))
        return 1
    worst = 0.0
    for i, (x, y) in enumerate(shape):
        worst = max(worst, abs(have[i * 2] - x), abs(have[i * 2 + 1] - y))
    if worst > 0.004:
        print('the outline is %.4f off the drawing at its worst' % worst)
        return 1
    print('the outline is the drawing (worst %.4f)' % worst)
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Draw Kliner as an SVG, with his eyes as paths of their own.

The app draws him from a PNG, which is right there and wrong on a web page: a
picture cannot blink at somebody, and a picture at one size is a picture at one
size. This walks the same two drawings the app uses — the outline for his shape
and the artwork for his eyes — and writes them out as three paths, so the page
can move the eyes without moving the face.

    websvg.py assets/app/outline.png app/Resources/mascot@3x.png assets/web/kliner.svg
"""
import math
import struct
import sys
import zlib
from collections import deque

ROUND = 3


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


def blobs(w, h, want):
    """Every run of pixels the test says yes to, as a list of point lists."""
    seen = [[False] * w for _ in range(h)]
    found = []
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not want(x, y):
                continue
            queue = deque([(x, y)])
            seen[y][x] = True
            run = []
            while queue:
                cx, cy = queue.popleft()
                run.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and want(nx, ny):
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            found.append(run)
    return found


def edge(inside, w, h, start):
    """Moore's walk round the outside of a run."""
    around = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    walk = [start]
    here, back = start, 4
    for _ in range(400000):
        moved = False
        for k in range(8):
            d = (back + 1 + k) % 8
            nx, ny = here[0] + around[d][0], here[1] + around[d][1]
            if 0 <= nx < w and 0 <= ny < h and inside[ny][nx]:
                back = (d + 5) % 8
                here = (nx, ny)
                walk.append(here)
                moved = True
                break
        if not moved:
            break
        if here == start and len(walk) > 10:
            break
    return walk


def smooth(walk, points):
    """Evenly spaced, then averaged twice: a boundary walked a pixel at a time
    is a staircase, and a staircase drawn at any size is a staircase."""
    def far(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    whole = sum(far(walk[i], walk[(i + 1) % len(walk)]) for i in range(len(walk)))
    if whole <= 0:
        return []
    spread, want, gone, i = [], 0.0, 0.0, 0
    while len(spread) < points and i < len(walk):
        a, b = walk[i], walk[(i + 1) % len(walk)]
        step = far(a, b)
        while gone + step >= want and len(spread) < points:
            t = (want - gone) / step if step else 0
            spread.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            want += whole / points
        gone += step
        i += 1
    n = len(spread)
    for _ in range(2):
        spread = [((spread[j - 1][0] + spread[j][0] * 2 + spread[(j + 1) % n][0]) / 4,
                   (spread[j - 1][1] + spread[j][1] * 2 + spread[(j + 1) % n][1]) / 4)
                  for j in range(n)]
    return spread


def curve(points):
    """A closed path through the points, each corner rounded off by putting the
    handles a third of the way along the chords either side of it. Straight
    lines between 180 samples look like 180 straight lines."""
    n = len(points)
    out = ['M %.*f %.*f' % (ROUND, points[0][0], ROUND, points[0][1])]
    for i in range(n):
        p0 = points[(i - 1) % n]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        out.append('C %.*f %.*f %.*f %.*f %.*f %.*f'
                   % (ROUND, c1[0], ROUND, c1[1],
                      ROUND, c2[0], ROUND, c2[1],
                      ROUND, p2[0], ROUND, p2[1]))
    out.append('Z')
    return ' '.join(out)


def main():
    shape, art, where = sys.argv[1], sys.argv[2], sys.argv[3]

    # ---- his shape, out of the drawing of it ------------------------------
    w0, h0, channels, px = pixels(shape)

    def drawn(x, y):
        i = (y * w0 + x) * channels
        r, g, b = px[i], px[i + 1], px[i + 2]
        a = px[i + 3] if channels == 4 else 255
        return a >= 100 and (g - r > 25 or b - r > 25) and r < 220

    pad = 6
    W, H = w0 + 2 * pad, h0 + 2 * pad
    wall = [[False] * W for _ in range(H)]
    for y in range(h0):
        for x in range(w0):
            if drawn(x, y):
                wall[y + pad][x + pad] = True

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
    body = smooth(edge(inside, W, H, start), 180)

    xs = [p[0] for p in body]
    ys = [p[1] for p in body]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))

    # A hundred wide, centred on nothing, so the page can put him anywhere at
    # any size without a single number in the markup meaning anything.
    def place(p):
        return ((p[0] - mx) / span * 100 + 50, (p[1] - my) / span * 100 + 50)

    body = [place(p) for p in body]

    # ---- his eyes, out of the artwork ------------------------------------
    ew, eh, echannels, epx = pixels(art)

    def hole(x, y):
        return epx[(y * ew + x) * echannels + echannels - 1] < 128

    holes = []
    for run in blobs(ew, eh, hole):
        rx = [p[0] for p in run]
        ry = [p[1] for p in run]
        if min(rx) == 0 or max(rx) == ew - 1 or min(ry) == 0 or max(ry) == eh - 1:
            continue
        holes.append(run)
    holes.sort(key=len, reverse=True)
    if len(holes) < 2:
        print('could not find two eyes in', art)
        return 1
    holes = sorted(holes[:2], key=lambda run: min(p[0] for p in run))

    # The artwork is square and his shape fills it, so the two drawings share a
    # middle and a width, and the eyes land where they belong.
    exs = [p[0] for row in blobs(ew, eh, lambda x, y: not hole(x, y)) for p in row]
    eys = [p[1] for row in blobs(ew, eh, lambda x, y: not hole(x, y)) for p in row]
    emx, emy = (min(exs) + max(exs)) / 2, (min(eys) + max(eys)) / 2
    espan = max(max(exs) - min(exs), max(eys) - min(eys))

    eyes = []
    for run in holes:
        grid = [[False] * ew for _ in range(eh)]
        for x, y in run:
            grid[y][x] = True
        walk = edge(grid, ew, eh, min(run, key=lambda p: (p[1], p[0])))
        made = smooth(walk, 44)
        eyes.append([((p[0] - emx) / espan * 100 + 50,
                      (p[1] - emy) / espan * 100 + 50) for p in made])

    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none">
  <path class="kliner-body" d="%s" fill="currentColor"/>
  <g class="kliner-eyes">
    <path class="kliner-eye kliner-eye-left" d="%s" fill="var(--kliner-eye, #17120f)"/>
    <path class="kliner-eye kliner-eye-right" d="%s" fill="var(--kliner-eye, #17120f)"/>
  </g>
</svg>
''' % (curve(body), curve(eyes[0]), curve(eyes[1]))
    open(where, 'w').write(svg)
    print('%s: body %d points, eyes %d and %d'
          % (where, len(body), len(eyes[0]), len(eyes[1])))
    return 0


if __name__ == '__main__':
    sys.exit(main())

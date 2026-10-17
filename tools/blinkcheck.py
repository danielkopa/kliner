#!/usr/bin/env python3
#
#   tools/blinkcheck.py — are both eyes shut in the blink frame?
#
#   Kliner's eyes are two quote marks. In the wordmark they stand in front of
#   the word; the mascot is the two of them and nothing else. So in either
#   picture the eyes are its two marks furthest to the left. When it blinks,
#   both marks must be replaced by two lids of the same width. One lid, or two
#   of different widths, is the bug that kept coming back — so this reads the
#   pixels rather than trusting the drawing code.
#
#   It used to look for the quotes in the right quarter of the wordmark, where
#   they came after the word, and for two holes cut out of the mascot, which
#   was a face then. On the art as it is now that measured letters of the
#   word, and found no holes at all.
#
#       blinkcheck.py FRAME            both eyes are lids, of one width
#       blinkcheck.py --holes FRAME    there are two eyes, of one width
#       blinkcheck.py --shut A B       A's eyes are at most a third as tall as B's
#
#   Reads a PNG with no libraries, because the test suite has none.

import sys, zlib
from struct import unpack


def read(path):
    data = open(path, "rb").read()
    i, width, height, idat = 8, 0, 0, b""
    while i < len(data):
        length = unpack(">I", data[i:i + 4])[0]
        kind = data[i + 4:i + 8]
        if kind == b"IHDR":
            width, height = unpack(">II", data[i + 8:i + 16])
        if kind == b"IDAT":
            idat += data[i + 8:i + 8 + length]
        i += 12 + length

    raw = zlib.decompress(idat)
    stride, rows, prev, pos = width * 4, [], bytearray(width * 4), 0
    for _ in range(height):
        filt = raw[pos]; pos += 1
        cur = bytearray(raw[pos:pos + stride]); pos += stride
        for x in range(stride):
            a = cur[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if filt == 1:   cur[x] = (cur[x] + a) & 255
            elif filt == 2: cur[x] = (cur[x] + b) & 255
            elif filt == 3: cur[x] = (cur[x] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                near = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[x] = (cur[x] + near) & 255
        rows.append(bytes(cur)); prev = cur
    return width, height, rows


def marks(width, height, rows):
    """Every mark in the picture, left to right, as [x0, x1, y0, y1].

    A mark is ink that holds together: pixels over 120 in the alpha, touching
    side or corner. Pieces that share columns are one mark, so the dot of the
    i is part of the i, and a quote mark that comes apart in the alpha is
    still one eye."""
    inked = [[rows[y][x * 4 + 3] > 120 for x in range(width)] for y in range(height)]
    seen = [[False] * width for _ in range(height)]
    found = []
    for y in range(height):
        for x in range(width):
            if seen[y][x] or not inked[y][x]:
                continue
            seen[y][x] = True
            stack, box = [(x, y)], [x, x, y, y]
            while stack:
                cx, cy = stack.pop()
                box = [min(box[0], cx), max(box[1], cx), min(box[2], cy), max(box[3], cy)]
                for nx in (cx - 1, cx, cx + 1):
                    for ny in (cy - 1, cy, cy + 1):
                        if 0 <= nx < width and 0 <= ny < height \
                                and inked[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
            found.append(box)
    found.sort()
    out = []
    for x0, x1, y0, y1 in found:
        if out and x0 <= out[-1][1]:
            last = out[-1]
            out[-1] = [last[0], max(last[1], x1), min(last[2], y0), max(last[3], y1)]
        else:
            out.append([x0, x1, y0, y1])
    return out


def eyes(path):
    """The two eyes as (width, height), or None when there are not two marks."""
    width, height, rows = read(path)
    found = marks(width, height, rows)
    if len(found) < 2:
        return None
    return [(x1 - x0 + 1, y1 - y0 + 1) for x0, x1, y0, y1 in found[:2]]


def main(files):
    if "--shut" in sys.argv:
        if len(files) < 2:
            print("--shut needs the shut frame and the open one")
            return 2
        shut, open_ = eyes(files[0]), eyes(files[1])
        if not shut or not open_:
            print("could not find two eyes in both frames")
            return 1
        a = max(tall for _, tall in shut)
        b = max(tall for _, tall in open_)
        # A third, not the seven tenths this used to allow: the halfway frame
        # of these eyes is just over half as tall as the open one, and
        # halfway is not shut.
        if a * 3 > b:
            print("the shut eye is %d tall against %d open: it is not a lid" % (a, b))
            return 1
        print("shut %d, open %d" % (a, b))
        return 0

    found = eyes(files[0])
    if not found:
        print("fewer than two marks: an eye is missing")
        return 1
    (a, tall_a), (b, tall_b) = found

    if "--holes" in sys.argv:
        # Named for when the eyes were holes in a face. It asks the same of
        # the eyes as they are now: are there two, and do they match.
        if abs(a - b) > max(2, (a + b) // 6):
            print("the two eyes are %d and %d wide: they do not match" % (a, b))
            return 1
        print("two eyes, %d and %d wide" % (a, b))
        return 0

    # A lid is at least three times as wide as it is tall. An open eye is
    # nearly twice as tall as it is wide.
    if tall_a * 3 > a or tall_b * 3 > b:
        print("the eyes are %dx%d and %dx%d: those are not lids" % (a, tall_a, b, tall_b))
        return 1
    if abs(a - b) > 1:
        print("the two lids are %d and %d wide: they do not match" % (a, b))
        return 1

    print("two lids, %d and %d wide" % (a, b))
    return 0


if __name__ == "__main__":
    files = [a for a in sys.argv[1:] if not a.startswith("-")]
    try:
        sys.exit(main(files or ["app/Resources/wordmark-blink@3x.png"]))
    except Exception as trouble:
        # Not 1, which --shut gives for "not shut": a frame that is missing
        # or cannot be read is neither shut nor open.
        print("could not read the frame: %s" % trouble)
        sys.exit(2)

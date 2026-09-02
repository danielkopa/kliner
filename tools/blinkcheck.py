#!/usr/bin/env python3
#
#   tools/blinkcheck.py — are both eyes shut in the blink frame?
#
#   The quote after the o is nimo's eyes. When it blinks, both marks must be
#   replaced by two lids of the same width. One lid, or two of different
#   widths, is the bug that kept coming back — so this reads the pixels rather
#   than trusting the drawing code.
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


def runs_of_ink(width, height, rows, fromFraction):
    start = int(width * fromFraction)
    marks, run = [], None
    for x in range(start, width):
        inked = any(rows[y][x * 4 + 3] > 120 for y in range(height))
        if inked and run is None:
            run = x
        if not inked and run is not None:
            marks.append((run, x - 1)); run = None
    if run is not None:
        marks.append((run, width - 1))
    return marks


def holes(width, height, rows):
    """Eyes cut out of a shape, read along the line they sit on.

    A band will not do: no column of the face is clear all the way down. The
    eyes are found on one row, between the shape's own two edges."""
    best = []
    for y in range(int(height * 0.28), int(height * 0.55)):
        row = [rows[y][x * 4 + 3] > 120 for x in range(width)]
        if True not in row:
            continue
        left, right = row.index(True), len(row) - 1 - row[::-1].index(True)
        gaps, run = [], None
        for x in range(left, right + 1):
            if not row[x] and run is None:
                run = x
            if row[x] and run is not None:
                gaps.append((run, x - 1)); run = None
        if len(gaps) > len(best):
            best = gaps
    return best


def eyeHeight(width, height, rows):
    """How tall the two holes are, so an open eye can be told from a shut one."""
    cut = holes(width, height, rows)
    if len(cut) != 2:
        return 0
    tall = 0
    for (x0, x1) in cut:
        middle = (x0 + x1) // 2
        clear = sum(1 for y in range(height) if rows[y][middle * 4 + 3] <= 120
                    and any(rows[k][middle * 4 + 3] > 120 for k in range(y))
                    and any(rows[k][middle * 4 + 3] > 120 for k in range(y + 1, height)))
        tall = max(tall, clear)
    return tall


def main(path):
    width, height, rows = read(path)

    if "--shut" in sys.argv:
        other = [a for a in sys.argv[1:] if not a.startswith("-")][1]
        ow, oh, orows = read(other)
        shut = eyeHeight(width, height, rows)
        open_ = eyeHeight(ow, oh, orows)
        if shut == 0 or open_ == 0:
            print("could not measure both frames")
            return 1
        if shut > open_ * 0.7:
            print("the shut eye is %d tall against %d open: it is not a lid" % (shut, open_))
            return 1
        print("shut %d, open %d" % (shut, open_))
        return 0

    if "--holes" in sys.argv:
        cut = holes(width, height, rows)
        if len(cut) != 2:
            print("%d hole(s) across the middle: expected two eyes" % len(cut))
            return 1
        a = cut[0][1] - cut[0][0] + 1
        b = cut[1][1] - cut[1][0] + 1
        if abs(a - b) > max(2, (a + b) // 6):
            print("the two eyes are %d and %d wide: they do not match" % (a, b))
            return 1
        print("two eyes, %d and %d wide" % (a, b))
        return 0

    marks = runs_of_ink(width, height, rows, 0.75)
    if len(marks) < 2:
        print("only %d mark(s) in the quote: an eye is missing" % len(marks))
        return 1

    left, right = marks[-2], marks[-1]
    a = left[1] - left[0] + 1
    b = right[1] - right[0] + 1
    if abs(a - b) > 1:
        print("the two lids are %d and %d wide: they do not match" % (a, b))
        return 1

    print("two lids, %d and %d wide" % (a, b))
    return 0


if __name__ == "__main__":
    files = [a for a in sys.argv[1:] if not a.startswith("-")]
    sys.exit(main(files[0] if files
                  else "app/Resources/wordmark-blink@3x.png"))

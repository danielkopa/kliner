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


def main(path):
    width, height, rows = read(path)
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
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else "app/Resources/wordmark-blink@3x.png"))

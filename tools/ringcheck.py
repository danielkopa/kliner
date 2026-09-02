#!/usr/bin/env python3
"""Check the waiting ring is drawn round the face rather than round the room
the face is standing in.

Thinking draws the face at a fixed width and traces the artwork's own outline
at a fixed reach from the centre. The artwork's shape reaches some fraction of
its width, which this measures out of the file; the ring should land a little
outside that and nowhere near twice it.

    ringcheck.py app/Resources/mascot@3x.png app/Sources/main.swift
"""
import re
import struct
import sys
import zlib


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


def main():
    art, source = sys.argv[1], sys.argv[2]
    w, h, channels, px = pixels(art)

    middle = (w - 1) / 2.0
    reach = 0
    for y in range(h):
        for x in range(w):
            if px[(y * w + x) * channels + channels - 1] <= 20:
                continue
            far = ((x - middle) ** 2 + (y - middle) ** 2) ** 0.5
            reach = max(reach, far)
    share = reach / w

    text = open(source).read()
    wide = re.search(r'face\.widthAnchor\.constraint\(equalToConstant: ([\d.]+)\)', text)
    ring = re.search(r'Thinking\.path\(around: middle, reach: ([\d.]+)\)', text)
    if not wide or not ring:
        print('could not find the face size or the ring reach in', source)
        return 1

    drawn = float(wide.group(1)) * share
    asked = float(ring.group(1))
    if asked < drawn + 2:
        print('the ring at %.1f cuts through the face, which reaches %.1f'
              % (asked, drawn))
        return 1
    if asked > drawn + 14:
        print('the ring at %.1f hangs %.1f points off a face that reaches %.1f'
              % (asked, asked - drawn, drawn))
        return 1
    print('the ring at %.1f sits %.1f points outside a face reaching %.1f'
          % (asked, asked - drawn, drawn))
    return 0


if __name__ == '__main__':
    sys.exit(main())

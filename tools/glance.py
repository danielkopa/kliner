#!/usr/bin/env python3
"""Make the frames where Kliner looks sideways.

Moving the whole mark two points across is the whole face sliding about. What
was wanted is the eyes going and the face staying, and the art is a flat
picture, so the only way to do that is to draw the frames: find the eyes, lift
them out, and put them back a little to one side.

In the wordmark the eyes are the two quote marks, drawn on nothing. In the
mascot they are two holes cut out of the blob, so lifting one out means filling
it in and cutting a new one along.

    glance.py app/Resources
"""
import sys
from collections import deque

from PIL import Image

# How far the eyes go, in points. Two is nothing on its own and everything at
# this size.
SHIFT = 2


def parts(alpha, want):
    """Connected runs of pixels the test says yes to."""
    w, h = alpha.size
    px = alpha.load()
    seen = [[False] * w for _ in range(h)]
    out = []
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not want(px[x, y]):
                continue
            queue = deque([(x, y)])
            seen[y][x] = True
            found = []
            while queue:
                cx, cy = queue.popleft()
                found.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and want(px[nx, ny]):
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            out.append(found)
    return out


def eyes(image, holes):
    """The two runs that are the eyes.

    In the mascot they are the two biggest holes that do not touch the edge of
    the picture. In the wordmark they are the two rightmost marks, which is
    where the quotes after the word are, and nothing else out there is small.
    """
    w, h = image.size
    alpha = image.split()[3]

    if holes:
        inside = []
        for run in parts(alpha, lambda v: v < 128):
            xs = [p[0] for p in run]
            ys = [p[1] for p in run]
            if min(xs) == 0 or max(xs) == w - 1 or min(ys) == 0 or max(ys) == h - 1:
                continue
            inside.append(run)
        inside.sort(key=len, reverse=True)
        keep = inside[:2]
        tails = inside[2:]
    else:
        marks = parts(alpha, lambda v: v >= 128)
        marks.sort(key=lambda run: -min(p[0] for p in run))
        keep = marks[:2]
        tails = marks[2:]

    if len(keep) < 2:
        return []

    # A quote mark can break into a body and a tail in the alpha. Anything
    # sitting inside an eye's box, give or take two pixels, is part of it.
    box = []
    for run in keep:
        xs = [p[0] for p in run]
        ys = [p[1] for p in run]
        box.append((min(xs) - 2, max(xs) + 2, min(ys) - 2, max(ys) + 2))
    for run in tails:
        if len(run) > len(keep[0]):
            continue
        x, y = run[0]
        for x0, x1, y0, y1 in box:
            if x0 <= x <= x1 and y0 <= y <= y1:
                keep.append(run)
                break
    return keep


def shape(out, colour, kind, box, scale):
    """Draw one eye, in place of the one that was lifted out."""
    px = out.load()
    w, h = out.size
    x0, x1, y0, y1 = box
    mx, my = (x0 + x1) / 2.0, (y0 + y1) / 2.0

    if kind == "round":
        # As wide as the eye was, and round, so the face reads as surprised
        # rather than as a different face.
        r = (x1 - x0 + 1) / 2.0
        for y in range(int(my - r) - 1, int(my + r) + 2):
            for x in range(int(mx - r) - 1, int(mx + r) + 2):
                if 0 <= x < w and 0 <= y < h:
                    if (x - mx) ** 2 + (y - my) ** 2 <= r * r:
                        px[x, y] = colour
        return

    # A dash: as wide as the eye was, a third as tall, on its middle line.
    tall = max(2 * scale, (y1 - y0 + 1) // 3)
    for y in range(int(my - tall / 2), int(my + tall / 2) + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < w and 0 <= y < h:
                px[x, y] = colour


def look(image, holes, shift, kind=None):
    """The same picture with its eyes moved sideways."""
    out = image.copy()
    px = out.load()
    was = image.load()
    found = eyes(image, holes)
    if not found:
        return None

    # What to put where an eye was. In the mascot that is the blob it was cut
    # out of; in the wordmark it is nothing at all.
    if holes:
        filler = None
        for run in found:
            x, y = run[0]
            for dx in range(1, 8):
                if x - dx >= 0 and was[x - dx, y][3] >= 128:
                    filler = was[x - dx, y]
                    break
            if filler:
                break
        if filler is None:
            return None
    else:
        filler = (0, 0, 0, 0)

    # What an eye is drawn in: the colour it already was, or, for a hole cut
    # out of a blob, nothing at all.
    ink = (0, 0, 0, 0)
    if not holes:
        best = 0
        for run in found:
            for x, y in run:
                if was[x, y][3] > best:
                    best = was[x, y][3]
                    ink = was[x, y]

    moved = []
    boxes = []
    for run in found:
        xs = [p[0] for p in run]
        ys = [p[1] for p in run]
        boxes.append((min(xs), max(xs), min(ys), max(ys)))
        for x, y in run:
            moved.append(((x, y), was[x, y]))
            px[x, y] = filler

    if kind is not None:
        for box in boxes:
            shape(out, ink, kind, box, max(1, image.size[0] // 78))
        return out

    w, h = out.size
    for (x, y), colour in moved:
        nx = x + shift
        if 0 <= nx < w:
            px[nx, y] = colour
    return out


def clear(image, side):
    """How many fully transparent columns the picture has at one edge."""
    w, h = image.size
    alpha = image.split()[3].load()
    count = 0
    for i in range(w):
        x = i if side < 0 else w - 1 - i
        if any(alpha[x, y] >= 8 for y in range(h)):
            break
        count += 1
    return count


def widen(path, pad):
    """Give a picture room either side, once.

    The quote marks in the wordmark sit against the right edge of it, so eyes
    that move would move off the picture. Every frame of the wordmark is given
    the same margin, so they still line up with one another, and a picture that
    already has the margin is left alone.
    """
    image = Image.open(path).convert("RGBA")
    if clear(image, -1) >= pad and clear(image, 1) >= pad:
        return image
    w, h = image.size
    wider = Image.new("RGBA", (w + pad * 2, h), (0, 0, 0, 0))
    wider.paste(image, (pad, 0))
    wider.save(path)
    return wider


def only_eyes(base, aside, w, h):
    """Everything that differs between two frames, as a box."""
    a, b = base.load(), aside.load()
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if a[x, y] != b[x, y]:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), max(xs), min(ys), max(ys)


def check(where):
    """The frames must differ from the one they came from in one small place,
    up near the top. Anything wider than that is the whole mark moving, which
    is the thing this replaced."""
    for name, sides in (("wordmark", ("right", "round", "dash")),
                        ("mascot", ("left", "right", "round", "dash"))):
        base = Image.open("%s/%s@3x.png" % (where, name)).convert("RGBA")
        w, h = base.size
        for side in sides:
            aside = Image.open("%s/%s-%s@3x.png" % (where, name, side)).convert("RGBA")
            if aside.size != base.size:
                print("%s-%s is not the same size as %s" % (name, side, name))
                return 1
            box = only_eyes(base, aside, w, h)
            if box is None:
                print("%s-%s is the same picture as %s" % (name, side, name))
                return 1
            x0, x1, y0, y1 = box
            if (x1 - x0) > w * 0.34 or (y1 - y0) > h * 0.34:
                print("%s-%s changes %dx%d of a %dx%d picture: that is not the eyes"
                      % (name, side, x1 - x0, y1 - y0, w, h))
                return 1
            if (y0 + y1) / 2 > h * 0.66:
                print("%s-%s changes the bottom of the picture, not the eyes"
                      % (name, side))
                return 1
    print("the eyes move and nothing else does")
    return 0


def main():
    where = sys.argv[1]
    if "--check" in sys.argv:
        return check(where)
    made = 0
    # The quote marks sit at the end of the word with a letter right behind
    # them, so in the wordmark they can only look outward. The mascot has room
    # on both sides of its face.
    for name, holes, ways in (("wordmark", False, ((1, "right"),)),
                              ("mascot", True, ((-1, "left"), (1, "right")))):
        for scale, tag in ((1, ""), (2, "@2x"), (3, "@3x")):
            pad = SHIFT * scale
            if not holes:
                for frame in ("", "-half", "-blink"):
                    widen("%s/%s%s%s.png" % (where, name, frame, tag), pad)
            path = "%s/%s%s.png" % (where, name, tag)
            image = Image.open(path).convert("RGBA")
            for way, side in ways:
                shifted = look(image, holes, way * SHIFT * scale)
                if shifted is None:
                    print("could not find the eyes in", path)
                    return 1
                shifted.save("%s/%s-%s%s.png" % (where, name, side, tag))
                made += 1

            # Two more eyes to wear: round, and a pair of dashes. A face with
            # one expression is a picture; a face with three is somebody.
            for kind in ("round", "dash"):
                drawn = look(image, holes, 0, kind=kind)
                if drawn is None:
                    print("could not find the eyes in", path)
                    return 1
                drawn.save("%s/%s-%s%s.png" % (where, name, kind, tag))
                made += 1
    print("%d frames" % made)
    return 0


if __name__ == "__main__":
    sys.exit(main())

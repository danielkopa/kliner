#!/usr/bin/env python3
"""Make the frames where Kliner looks sideways, and prove the ones there are.

Moving the whole mark two points across is the whole face sliding about. What
was wanted is the eyes going and the face staying, and the art is a flat
picture, so the only way to do that is to draw the frames: find the eyes, lift
them out, and put them back a little to one side.

The eyes are two quote marks, drawn on nothing. In the wordmark they stand in
front of the word, so they are its two marks furthest to the left; the mascot
is the two of them and nothing else. (The mascot used to be a blob with the
eyes cut out of it, and the quotes came after the word. This looked for those
until the art was redrawn.)

    glance.py DIR            draw the looking frames in DIR from the open ones
    glance.py DIR --check    prove the frames in DIR move the eyes, nothing else

The frames in app/Resources came with the art, drawn as the same eyes moved,
so the suite draws its own into a copy rather than over them.
"""

import sys
from collections import deque

from PIL import Image

# How far the eyes go, in points. Two is nothing on its own and everything at
# this size.
SHIFT = 2


def parts(alpha, want):
    """Connected runs of pixels the test says yes to, touching side or corner."""
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
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                               (1, 1), (1, -1), (-1, 1), (-1, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and want(px[nx, ny]):
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            out.append(found)
    return out


def eyes(image):
    """The two runs of pixels that are the eyes.

    They are the two marks furthest to the left: in the wordmark the quotes
    stand in front of the word, and the mascot is the two of them and nothing
    else. A mark is ink that holds together, and pieces that share columns
    are one mark, so a quote mark that comes apart in the alpha is still one
    eye, and the dot of the i is part of the i.
    """
    alpha = image.split()[3]
    found = sorted(parts(alpha, lambda v: v > 120),
                   key=lambda run: min(p[0] for p in run))
    marks = []
    for run in found:
        left = min(p[0] for p in run)
        right = max(p[0] for p in run)
        if marks and left <= marks[-1][1]:
            marks[-1][1] = max(marks[-1][1], right)
            marks[-1][2].extend(run)
        else:
            marks.append([left, right, list(run)])
    if len(marks) < 2:
        return []
    return [marks[0][2], marks[1][2]]


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


def look(image, shift, kind=None):
    """The same picture with its eyes moved sideways, or drawn as another kind."""
    out = image.copy()
    px = out.load()
    was = image.load()
    w, h = image.size
    found = eyes(image)
    if not found:
        return None

    # Each eye with its soft edge: everything with any ink at all inside its
    # box, give or take two pixels. Lifting only the solid part would leave
    # the outline of where it was behind.
    boxes = []
    lifted = {}
    for run in found:
        xs = [p[0] for p in run]
        ys = [p[1] for p in run]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        boxes.append((x0, x1, y0, y1))
        for y in range(max(0, y0 - 2), min(h, y1 + 3)):
            for x in range(max(0, x0 - 2), min(w, x1 + 3)):
                if was[x, y][3] > 0:
                    lifted[(x, y)] = was[x, y]

    # What an eye is drawn in: the most solid colour it already was. The eyes
    # are drawn on nothing, so where one was is nothing at all.
    ink = max(lifted.values(), key=lambda colour: colour[3])
    for x, y in lifted:
        px[x, y] = (0, 0, 0, 0)

    if kind is not None:
        for box in boxes:
            shape(out, ink, kind, box, max(1, w // 78))
        return out

    for (x, y), colour in lifted.items():
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

    Eyes that move can move off the edge of the picture. Every frame of the
    wordmark is given the same margin, so they still line up with one another,
    and a picture that already has the margin is left alone.
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
    """The frames must differ from the one they came from only where the eyes
    are: inside the box round the two of them, grown by as far as an eye moves
    and two pixels of soft edge. A change anywhere else is the whole mark
    moving, or a letter, which is the thing this replaced."""
    grow = SHIFT * 3 + 2
    for name, sides in (("wordmark", ("right", "round", "dash")),
                        ("mascot", ("left", "right", "round", "dash"))):
        base = Image.open("%s/%s@3x.png" % (where, name)).convert("RGBA")
        w, h = base.size
        found = eyes(base)
        if not found:
            print("could not find the eyes in %s" % name)
            return 1
        xs = [p[0] for run in found for p in run]
        ys = [p[1] for run in found for p in run]
        x0, x1 = min(xs) - grow, max(xs) + grow
        y0, y1 = min(ys) - grow, max(ys) + grow
        for side in sides:
            aside = Image.open("%s/%s-%s@3x.png" % (where, name, side)).convert("RGBA")
            if aside.size != base.size:
                print("%s-%s is not the same size as %s" % (name, side, name))
                return 1
            box = only_eyes(base, aside, w, h)
            if box is None:
                print("%s-%s is the same picture as %s" % (name, side, name))
                return 1
            bx0, bx1, by0, by1 = box
            if bx0 < x0 or bx1 > x1 or by0 < y0 or by1 > y1:
                print("%s-%s changes x %d-%d, y %d-%d of a %dx%d picture, and the eyes"
                      " are within x %d-%d, y %d-%d: that is not the eyes"
                      % (name, side, bx0, bx1, by0, by1, w, h,
                         max(0, x0), min(w - 1, x1), max(0, y0), min(h - 1, y1)))
                return 1
    print("the eyes move and nothing else does")
    return 0


def main():
    where = sys.argv[1]
    if "--check" in sys.argv:
        return check(where)
    made = 0
    # The wordmark has one glance, to the right, towards the word: there is
    # room for it between the eyes and the k. The mascot is the two eyes on
    # their own, with room either side, so it looks both ways.
    for name, ways in (("wordmark", ((1, "right"),)),
                       ("mascot", ((-1, "left"), (1, "right")))):
        for scale, tag in ((1, ""), (2, "@2x"), (3, "@3x")):
            pad = SHIFT * scale
            if name == "wordmark":
                for frame in ("", "-half", "-blink"):
                    widen("%s/%s%s%s.png" % (where, name, frame, tag), pad)
            path = "%s/%s%s.png" % (where, name, tag)
            image = Image.open(path).convert("RGBA")
            for way, side in ways:
                shifted = look(image, way * SHIFT * scale)
                if shifted is None:
                    print("could not find the eyes in", path)
                    return 1
                shifted.save("%s/%s-%s%s.png" % (where, name, side, tag))
                made += 1

            # Two more eyes to wear: round, and a pair of dashes. A face with
            # one expression is a picture; a face with three is somebody.
            for kind in ("round", "dash"):
                drawn = look(image, 0, kind=kind)
                if drawn is None:
                    print("could not find the eyes in", path)
                    return 1
                drawn.save("%s/%s-%s%s.png" % (where, name, kind, tag))
                made += 1
    print("%d frames" % made)
    return 0


if __name__ == "__main__":
    sys.exit(main())

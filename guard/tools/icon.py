# The mark: the panel's own shape. A rule down the left and the two lines of a
# warning beside it — the thing you actually see when Kliner Guard speaks.
from PIL import Image, ImageDraw

INK = (22, 22, 20, 255)
PAPER = (246, 246, 244, 255)

def draw(size):
    s = size * 8                       # draw large, shrink down: cheap antialiasing
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = int(s * 0.22)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=INK)

    bar_x = int(s * 0.26)
    bar_w = max(2, int(s * 0.075))
    top, bottom = int(s * 0.28), int(s * 0.72)
    d.rectangle([bar_x, top, bar_x + bar_w, bottom], fill=PAPER)

    line_x = bar_x + bar_w + int(s * 0.10)
    right = int(s * 0.76)
    thick = max(2, int(s * 0.085))
    d.rectangle([line_x, top, right, top + thick], fill=PAPER)
    d.rectangle([line_x, top + int(s * 0.16), int(s * 0.66), top + int(s * 0.16) + thick], fill=PAPER)
    d.rectangle([line_x, top + int(s * 0.32), right, top + int(s * 0.32) + thick], fill=PAPER)

    return im.resize((size, size), Image.LANCZOS)

for size in (16, 32, 48, 128):
    draw(size).save('extension/icon%d.png' % size)
print('icons: 16 32 48 128')

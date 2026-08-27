#!/usr/bin/env python3
"""Draw the README demo: a terminal that plays a nimo session.

An animated SVG rather than a GIF — it stays sharp at any size, weighs a few
kilobytes instead of a few megabytes, and the frames are text in this file, so
the demo can be corrected in a diff like anything else.

    python3 tools/make-demo.py > assets/demo.svg
"""

import sys

# the palette the terminal uses
INK   = "#D4DBDE"
DIM   = "#6A7679"
CYAN  = "#5FD3C6"
WARM  = "#D9BA74"
BRIGHT= "#EEF2F3"
BG    = "#0B0D0E"
EDGE  = "#1A1E20"

# Each frame is a list of (text, colour). "|" starts a colour run inline:
# lines are kept plain on purpose — the demo should read like the real thing.
FRAMES = [
    # 1 — a bare prompt
    [("$ min", DIM)],

    # 2 — nimo says hello
    [("", INK),
     ("             ╭───────────────╮", CYAN),
     ("           ╭─╯               ╰─╮", CYAN),
     ("          ╭╯                   ╰╮", CYAN),
     ("          │     ●         ●     │", CYAN),
     ("          │                     │", CYAN),
     ("          │      ╰───────╯      │", CYAN),
     ("          ╰╮                   ╭╯", CYAN),
     ("           ╰─╮               ╭─╯", CYAN),
     ("             ╰───────────────╯", CYAN),
     ("", INK),
     ("                     nimo", DIM),
     ("", INK),
     ("  / to see what it can do", DIM),
     ("", INK),
     ("  nimo › ", INK)],

    # 3 — typing
    [("  nimo › /clear", INK)],

    # 4 — the menu, counting what it offers
    [("  nimo › /clear", INK),
     ("", INK),
     ("  ╭─ what should be clear? ─────────────────────", DIM),
     ("", INK),
     ("     nothing is deleted — everything can be undone", DIM),
     ("", INK),
     ("   ▸ Desktop        85 items", BRIGHT),
     ("     Downloads      296 items", INK),
     ("     Screenshots    12 screenshots loose", INK),
     ("     Dock           the apps you never open", INK),
     ("     Trash          18 items", INK),
     ("     Everything     all of it, one step at a time", INK)],

    # 5 — down one
    [("  nimo › /clear", INK),
     ("", INK),
     ("  ╭─ what should be clear? ─────────────────────", DIM),
     ("", INK),
     ("     nothing is deleted — everything can be undone", DIM),
     ("", INK),
     ("     Desktop        85 items", INK),
     ("   ▸ Downloads      296 items", BRIGHT),
     ("     Screenshots    12 screenshots loose", INK),
     ("     Dock           the apps you never open", INK),
     ("     Trash          18 items", INK),
     ("     Everything     all of it, one step at a time", INK)],

    # 6 — what it found
    [("  ╭─ your downloads ────────────────────────────", DIM),
     ("", INK),
     ("     Documents                      118 items", INK),
     ("     Archives                        61 items", INK),
     ("     Images                          54 items", INK),
     ("     Video                           31 items", INK),
     ("     Code                            18 items", INK),
     ("     Other                           14 items", INK),
     ("", INK),
     ("     ─────────────────────────────────", DIM),
     ("     In there                       296 items", BRIGHT),
     ("", INK),
     ("  ╰─────────────────────────────────────────────", DIM),
     ("", INK),
     ("  everything moves into  Downloads/Tidy/<kind>/", DIM),
     ("  nothing is deleted, nothing is renamed", DIM)],

    # 7 — the one question
    [("  everything moves into  Downloads/Tidy/<kind>/", DIM),
     ("  nothing is deleted, nothing is renamed", DIM),
     ("", INK),
     ("  Sort 296 items? [y/N] y", INK)],

    # 8 — done
    [("  Sort 296 items? [y/N] y", DIM),
     ("", INK),
     ("  ✓ Sorted — 296 items filed away", CYAN),
     ("  Downloads/Tidy/", DIM),
     ("", INK),
     ("  changed your mind?  min downloads --undo", DIM),
     ("", INK),
     ("  nimo › ", INK)],
]

HOLD = [1.6, 2.6, 1.0, 2.2, 1.6, 2.8, 1.6, 3.0]   # seconds per frame

CHAR_W = 8.4
LINE_H = 19.5
PAD_X  = 22
PAD_Y  = 46
COLS   = 58
ROWS   = 18

WIDTH  = int(PAD_X * 2 + CHAR_W * COLS)
HEIGHT = int(PAD_Y + LINE_H * ROWS + 18)


def esc(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def main():
    total = sum(HOLD)
    out = []
    out.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" '
        f'width="{WIDTH}" height="{HEIGHT}" role="img" '
        f'aria-label="nimo sorting 296 downloads, in a terminal">'
    )
    out.append(
        f'<rect width="{WIDTH}" height="{HEIGHT}" rx="12" fill="{BG}" stroke="{EDGE}"/>'
    )
    for i, cx in enumerate((26, 44, 62)):
        out.append(f'<circle cx="{cx}" cy="24" r="5" fill="#262E30"/>')
    out.append(
        f'<text x="82" y="28" font-family="ui-monospace, SFMono-Regular, Menlo, monospace" '
        f'font-size="11" fill="{DIM}">daniel — min</text>'
    )
    out.append(f'<line x1="0" y1="44" x2="{WIDTH}" y2="44" stroke="{EDGE}"/>')

    start = 0.0
    for frame, hold in zip(FRAMES, HOLD):
        a = start / total
        b = (start + hold) / total
        # a hair of fade at each end, so frames cut cleanly without flicker
        keys = f"0;{max(a - 0.004, 0):.4f};{a:.4f};{b:.4f};{min(b + 0.004, 1):.4f};1"
        vals = "0;0;1;1;0;0"

        out.append('<g opacity="0">')
        out.append(
            f'<animate attributeName="opacity" values="{vals}" keyTimes="{keys}" '
            f'dur="{total:.1f}s" repeatCount="indefinite" calcMode="linear"/>'
        )
        for row, (text, colour) in enumerate(frame):
            if not text:
                continue
            y = PAD_Y + LINE_H * (row + 1)
            out.append(
                f'<text x="{PAD_X}" y="{y:.1f}" xml:space="preserve" '
                f'font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" '
                f'font-size="13" fill="{colour}">{esc(text)}</text>'
            )
        out.append('</g>')
        start += hold

    out.append('</svg>')
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()

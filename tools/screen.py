#!/usr/bin/env python3
"""What a terminal would actually show.

nimo draws its face and then moves the cursor back up to blink the eyes. A
pipe keeps the escape codes as bytes, so a test that greps the raw output
sees a face that is perfectly fine and a screen that is not: the whole
prompt once landed six rows up, on top of the face, and every text-based
check still passed.

This reads a raw terminal stream on stdin and prints the grid a terminal
would end up with — newline, carriage return, and the four cursor moves
(CUU/CUD/CUF/CUB). Colour and every other escape is dropped, because
nothing here is about colour.

    min ... | python3 tools/screen.py
"""

import re
import sys

CSI = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")


def render(data):
    rows = []
    row = col = 0

    def put(ch):
        nonlocal col
        while len(rows) <= row:
            rows.append([])
        line = rows[row]
        while len(line) <= col:
            line.append(" ")
        line[col] = ch
        col += 1

    i = 0
    while i < len(data):
        ch = data[i]
        if ch == "\x1b":
            m = CSI.match(data, i)
            if m:
                arg, final = m.group(1), m.group(2)
                n = int(arg) if arg.isdigit() else 1
                if final == "A":
                    row = max(0, row - n)
                elif final == "B":
                    row += n
                elif final == "C":
                    col += n
                elif final == "D":
                    col = max(0, col - n)
                i = m.end()
                continue
            i += 1
            continue
        if ch == "\n":
            row += 1
            col = 0
        elif ch == "\r":
            col = 0
        elif ch == "\t":
            col = (col // 8 + 1) * 8
        elif ch == "\b":
            col = max(0, col - 1)
        else:
            put(ch)
        i += 1

    return "\n".join("".join(line).rstrip() for line in rows)


if __name__ == "__main__":
    sys.stdout.write(render(sys.stdin.buffer.read().decode("utf-8", "replace")) + "\n")

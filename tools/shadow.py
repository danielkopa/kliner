#!/usr/bin/env python3
"""Two names for one thing in one scope.

`let way = NSStackView()` near the top of a function and `let way: CGFloat`
near the bottom of the same one is a compile error, and it is invisible when
the two are four hundred lines apart. Swift catches it; Swift is also the
thing we are trying not to have to run to find out.

Scopes are counted by braces, with two exceptions that are scopes in Swift
without being braces: every `case` of a switch, and every `catch`.
"""
import re
import sys

DECL = re.compile(r'^\s*(?:let|var)\s+([A-Za-z_]\w*)\s*[:=]')
BRANCH = re.compile(r'^\s*(?:case\b|default\s*:|catch\b)')


def bare(line):
    """The line with its comment and its string contents taken out, so a brace
    inside either of them does not open a scope that never closes."""
    line = re.sub(r'\\.', '', line)
    line = re.sub(r'"[^"]*"', '""', line)
    cut = line.find('//')
    return line if cut < 0 else line[:cut]


def main():
    if len(sys.argv) < 2:
        print("usage: shadow.py <file.swift>")
        return 2

    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        lines = f.readlines()

    depth = 0
    seen = {}            # depth -> {name: line number}
    faults = []
    inside_comment = False

    for n, raw in enumerate(lines, 1):
        text = raw
        if inside_comment:
            if '*/' in text:
                text = text.split('*/', 1)[1]
                inside_comment = False
            else:
                continue
        if '/*' in bare(text):
            head, rest = text.split('/*', 1)
            if '*/' in rest:
                text = head + rest.split('*/', 1)[1]
            else:
                text = head
                inside_comment = True

        stripped = bare(text)

        # A new case or catch starts a scope of its own without a brace.
        if BRANCH.match(stripped):
            seen[depth] = {}

        found = DECL.match(stripped)
        if found:
            name = found.group(1)
            here = seen.setdefault(depth, {})
            if name in here:
                faults.append((n, name, here[name]))
            else:
                here[name] = n

        opened = stripped.count('{')
        closed = stripped.count('}')
        if opened:
            depth += opened
        if closed:
            for _ in range(closed):
                seen.pop(depth, None)
                depth = max(0, depth - 1)

    for n, name, first in faults:
        print("%s:%d: '%s' is already declared at line %d in the same scope"
              % (path, n, name, first))

    if faults:
        return 1
    print("%d lines read, no name declared twice in one scope" % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())

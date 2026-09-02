#!/usr/bin/env python3
"""Catch a view pinned to the edge of something inside itself.

`buttons.trailingAnchor.constraint(equalTo: bell.leadingAnchor)` looks like
every other line in a layout, and if `bell` is inside `buttons` it is a loop:
the row is placed by its contents and its contents are placed by the row.
Auto Layout does not crash on it, it quietly throws constraints away, and the
window comes out with half of it missing.

Nothing here can run a layout, so this reads the source: which views are added
to which, and which constraints tie an edge of one to the opposite edge of the
other.

    loopcheck.py app/Sources/main.swift
"""
import re
import sys

# Pinning a parent's edge to the *same* edge of a child sizes the parent, which
# is ordinary. Pinning it to the opposite edge is the loop.
FACING = {
    'leading': 'trailing',
    'trailing': 'leading',
    'top': 'bottom',
    'bottom': 'top',
}

ADDS = re.compile(r'(\w+)\.add(?:ArrangedSubview|Subview)\((\w+)\)')
# `for view in [a, b, c] { holder.addSubview(view) }` puts three views in a
# holder without ever naming the pair, which is exactly where the loop hid.
WALKS = re.compile(r'for (\w+) in \[([^\]]+)\]')
TIES = re.compile(r'(\w+)\.(\w+)Anchor\.constraint\('
                  r'(?:equalTo|greaterThanOrEqualTo|lessThanOrEqualTo):\s*'
                  r'(\w+)\.(\w+)Anchor')


def main():
    path = sys.argv[1]
    source = open(path).read()

    inside = set()
    for parent, child in ADDS.findall(source):
        inside.add((parent, child))

    lines = source.split('\n')
    for i, text in enumerate(lines):
        walk = WALKS.search(text)
        if not walk:
            continue
        name, listed = walk.group(1), walk.group(2)
        held = [one.strip().lstrip('.') for one in listed.split(',')]
        held = [one for one in held if re.fullmatch(r'\w+', one)]
        for follow in lines[i:i + 4]:
            for parent, child in ADDS.findall(follow):
                if child != name:
                    continue
                for one in held:
                    inside.add((parent, one))

    bad = 0
    for line, text in enumerate(source.split('\n'), start=1):
        for one, edge, two, other in TIES.findall(text):
            if FACING.get(edge) != other:
                continue
            if (one, two) in inside:
                print('%s:%d: %s is pinned to the %s of %s, which is inside it'
                      % (path, line, one, other, two))
                bad += 1
            elif (two, one) in inside:
                print('%s:%d: %s is pinned to the %s of %s, which it is inside'
                      % (path, line, one, other, two))
                bad += 1
    if bad:
        return 1
    print('%d views placed, nothing pinned to its own contents' % len(inside))
    return 0


if __name__ == '__main__':
    sys.exit(main())

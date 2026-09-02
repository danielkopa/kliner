#!/usr/bin/env python3
"""Check that every call to one of our own types names its arguments in the
order that type's initialiser declares them.

Swift will not reorder labelled arguments for you: writing them out of order,
or leaving a required one out, is a compile error rather than a nicety. Nothing
in this repository can compile Swift, so this reads the initialisers out of the
source and checks every call site against them by hand.

    argorder.py app/Sources/main.swift
"""
import re
import sys

DECLARES = re.compile(r'^(?:public |final )*(?:struct|class) (\w+)')


def split_top(text):
    """`text` cut on the commas that are not inside brackets."""
    out, piece, depth = [], '', 0
    for ch in text:
        if ch in '([{<':
            depth += 1
        elif ch in ')]}>':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(piece)
            piece = ''
        else:
            piece += ch
    out.append(piece)
    return out


def initialisers(lines):
    """{type: (labels in order, labels that must be given)}."""
    found = {}
    owner = None
    for i, line in enumerate(lines):
        head = DECLARES.match(line)
        if head:
            owner = head.group(1)
            continue
        if not owner or not re.match(r'^    (?:convenience )?init[?]?\(', line):
            continue

        text = ''
        for follow in lines[i:]:
            text += follow
            if text.count('(') and text.count('(') == text.count(')'):
                break
        inside = text[text.index('(') + 1:text.rindex(')')]

        order, must = [], []
        for one in split_top(inside):
            one = one.strip()
            if not one:
                continue
            # `_ headline: String` is written with no label at the call site,
            # `of many: Int` is written `of:`, and `title: String` is written
            # `title:`. The first word is the one that gets typed.
            head = one.split(':')[0].split()
            if not head or head[0] == '_':
                continue
            order.append(head[0])
            kind = one.split(':', 1)[1] if ':' in one else ''
            # A closure at the end is usually written as a trailing closure,
            # with its label left off, and that is not a missing argument.
            if '=' not in one and '->' not in kind:
                must.append(head[0])
        # A type can have more than one way in. A call has to match one of
        # them, not all of them.
        # Kept, not cleared: a type can declare more than one way in, and the
        # next `class` or `struct` line is what ends its list.
        found.setdefault(owner, []).append((order, must))
    return found


def calls(source, name):
    """Every `Name(` call site, as (line number, [label, ...])."""
    out = []
    for hit in re.finditer(r'(?<![\w.])' + name + r'\(', source):
        start = hit.end()
        depth, i = 1, start
        while i < len(source) and depth:
            if source[i] in '([{':
                depth += 1
            elif source[i] in ')]}':
                depth -= 1
            i += 1
        inside = source[start:i - 1]
        labels, depth = [], 0
        for piece in re.finditer(r'[,()\[\]{}]|(\w+)\s*:', inside):
            ch = piece.group(0)
            if ch and ch[0] in '([{':
                depth += 1
            elif ch and ch[0] in ')]}':
                depth -= 1
            elif piece.group(1) and depth == 0:
                before = inside[:piece.start()].rstrip()
                if not before or before[-1] == ',':
                    labels.append(piece.group(1))
        if labels:
            out.append((source[:hit.start()].count('\n') + 1, labels))
    return out


def main():
    path = sys.argv[1]
    source = open(path).read()
    known = initialisers(source.split('\n'))

    def wrong(order, must, labels):
        """What is wrong with this call against this initialiser, if anything."""
        said = []
        for label in must:
            if label not in labels:
                said.append('needs an argument called %s' % label)
        at = -1
        for label in labels:
            if label not in order:
                said.append('has no argument called %s' % label)
                continue
            if order.index(label) < at:
                said.append('takes %s before %s' % (order[at], label))
            at = max(at, order.index(label))
        return said

    bad = 0
    seen = 0
    for name in sorted(known):
        ways = known[name]
        for line, labels in calls(source, name):
            seen += 1
            trouble = [wrong(order, must, labels) for order, must in ways]
            if any(not one for one in trouble):
                continue          # one of the ways in fits
            for said in min(trouble, key=len):
                print('%s:%d: %s %s' % (path, line, name, said))
                bad += 1
    if bad:
        return 1
    print('%d call sites in order' % seen)
    return 0


if __name__ == '__main__':
    sys.exit(main())

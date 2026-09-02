#!/usr/bin/env python3
"""Check that every call to one of our own structs names its arguments in the
order its init declares them.

Swift will not reorder labelled arguments for you: writing them out of order is
an error, not a nicety. Since this repository cannot compile Swift, this reads
the initialisers out of the source and checks the call sites against them.
"""
import re
import sys


def initialisers(source):
    """{type name: [argument label, ...]} for every struct init in the file."""
    found = {}
    kind = re.compile(r'^(?:public |final )*(?:struct|class) (\w+)')
    name = None
    for chunk in source.split('\n'):
        head = kind.match(chunk)
        if head:
            name = head.group(1)
    # a second pass, because an init belongs to the type declared above it
    lines = source.split('\n')
    owner = None
    for i, line in enumerate(lines):
        head = kind.match(line)
        if head:
            owner = head.group(1)
            continue
        if owner and re.match(r'^    init\(', line):
            text = ''
            for follow in lines[i:]:
                text += follow
                if text.count('(') and text.count('(') == text.count(')'):
                    break
            inside = text[text.index('(') + 1:text.rindex(')')]
            labels = []
            depth = 0
            piece = ''
            for ch in inside:
                if ch in '([{':
                    depth += 1
                elif ch in ')]}':
                    depth -= 1
                if ch == ',' and depth == 0:
                    labels.append(piece)
                    piece = ''
                else:
                    piece += ch
            labels.append(piece)
            clean = []
            must = []
            for one in labels:
                one = one.strip()
                if not one:
                    continue
                label = one.split(':')[0].split()[-1]
                clean.append(label)
                if '=' not in one:
                    must.append(label)
            found[owner] = (clean, must)
            owner = None
    return found


def calls(source, names):
    """Every `Name(` call site, as (type, line number, [label, ...])."""
    out = []
    for name in names:
        for hit in re.finditer(r'(?<![\w.])' + name + r'\(', source):
            start = hit.end()
            depth = 1
            i = start
            while i < len(source) and depth:
                if source[i] in '([{':
                    depth += 1
                elif source[i] in ')]}':
                    depth -= 1
                i += 1
            inside = source[start:i - 1]
            labels = []
            depth = 0
            for piece in re.finditer(r'[,()\[\]{}]|(\w+)\s*:', inside):
                ch = piece.group(0)
                if ch and ch[0] in '([{':
                    depth += 1
                elif ch and ch[0] in ')]}':
                    depth -= 1
                elif piece.group(1) and depth == 0:
                    before = inside[:piece.start()].rstrip()
                    if not before or before[-1] in ',':
                        labels.append(piece.group(1))
            if labels:
                out.append((name, source[:hit.start()].count('\n') + 1, labels))
    return out


def main():
    path = sys.argv[1]
    source = open(path).read()
    known = initialisers(source)
    watch = [n for n in ('Extra', 'Action') if n in known]
    bad = 0
    for name, line, labels in calls(source, watch):
        want, must = known[name]
        for label in must:
            if label not in labels:
                print('%s:%d: %s needs an argument called %s'
                      % (path, line, name, label))
                bad += 1
        seen = -1
        for label in labels:
            if label not in want:
                print('%s:%d: %s has no argument called %s' % (path, line, name, label))
                bad += 1
                continue
            at = want.index(label)
            if at < seen:
                print('%s:%d: %s takes %s before %s'
                      % (path, line, name, want[seen], label))
                bad += 1
            seen = max(seen, at)
    if bad:
        return 1
    print('%d call sites in order' % len(calls(source, watch)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

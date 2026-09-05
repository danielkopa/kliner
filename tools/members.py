#!/usr/bin/env python3
"""Every `self.something` a class writes, the class has to have.

The one compile error this suite could not see coming was a paint routine
edited into the wrong class: it set `self.tile` and read `self.done` inside
`Pick`, which has neither. swiftc said so in a second; nothing here did.

So: walk each class, collect what it declares — stored properties, methods,
and the names its own initialiser takes as `self.x = x` — and then look at
every `self.<name>` inside it. Anything that is neither declared nor a member
of the AppKit class it inherits from is the mistake this file exists to find.

    python3 tools/members.py app/Sources/main.swift
"""
import re
import sys

# What a view, a control or an object already has, used with an explicit self.
# Not the whole of AppKit — only the names this file actually reaches for.
INHERITED = {
    "layer", "wantsLayer", "bounds", "frame", "window", "superview", "subviews",
    "effectiveAppearance", "appearance", "isHidden", "alphaValue", "toolTip",
    "needsLayout", "needsDisplay", "translatesAutoresizingMaskIntoConstraints",
    "trackingAreas", "widthAnchor", "heightAnchor", "topAnchor", "bottomAnchor",
    "leadingAnchor", "trailingAnchor", "centerXAnchor", "centerYAnchor",
    "firstBaselineAnchor", "lastBaselineAnchor", "safeAreaInsets",
    "stringValue", "attributedStringValue", "font", "textColor", "alignment",
    "image", "contentTintColor", "imageScaling", "imageAlignment",
    "isEnabled", "isEditable", "isSelectable", "isBordered", "drawsBackground",
    "backgroundColor", "cornerRadius", "documentView", "contentView",
    "orientation", "spacing", "alignment", "distribution", "edgeInsets",
    "arrangedSubviews", "delegate", "target", "action", "title", "state",
    "material", "blendingMode", "intrinsicContentSize", "fittingSize",
    "lineBreakMode", "maximumNumberOfLines", "usesSingleLineMode",
    "placeholderString", "currentEditor", "isContinuous", "identifier",
    "menu", "tag", "isFlipped", "visibleRect", "enclosingScrollView",
    "contentInsets", "hasVerticalScroller", "documentVisibleRect",
    "symbolConfiguration", "isTemplate", "boxType", "fillColor", "borderWidth",
    "wantsUpdateLayer", "layoutSubtreeIfNeeded", "invalidateIntrinsicContentSize",
    "addSubview", "removeFromSuperview", "addTrackingArea", "removeTrackingArea",
    "convert", "hitTest", "setNeedsDisplay", "sizeToFit", "layoutSubtreeIfNeeded",
    "addArrangedSubview", "removeArrangedSubview", "setCustomSpacing",
    "setContentHuggingPriority", "setContentCompressionResistancePriority",
    "addCursorRect", "resetCursorRects", "updateTrackingAreas", "scroll",
    "animator", "isDescendant", "makeFirstResponder", "becomeFirstResponder",
    "layout", "viewDidMoveToWindow", "viewDidChangeEffectiveAppearance",
    "init",
    "addLayoutGuide", "reflectScrolledClipView", "setFrameSize", "setFrameOrigin",
}

DECL = re.compile(r"^\s*(?:@\w+\s+)*"
                  r"(?:(?:private|fileprivate|public|internal|open)(?:\(set\))?\s+|"
                  r"static\s+|final\s+|override\s+|lazy\s+|weak\s+|unowned\s+|"
                  r"class\s+|mutating\s+|"
                  r"convenience\s+|required\s+|@objc\s+|discardableResult\s+)*"
                  r"(?:let|var|func)\s+([A-Za-z_]\w*)")
CLASS = re.compile(r"^(?:final\s+)?class\s+(\w+)\s*:")
USE = re.compile(r"\bself\.([A-Za-z_]\w*)")


def classes(text):
    """Every class in the file, as (name, first line, body lines)."""
    lines = text.split("\n")
    found = []
    i = 0
    while i < len(lines):
        head = CLASS.match(lines[i])
        if not head:
            i += 1
            continue
        depth = lines[i].count("{") - lines[i].count("}")
        body = []
        j = i + 1
        while j < len(lines) and depth > 0:
            body.append((j + 1, lines[j]))
            depth += lines[j].count("{") - lines[j].count("}")
            j += 1
        found.append((head.group(1), i + 1, body))
        i = j
    return found


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "app/Sources/main.swift"
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    wrong = []
    seen = 0
    for name, at, body in classes(text):
        seen += 1
        has = set()
        for _, line in body:
            found = DECL.match(line)
            if found:
                has.add(found.group(1))
        for number, line in body:
            if line.lstrip().startswith("//"):
                continue
            for used in USE.findall(line):
                if used in has or used in INHERITED:
                    continue
                wrong.append("%s:%d: %s has no member '%s'" %
                             (path, number, name, used))

    if wrong:
        for one in wrong:
            print(one)
        return 1
    print("%d classes read, every self.x is a member of the class writing it"
          % seen)
    return 0


if __name__ == "__main__":
    sys.exit(main())

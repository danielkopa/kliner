//
//  app/Sources/Overview.swift — the pieces the overview is drawn from
//
//  Kliner's own drawing vocabulary, the one the site uses: corner brackets
//  instead of boxes, and charts told apart by texture instead of by hue. A
//  breakdown in five colours is a chart to be decoded. The same breakdown in
//  five hatches is read in the order it is drawn, and it survives being
//  printed, screenshotted, or looked at by somebody who cannot tell red from
//  green.
//

import AppKit
import Foundation
import QuartzCore

// MARK: - texture, which is how one thing is told from the next

enum Weave {
    case diagonal, back, dots, bars, rows, grid, dense, sparse

    /// In the order a breakdown wants them: the first is the boldest, and
    /// each one after is plainly a different texture rather than a shade.
    static let order: [Weave] = [.diagonal, .back, .dots, .bars, .grid, .rows, .dense, .sparse]

    static func at(_ i: Int) -> Weave { order[i % order.count] }

    /// Draw this texture inside whatever is currently clipped.
    func draw(in rect: NSRect, colour: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        // addClip, not setClip. setClip *replaces* the clip, so a texture
        // drawn inside a wedge threw the wedge away and filled the square —
        // which is why the ring came out as a block of dots.
        NSBezierPath(rect: rect).addClip()
        colour.setStroke()
        colour.setFill()

        let path = NSBezierPath()
        switch self {
        case .diagonal, .back, .dense:
            path.lineWidth = self == .dense ? 1.6 : 1.3
            let step: CGFloat = self == .dense ? 3.2 : 5
            let back = (self == .back)
            var x = rect.minX - rect.height
            while x < rect.maxX + rect.height {
                path.move(to: NSPoint(x: back ? x + rect.height : x, y: rect.minY))
                path.line(to: NSPoint(x: back ? x : x + rect.height, y: rect.maxY))
                x += step
            }
            path.stroke()

        case .bars:
            path.lineWidth = 1.8
            var x = rect.minX + 1.5
            while x < rect.maxX {
                path.move(to: NSPoint(x: x, y: rect.minY))
                path.line(to: NSPoint(x: x, y: rect.maxY))
                x += 5.5
            }
            path.stroke()

        case .rows:
            path.lineWidth = 1.5
            var y = rect.minY + 1.5
            while y < rect.maxY {
                path.move(to: NSPoint(x: rect.minX, y: y))
                path.line(to: NSPoint(x: rect.maxX, y: y))
                y += 5
            }
            path.stroke()

        case .grid:
            path.lineWidth = 1
            var x = rect.minX + 2
            while x < rect.maxX { path.move(to: NSPoint(x: x, y: rect.minY))
                                  path.line(to: NSPoint(x: x, y: rect.maxY)); x += 5 }
            var y = rect.minY + 2
            while y < rect.maxY { path.move(to: NSPoint(x: rect.minX, y: y))
                                  path.line(to: NSPoint(x: rect.maxX, y: y)); y += 5 }
            path.stroke()

        case .dots, .sparse:
            let step: CGFloat = self == .dots ? 4.5 : 7
            let r: CGFloat = self == .dots ? 1.1 : 1
            var y = rect.minY + step / 2
            while y < rect.maxY {
                var x = rect.minX + step / 2
                while x < rect.maxX {
                    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r,
                                                width: r * 2, height: r * 2)).fill()
                    x += step
                }
                y += step
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A small square of one texture: the mark beside a row, and the swatch
/// beside a slice. The same picture in both places is what makes the legend
/// a legend rather than a second list of names.
final class Swatch: NSView {
    private let weave: Weave
    private let side: CGFloat

    init(_ weave: Weave, side: CGFloat = 22) {
        self.weave = weave
        self.side = side
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.weave.draw(in: self.bounds.insetBy(dx: 1, dy: 1),
                            colour: Paint.ink.withAlphaComponent(0.85))
        }
    }
}

// MARK: - a frame that is four corners, not a box

/// A frame of four corner brackets.
///
/// A box says "this is a container". Four corners say "look here" and leave
/// the page open behind them, which is why every panel can be framed without
/// the page filling up with edges. It was a filled card for one round, drawn
/// to a different reference; this is the one Kliner is for, and the site
/// frames things this way too.
final class Framed: NSView {
    private let inset: CGFloat

    init(_ content: NSView, inset: CGFloat = 26) {
        self.inset = inset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let arm: CGFloat = 14
            let r = self.bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath()
            path.lineWidth = 1

            path.move(to: NSPoint(x: r.minX, y: r.minY + arm))
            path.line(to: NSPoint(x: r.minX, y: r.minY))
            path.line(to: NSPoint(x: r.minX + arm, y: r.minY))

            path.move(to: NSPoint(x: r.maxX - arm, y: r.minY))
            path.line(to: NSPoint(x: r.maxX, y: r.minY))
            path.line(to: NSPoint(x: r.maxX, y: r.minY + arm))

            path.move(to: NSPoint(x: r.minX, y: r.maxY - arm))
            path.line(to: NSPoint(x: r.minX, y: r.maxY))
            path.line(to: NSPoint(x: r.minX + arm, y: r.maxY))

            path.move(to: NSPoint(x: r.maxX - arm, y: r.maxY))
            path.line(to: NSPoint(x: r.maxX, y: r.maxY))
            path.line(to: NSPoint(x: r.maxX, y: r.maxY - arm))

            Paint.ink.withAlphaComponent(0.30).setStroke()
            path.stroke()
        }
    }
}

// MARK: - a pill

/// A fact that belongs beside something rather than in it: how old a reading
/// is, whether a mode is on, what a row is besides its name and its size.
/// Clickable when it is given something to do, and plainly not when it is not.
final class Pill: NSView {
    var onClick: (() -> Void)?

    private var strong: Bool
    private let label = NSTextField(labelWithString: "")
    private var hovering = false

    init(_ text: String, strong: Bool = false) {
        self.strong = strong
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        label.stringValue = text
        label.font = Words.small
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    func set(_ text: String) { label.stringValue = text }

    /// Whether whatever this pill stands for is on.
    func lit(_ yes: Bool) {
        guard strong != yes else { return }
        strong = yes
        paint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard onClick != nil else { return }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  paint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; paint() }
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard onClick != nil else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    private func paint() {
        layer?.cornerRadius = 13
        label.textColor = strong ? Paint.onAccent : Paint.muted
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.strong
                ? Paint.accent.cgColor
                : Paint.ink.withAlphaComponent(self.hovering ? 0.12 : 0.07).cgColor
        }
    }
}

// MARK: - the ring

/// A breakdown as one ring, each slice a different texture.
///
/// Five hues is a chart to be decoded — you read the legend, then the ring,
/// then the legend again. Five textures are read in the order they are drawn,
/// and the swatch beside the name is the same picture as the slice, so the
/// legend is a legend rather than a second list of names.
final class Ring: NSView {
    private let slices: [(name: String, size: Double)]
    private let side: CGFloat

    init(_ slices: [(name: String, size: Double)], side: CGFloat = 190) {
        self.slices = slices
        self.side = side
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        let whole = slices.reduce(0) { $0 + $1.size }
        guard whole > 0 else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let middle = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
            let outer = self.side / 2 - 2
            let inner = outer * 0.56
            var from: CGFloat = 90          // twelve o'clock, going clockwise

            for (i, slice) in self.slices.enumerated() {
                let sweep = CGFloat(slice.size / whole) * 360
                guard sweep > 0.2 else { continue }
                let to = from - sweep

                let wedge = NSBezierPath()
                wedge.appendArc(withCenter: middle, radius: outer,
                                startAngle: from, endAngle: to, clockwise: true)
                wedge.appendArc(withCenter: middle, radius: inner,
                                startAngle: to, endAngle: from, clockwise: false)
                wedge.close()

                NSGraphicsContext.saveGraphicsState()
                wedge.setClip()
                Weave.at(i).draw(in: self.bounds, colour: Paint.band(i))
                NSGraphicsContext.restoreGraphicsState()

                // A hairline between slices, so two textures that happen to
                // run the same way still read as two slices.
                Paint.veil.setStroke()
                wedge.lineWidth = 2
                wedge.stroke()

                from = to
            }
        }
    }
}

// MARK: - the funnel

/// What was read, what is worth touching, what actually gets deleted.
///
/// Three numbers in a row is a row of numbers. The same three as one shape
/// narrowing left to right says the thing the numbers are for: almost none of
/// what Kliner looks at is ever thrown away.
final class Funnel: NSView {
    private let stops: [(value: Double, name: String)]

    /// Whether the numbers are sizes or counts. Without this the disk read
    /// "228 000 000 000", three readings ran into each other, and the row
    /// under the shape was unreadable.
    init(_ stops: [(value: Double, name: String)], bytes: Bool = false) {
        self.stops = stops
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 176).isActive = true

        // The readings sit under the shape, each under the point it belongs
        // to, so the eye drops straight from the taper to the number.
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        for stop in stops {
            let one = NSStackView()
            one.orientation = .vertical
            one.alignment = .centerX
            one.spacing = 3

            let big = NSTextField(labelWithString: bytes ? size(stop.value)
                                                          : whole(stop.value))
            big.font = Words.head
            big.alignment = .center
            big.lineBreakMode = .byTruncatingTail
            big.textColor = Paint.ink
            one.addArrangedSubview(big)

            let name = NSTextField(labelWithString: stop.name)
            name.font = Words.small
            name.textColor = Paint.faint
            name.alignment = .center
            name.lineBreakMode = .byTruncatingTail
            one.addArrangedSubview(name)

            row.addArrangedSubview(one)
        }

        // What is left by each stop, as a share of what went in, sitting on
        // the shape rather than under it. The shape says a lot goes and the
        // number says how much — one is no use without the other.
        let marks = NSStackView()
        marks.orientation = .horizontal
        marks.distribution = .fillEqually
        marks.alignment = .centerY
        marks.spacing = 0
        marks.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marks)

        let first = stops.first?.value ?? 0
        for stop in stops {
            let cell = NSStackView()
            cell.orientation = .horizontal
            cell.alignment = .centerY
            cell.addArrangedSubview(stretch())
            let share = first > 0 ? stop.value / first * 100 : 0
            cell.addArrangedSubview(Pill(String(Int(share.rounded())) + "%",
                                         strong: stop.value == first))
            cell.addArrangedSubview(stretch())
            marks.addArrangedSubview(cell)
        }

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 42),

            marks.leadingAnchor.constraint(equalTo: leadingAnchor),
            marks.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The shape is drawn from y 52 for 112 points in a view 176 tall,
            // so its middle is 68 down from the top; half a pill above that
            // puts the pills through the middle of the band.
            marks.topAnchor.constraint(equalTo: topAnchor, constant: 55),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        guard stops.count > 1, let top = stops.map({ $0.value }).max(), top > 0 else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let room = NSRect(x: 0, y: 52, width: self.bounds.width, height: 112)
            let legs = self.stops.count - 1
            let span = room.width / CGFloat(legs)

            for leg in 0 ..< legs {
                let a = CGFloat(self.stops[leg].value / top)
                let b = CGFloat(self.stops[leg + 1].value / top)
                let x0 = room.minX + span * CGFloat(leg)

                let band = NSBezierPath()
                let steps = 48
                // top edge left to right, bottom edge back again
                for s in 0 ... steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let h = (a + (b - a) * self.ease(t)) * room.height
                    let p = NSPoint(x: x0 + span * t, y: room.midY + h / 2)
                    s == 0 ? band.move(to: p) : band.line(to: p)
                }
                for s in stride(from: steps, through: 0, by: -1) {
                    let t = CGFloat(s) / CGFloat(steps)
                    let h = (a + (b - a) * self.ease(t)) * room.height
                    band.line(to: NSPoint(x: x0 + span * t, y: room.midY - h / 2))
                }
                band.close()

                // Each leg a step quieter: the shape is already falling, and
                // the tone falling with it says the same thing twice, which
                // is what makes it read at a glance.
                Paint.band(leg).setFill()
                band.fill()
            }
        }
    }

    /// Flat, then the drop, then flat: a straight line between two stops
    /// reads as a wedge, and a wedge is a shape, not a change.
    private func ease(_ t: CGFloat) -> CGFloat {
        let x = Double(t)
        return CGFloat(x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2)
    }
}

/// A plain count with a thin space every three digits, the way nimo writes
/// them: 42 318, not 42318 and not 42,318.
func whole(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{2009}"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? String(Int(value))
}

// MARK: - the heat strip

/// One cell a month, lighter the more there is. Twelve cells say "this has
/// been piling up since spring" in the space a sentence would take to say it
/// worse.
final class Heat: NSView {
    private let values: [Double]
    private let months: [String]

    init(_ values: [Double], months: [String]) {
        self.values = values
        self.months = months
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        guard !values.isEmpty, let top = values.max(), top > 0 else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let gap: CGFloat = 3
            let n = CGFloat(self.values.count)
            let w = (self.bounds.width - gap * (n - 1)) / n

            for (i, value) in self.values.enumerated() {
                let x = (w + gap) * CGFloat(i)
                let cell = NSRect(x: x, y: 22, width: w, height: 26)
                Paint.ink.withAlphaComponent(0.14 + (value / top) * 0.80).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 7, yRadius: 7).fill()

                // Every other month named. All twelve is a crowd at this size.
                guard i % 2 == 0, i / 2 < self.months.count else { continue }
                let name = self.months[i / 2] as NSString
                name.draw(at: NSPoint(x: x, y: 2),
                          withAttributes: [.font: Words.small,
                                           .foregroundColor: Paint.faint])
            }
        }
    }
}

// MARK: - one line of the overview

/// A place Kliner can tidy: what it is called, the command it stands for,
/// what it would do in a sentence, and the two figures worth knowing before
/// you press anything.
///
/// The command is kept for the rows that use that line to say something
/// else; a row whose command is a `min` line shows nothing there.
final class Entry: NSView {
    var onDo: (() -> Void)?
    var onOpen: (() -> Void)?

    private var hovering = false

    init(weave: Weave, name: String, command: String, blurb: String,
         pill: String?, figure: String, verb: String?, strong: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let mark = Swatch(weave, side: 30)
        addSubview(mark)

        let title = NSTextField(labelWithString: name)
        title.font = Words.entry
        title.textColor = Paint.ink
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        // No commands on the rows any more. A window that teaches the tool
        // underneath it is still a window with a terminal in it, and this one
        // is not supposed to have one.
        let typed = NSTextField(labelWithString: command.hasPrefix("min ") ? "" : command)
        typed.font = Words.typed
        typed.textColor = Paint.faint
        typed.translatesAutoresizingMaskIntoConstraints = false
        addSubview(typed)

        let said = Wrapping(labelWithString: blurb)
        said.font = Words.lead
        said.textColor = Paint.muted
        said.maximumNumberOfLines = 0
        said.lineBreakMode = .byWordWrapping
        said.translatesAutoresizingMaskIntoConstraints = false
        addSubview(said)

        let amount = NSTextField(labelWithString: figure)
        amount.font = Words.lead
        amount.textColor = Paint.muted
        amount.alignment = .right
        amount.translatesAutoresizingMaskIntoConstraints = false
        addSubview(amount)

        var right: NSView = amount
        if let word = verb {
            let go = Chip(strong ? .strong : .quiet)
            go.set(word)
            go.onClick = { [weak self] in self?.onDo?() }
            go.translatesAutoresizingMaskIntoConstraints = false
            addSubview(go)
            NSLayoutConstraint.activate([
                go.trailingAnchor.constraint(equalTo: trailingAnchor),
                go.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                amount.trailingAnchor.constraint(equalTo: go.leadingAnchor, constant: -14),
            ])
            right = go
        } else {
            amount.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
        _ = right

        var badge: Pill?
        if let text = pill {
            let one = Pill(text)
            addSubview(one)
            NSLayoutConstraint.activate([
                one.trailingAnchor.constraint(equalTo: amount.leadingAnchor, constant: -14),
                one.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            ])
            badge = one
        }

        // Not `badge ?? amount`: the two sides are a Pill and an NSTextField,
        // and ?? wants one type, not the nearest thing both happen to be.
        var stops: NSView = amount
        if let one = badge { stops = one }

        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            title.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: stops.leadingAnchor,
                                            constant: -14),

            typed.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            typed.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),

            said.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            said.topAnchor.constraint(equalTo: typed.bottomAnchor, constant: 10),
            said.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            amount.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            bottomAnchor.constraint(equalTo: said.bottomAnchor, constant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard onOpen != nil else { return }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  paint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; paint() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        layer?.cornerRadius = 8
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.hovering
                ? Paint.ink.withAlphaComponent(0.035).cgColor
                : NSColor.clear.cgColor
        }
    }
}

/// A hairline the width of whatever it is put in.
func rule() -> NSView {
    let box = NSBox()
    box.boxType = .custom
    box.borderWidth = 0
    box.fillColor = Paint.line
    box.translatesAutoresizingMaskIntoConstraints = false
    box.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return box
}

/// Blank space in a row that takes whatever is left over. A plain NSView
/// hugs its content as hard as a label does, so a stack given one has no
/// reason to hand it the slack rather than stretching the words.
func stretch() -> NSView {
    let air = NSView()
    air.translatesAutoresizingMaskIntoConstraints = false
    air.setContentHuggingPriority(.init(1), for: .horizontal)
    air.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    return air
}

/// The key for the heat strip: four cells of the thing itself, faint to full.
/// A key drawn in the same marks as the chart needs no explaining; a key drawn
/// in words needs reading first.
final class Scale: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 58),
            heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let gap: CGFloat = 3
            let w = (self.bounds.width - gap * 3) / 4
            for i in 0 ..< 4 {
                Paint.ink.withAlphaComponent(0.14 + Double(i) * 0.27).setFill()
                NSBezierPath(roundedRect: NSRect(x: (w + gap) * CGFloat(i), y: 0,
                                                 width: w, height: self.bounds.height),
                             xRadius: 4, yRadius: 4).fill()
            }
        }
    }
}

// MARK: - a bar made of dashes

/// A share, drawn as a row of dashes with the first so many lit.
///
/// A solid bar beside a solid bar beside a solid bar is three solid bars, and
/// the eye has to measure them against each other. Dashes count: the lit ones
/// are a number you can read at a glance without a scale under them.
final class Dots: NSView {
    private let share: Double

    init(_ share: Double) {
        self.share = max(0, min(1, share))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let wide: CGFloat = 5, gap: CGFloat = 3
            let many = max(1, Int((self.bounds.width + gap) / (wide + gap)))
            // Round up, so any share above nothing lights at least one dash:
            // a bar that reads empty for a real number is a bar that lies.
            let lit = self.share > 0 ? max(1, Int((Double(many) * self.share).rounded(.up))) : 0
            for i in 0 ..< many {
                let x = CGFloat(i) * (wide + gap)
                Paint.ink.withAlphaComponent(i < lit ? 0.82 : 0.14).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 1.5, width: wide, height: 3),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }
}

// MARK: - which way it went

/// A figure that moved, and the direction in its own colour.
///
/// The only two coloured things in the window. A change is the one reading
/// where the direction matters more than the number, so the direction is what
/// carries the colour and the number stays the size of everything else.
final class Moved: NSView {
    init(by share: Double, saying: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let up = share >= 0
        let arrow = NSTextField(labelWithString: up ? "\u{2191}" : "\u{2193}")
        arrow.font = Words.small
        arrow.textColor = up ? Paint.worse : Paint.better
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        // Up is not good news here. More arriving than last month means the
        // pile is growing, so the arrow that points up is the red one —
        // which is the opposite of a sales chart and the right way round for
        // a tidying tool.
        let said = NSTextField(labelWithString: saying)
        said.font = Words.small
        said.textColor = Paint.muted
        said.lineBreakMode = .byTruncatingTail
        said.translatesAutoresizingMaskIntoConstraints = false
        addSubview(said)

        NSLayoutConstraint.activate([
            arrow.leadingAnchor.constraint(equalTo: leadingAnchor),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            said.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 4),
            said.trailingAnchor.constraint(equalTo: trailingAnchor),
            said.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

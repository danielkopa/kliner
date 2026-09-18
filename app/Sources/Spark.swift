//
//  app/Sources/Spark.swift — a small picture beside a row
//
//  A list of names and numbers is a table, and a table is read one line at a
//  time. The same list with a picture on every line is read at a glance:
//  which row is the big one is a shape, not a comparison of two figures.
//
//  Two shapes only, and both are drawn from numbers nimo actually has.
//  A chart invented to fill a gap is a lie in a shape people trust, so where
//  there is no figure there is no picture.
//

import AppKit
import Foundation

final class Spark: NSView {
    /// What a row is about, in the only two ways nimo knows a row.
    enum Kind {
        /// A count of things: one mark per thing, so the field is the number.
        case count(Int)
        /// A part of a whole, in bytes: a bar hatched up to its share.
        case share(Double, of: Double)
    }

    private let kind: Kind
    private let dim: Bool

    /// The most marks worth drawing. Past this the field is solid and another
    /// hundred dots say nothing a hundred and one did not.
    private static let most = 132

    init(_ kind: Kind, dim: Bool = false) {
        self.kind = kind
        self.dim = dim
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 92),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.kind {
            case .count(let n):       self.drawField(n)
            case .share(let p, let w): self.drawBar(p, w)
            }
        }
    }

    // MARK: one mark per thing

    private func drawField(_ n: Int) {
        guard n > 0 else { return }
        let shown = min(n, Spark.most)
        let cols = 22
        let rows = max(1, Int(ceil(Double(shown) / Double(cols))))
        let w = bounds.width, h = bounds.height
        let gx = w / CGFloat(cols)
        let gy = min(h / CGFloat(rows), 5.5)
        let top = (h - gy * CGFloat(rows)) / 2

        for i in 0 ..< shown {
            let cx = (CGFloat(i % cols) + 0.5) * gx
            let cy = top + (CGFloat(i / cols) + 0.5) * gy
            // A grid of perfectly even dots reads as a texture swatch. A hair
            // of drift, the same every time because it comes from the index,
            // reads as a pile of things.
            let dx = CGFloat(sin(Double(i) * 3.7)) * gx * 0.22
            let dy = CGFloat(cos(Double(i) * 2.3)) * gy * 0.18
            let r: CGFloat = 1.05
            let dot = NSBezierPath(ovalIn: NSRect(x: cx + dx - r, y: cy + dy - r,
                                                  width: r * 2, height: r * 2))
            Paint.ink.withAlphaComponent(alpha(0.34 + Double(i % 5) * 0.11)).setFill()
            dot.fill()
        }
    }

    // MARK: a share of a whole

    private func drawBar(_ part: Double, _ whole: Double) {
        guard whole > 0, part > 0 else { return }
        let share = CGFloat(min(1, max(0.012, part / whole)))
        let top = (bounds.height - 12) / 2
        let track = NSRect(x: 0, y: top, width: bounds.width, height: 12)
        let filled = NSRect(x: 0, y: top, width: bounds.width * share, height: 12)

        Paint.ink.withAlphaComponent(alpha(0.10)).setFill()
        NSBezierPath(rect: track).fill()

        // Hatched rather than solid: a solid bar beside a field of dots reads
        // as the same chart twice. Diagonals say "this is a measure of room",
        // dots say "these are things", without a word or a colour.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: filled).setClip()
        let stroke = NSBezierPath()
        stroke.lineWidth = 1.4
        var x = -track.height
        while x < filled.width + track.height {
            stroke.move(to: NSPoint(x: x, y: top + track.height))
            stroke.line(to: NSPoint(x: x + track.height, y: top))
            x += 4.5
        }
        Paint.ink.withAlphaComponent(alpha(0.8)).setStroke()
        stroke.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Everything fades together on a row that is already done.
    private func alpha(_ full: Double) -> CGFloat {
        CGFloat(dim ? full * 0.22 : full)
    }
}

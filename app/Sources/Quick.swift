//
//  app/Sources/Quick.swift — the menu bar item, and the key that opens it
//
//  Kliner has a window, and a window is a place you go. This is the other
//  half: a mark in the menu bar, and one key combination that drops a short
//  menu under it wherever you happen to be.
//
//  What it does not do is run anything. Every one of nimo's jobs moves files
//  about, and a thing that moves files on one keystroke, out of a list you
//  are half way through reading, is a thing people learn to be afraid of.
//  Choosing a line here opens that page in the window, where it says what it
//  is about to do and waits to be told yes. The menu is a way in, not a
//  trigger.
//

import AppKit
import Foundation
import QuartzCore
import Carbon

// MARK: - the key combination

/// The one place the keys are written down.
///
/// ⌘K is what it ships as, because that is the key every command palette
/// answers to now. It is registered *system wide*, which is the point and
/// also the cost: while Kliner is running, ⌘K belongs to Kliner, and the
/// apps that wanted it — a browser's address bar, Slack's channel jump —
/// stop getting it.
///
/// If that turns out to be the wrong trade, this is a one-line change.
/// `optionKey + cmdKey` collides with nothing.
enum Combo {
    static let key: UInt32 = UInt32(kVK_ANSI_K)
    static let modifiers: UInt32 = UInt32(cmdKey)
    /// The same thing, for anybody reading the screen.
    static let written = "⌘K"
}

// MARK: - a key macOS hands over wherever you are

/// Carbon, in 2026, on purpose.
///
/// The modern way to watch for a key you do not own is a global event
/// monitor, and that needs the Accessibility permission — a trip to System
/// Settings before the app works at all — and it cannot swallow the
/// keystroke, so the app underneath gets it too. `RegisterEventHotKey` needs
/// no permission, takes the key cleanly, and is still what every launcher on
/// the Mac is built on.
final class Hotkey {
    /// Kliner registers exactly one, so the handler does not have to ask
    /// which one was pressed. If a second ever arrives, this becomes a
    /// dictionary keyed by `EventHotKeyID.id` and the handler reads the
    /// event's direct object to find it.
    private static var fire: (() -> Void)?
    private static var listening = false

    private var ref: EventHotKeyRef?

    init?(key: UInt32, modifiers: UInt32, fire: @escaping () -> Void) {
        Hotkey.fire = fire
        Hotkey.listen()

        // 'KLNR', so nobody else's hot key is mistaken for ours.
        let name = EventHotKeyID(signature: OSType(0x4B4C4E52), id: 1)
        let made = RegisterEventHotKey(key, modifiers, name,
                                       GetApplicationEventTarget(), 0, &ref)
        guard made == noErr, ref != nil else { return nil }
    }

    deinit {
        if let ref = ref { UnregisterEventHotKey(ref) }
    }

    private static func listen() {
        guard !listening else { return }
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The block below captures nothing, which is what lets Swift hand it
        // to C as a plain function pointer.
        let ok = InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async { Hotkey.fire?() }
            return noErr
        }, 1, &kind, nil, nil)
        listening = (ok == noErr)
    }
}

// MARK: - one line in the menu

/// A picture, a name, and the command it stands for, greyed at the end of the
/// line. The row you are on is filled; nothing else is.
final class QuickRow: NSView {
    let index: Int
    var onRun: ((Int) -> Void)?
    var onPoint: ((QuickRow) -> Void)?

    /// Every row is this tall. The menu works its own height out rather than
    /// measuring, so this is the one place the number lives.
    static let tall: CGFloat = 34

    private var lit = false
    private let tile = NSView()
    private let mark = NSImageView()
    private let figure = NSTextField(labelWithString: "")

    init(index: Int, title: String, command: String, figure said: String, symbol: String) {
        self.index = index
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        // No tile behind the glyph any more: on a list this short it was one
        // more box to read. The lit row is the only thing that draws itself.
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 6
        tile.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tile)

        if let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            mark.image = picture
        }
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        let name = NSTextField(labelWithString: title)
        name.font = Words.strong
        name.textColor = Paint.ink
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        // One line: the name, and nothing under it. The command a row stands
        // for is still what the search matches, it is just not printed.

        // The figure only shows on the row you are on. Nine of them down the
        // right edge is a second column to read; one, where you are looking,
        // is the answer to "how many".
        figure.stringValue = said
        figure.alphaValue = 0
        figure.font = Words.small
        figure.textColor = Paint.muted
        figure.alignment = .right
        figure.lineBreakMode = .byTruncatingHead
        figure.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        figure.translatesAutoresizingMaskIntoConstraints = false
        addSubview(figure)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: QuickRow.tall),

            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 20),
            tile.heightAnchor.constraint(equalToConstant: 20),

            mark.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: tile.centerYAnchor),

            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 11),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: figure.leadingAnchor, constant: -12),

            figure.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            figure.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    /// The whole row is the button. The labels inside it are not.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways,
                                                 .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onPoint?(self) }
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { onRun?(index) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    func light(_ on: Bool) {
        guard lit != on else { return }
        lit = on
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.lit ? Paint.picked.cgColor : NSColor.clear.cgColor
            self.tile.layer?.backgroundColor = NSColor.clear.cgColor
            self.mark.contentTintColor = self.lit ? Paint.ink : Paint.muted
            self.figure.textColor = Paint.muted
            self.figure.animator().alphaValue = self.lit ? 1 : 0
        }
    }
}

/// The small word over a run of rows. Places, then the things that do
/// something, then the places you can go: a list of ten with no headings is
/// ten things to read, and with them it is three.
final class QuickGroup: NSView {
    static let tall: CGFloat = 20

    init(_ words: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "")
        name.attributedStringValue = NSAttributedString(
            string: words.uppercased(),
            attributes: [.font: Words.label, .foregroundColor: Paint.muted, .kern: 0.8])
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: QuickGroup.tall),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

// MARK: - the panel itself

/// A borderless panel that can take the keyboard without the app having to
/// steal the whole screen first.
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - the menu

final class Quick: NSObject, NSTextFieldDelegate {
    static let shared = Quick()

    /// Handed a page number; the window shows it. Set by the app delegate,
    /// because the menu knows nothing about the window.
    var onOpenPage: ((Int) -> Void)?

    /// What the window read last time it looked, so the menu can say it too.
    ///
    /// The point of a key you can press anywhere is that you do not have to
    /// go anywhere. A menu that only lists page names makes you open the
    /// window to learn anything; with the figures on it, ⌘K answers the
    /// question by itself and you open the window only to act.
    var headline: String?
    var figures: [Int: String] = [:]

    private var status: NSStatusItem?
    private var hotkey: Hotkey?

    private var panel: MenuPanel?
    private var field: NSTextField?
    private var list: NSStackView?
    private var listHeight: NSLayoutConstraint?

    private var foot: NSTextField?
    private var footHeight: NSLayoutConstraint?
    /// One width for the panel, so nothing is 520 in two places.
    static let wide: CGFloat = 480
    private var rows: [QuickRow] = []
    /// How many headings are in the list. The menu works its own height out
    /// rather than measuring it, so it has to know.
    private var heads = 0
    private var sel = 0
    /// Whether Kliner had a window on the screen before the menu opened. If
    /// it did not, closing the menu hands the screen back to whatever you
    /// were doing rather than leaving an empty app in front.
    private var borrowed = false

    private struct Entry {
        let index: Int
        let group: String
        let title: String
        let hint: String
        let symbol: String
    }

    // MARK: starting

    func start() {
        let bar = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = bar.button {
            let mark = NSImage(named: "mascot")
            mark?.isTemplate = true
            mark?.size = NSSize(width: 18, height: 18)
            button.image = mark
            button.target = self
            button.action = #selector(tapped)
            button.toolTip = "Kliner  \(Combo.written)"
        }
        status = bar

        hotkey = Hotkey(key: Combo.key, modifiers: Combo.modifiers) { [weak self] in
            self?.toggle()
        }
    }

    /// Whether macOS gave us the key. Something else may already hold it,
    /// in which case the mark in the menu bar is the whole of the way in.
    var hotkeyWorks: Bool { hotkey != nil }

    @objc private func tapped() { toggle() }

    // MARK: opening and shutting

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = make()
        // If Kliner was not the app in front, the menu is borrowing the
        // screen and has to give it back when it closes.
        borrowed = !NSApp.isActive

        field?.stringValue = ""
        foot?.stringValue = tail()
        footHeight?.constant = tail().isEmpty ? 0 : 15
        fill("")
        place()

        panel.alphaValue = 0
        // Activate first, order second. The other way round, activating makes
        // some other window of ours key, the panel resigns key the instant it
        // appears, and the thing shuts itself.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            // Give the screen back to whatever was in front.
            if self.borrowed { NSApp.hide(nil) }
        })
    }

    // MARK: building it once

    private func make() -> MenuPanel {
        if let panel = panel { return panel }

        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: Quick.wide, height: 240),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none

        // Kliner's own card, the colour of the window, not glass: glass takes
        // its colour from whatever wallpaper is behind it.
        let blur = Surface(Paint.card, round: 12, edged: true)
        blur.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = blur

        let ask = NSTextField()
        ask.font = Words.ask
        ask.textColor = Paint.ink
        ask.placeholderString = "Search Kliner"
        ask.isBordered = false
        ask.drawsBackground = false
        ask.focusRingType = .none
        ask.delegate = self
        ask.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(ask)
        field = ask

        let hair = Surface(Paint.line)
        blur.addSubview(hair)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        list = stack

        let foot = NSTextField(labelWithString: self.tail())
        foot.font = Words.small
        foot.textColor = Paint.faint
        foot.lineBreakMode = .byTruncatingTail
        foot.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(foot)
        self.foot = foot

        let height = stack.heightAnchor.constraint(equalToConstant: 34)
        listHeight = height
        let tall = foot.heightAnchor.constraint(equalToConstant: self.tail().isEmpty ? 0 : 15)
        footHeight = tall

        NSLayoutConstraint.activate([
            ask.topAnchor.constraint(equalTo: blur.topAnchor, constant: 13),
            ask.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
            ask.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -14),
            // Said out loud, because the panel's height is worked out below
            // rather than measured, and a guess would leave a gap.
            ask.heightAnchor.constraint(equalToConstant: 20),

            hair.topAnchor.constraint(equalTo: ask.bottomAnchor, constant: 11),
            hair.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hair.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hair.heightAnchor.constraint(equalToConstant: 1),

            stack.topAnchor.constraint(equalTo: hair.bottomAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -8),
            height,

            foot.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            foot.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
            foot.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -14),
            tall,
        ])

        // Clicking anywhere else puts it away, the way a menu does.
        NotificationCenter.default.addObserver(self, selector: #selector(slipped),
                                               name: NSWindow.didResignKeyNotification,
                                               object: panel)

        self.panel = panel
        return panel
    }

    @objc private func slipped() { hide() }

    /// The line along the bottom: what the window last read, then the keys.
    private func tail() -> String {
        // Only what Home last read. The keys used to be printed here too;
        // ⌘space does not explain itself either, and the line was the
        // widest thing in the panel.
        guard let said = headline, !said.isEmpty else { return "" }
        return said
    }

    // MARK: what is in it

    private var entries: [Entry] {
        // The headings are the window's own: "Your desk", "Your screen", and
        // the rest, exactly as they read down the side. Somebody who has used
        // the window once already knows where a row will be.
        var out = Action.all.enumerated().map { pair -> Entry in
            let item = pair.element
            return Entry(index: pair.offset,
                         group: item.group.isEmpty ? "Kliner" : item.group,
                         title: item.title,
                         hint: item.arguments.isEmpty
                               ? "" : "min " + item.arguments.joined(separator: " "),
                         symbol: item.symbol)
        }
        // Activity is a page the window draws itself, after Settings and Help.
        out.append(Entry(index: Action.all.count + 2, group: "Your computer", title: "Activity",
                         hint: "CPU memory apps processes", symbol: "cpu"))
        out.append(Entry(index: Quick.monitor, group: "Your computer", title: "Activity Monitor",
                         hint: "Apple's own app", symbol: "gauge"))
        out.append(Entry(index: Quick.closeApps, group: "Your computer", title: "Close all apps",
                         hint: "quit everything that is open", symbol: "xmark.circle"))
        out.append(Entry(index: Action.all.count, group: "Kliner", title: "Settings",
                         hint: "Permissions and preferences", symbol: "gearshape"))

        // Rows of one heading together, headings in the order they first
        // appear, and inside a heading the order the window already uses.
        // Kliner's own two pages go last: pressing the key is how you reach
        // somewhere on your Mac, and Home is where you already are.
        var order: [String: Int] = [:]
        for entry in out where order[entry.group] == nil {
            order[entry.group] = order.count
        }
        func rank(_ group: String) -> Int {
            group == "Kliner" ? 99 : (order[group] ?? 0)
        }
        return out.sorted { a, b in
            let one = rank(a.group), two = rank(b.group)
            return one == two ? a.index < b.index : one < two
        }
    }

    /// Letters in order, anywhere in the word: "dsk" finds Desktop, "clnup"
    /// finds Clean up. What every launcher does, and what people type.
    private static func loose(_ text: String, _ want: String) -> Bool {
        var at = text.startIndex
        for letter in want {
            guard at < text.endIndex, let found = text[at...].firstIndex(of: letter) else { return false }
            at = text.index(after: found)
        }
        return true
    }

    /// How well a row answers what was typed. Nought means it does not.
    private func score(_ entry: Entry, _ want: String) -> Int {
        let title = entry.title.lowercased()
        if title == want { return 1000 }
        if title.hasPrefix(want) { return 900 - title.count }
        if title.contains(want) { return 700 - title.count }
        if Quick.loose(title, want) { return 500 - title.count }
        if entry.hint.lowercased().contains(want) { return 300 }
        if entry.index < Action.all.count,
           Action.all[entry.index].blurb.lowercased().contains(want) { return 200 }
        return 0
    }

    private func matching(_ typed: String) -> [Entry] {
        let want = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all: [Entry] = entries
        guard !want.isEmpty else { return Array(all.prefix(12)) }
        // Written out instead of chained. The chained version reads better
        // and swiftc gives up on it: "unable to type-check this expression
        // in reasonable time". A loop compiles in no time and does the same.
        var hits: [(entry: Entry, mark: Int)] = []
        for entry in all {
            let mark: Int = score(entry, want)
            if mark > 0 { hits.append((entry: entry, mark: mark)) }
        }
        hits.sort { (a: (entry: Entry, mark: Int), b: (entry: Entry, mark: Int)) -> Bool in
            if a.mark != b.mark { return a.mark > b.mark }
            return a.entry.index < b.entry.index
        }
        var out: [Entry] = []
        for hit in hits.prefix(9) { out.append(hit.entry) }
        return out
    }

    private func fill(_ typed: String) {
        guard let stack = list else { return }
        // Everything, not just the rows: the "nothing matches" line is in
        // here too, and a list that only forgets its rows keeps that line for
        // ever underneath the next search.
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows = []

        let hits = matching(typed)
        var seen = ""
        heads = 0
        for entry in hits {
            if entry.group != seen {
                seen = entry.group
                let head = QuickGroup(entry.group)
                stack.addArrangedSubview(head)
                head.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                heads += 1
            }
            // The figure the window last read, when it has one.
            let row = QuickRow(index: entry.index,
                               title: entry.title,
                               command: entry.hint,
                               figure: figures[entry.index] ?? "",
                               symbol: entry.symbol)
            row.onRun = { [weak self] index in self?.run(index) }
            row.onPoint = { [weak self] row in self?.point(to: row) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            rows.append(row)
        }

        if hits.isEmpty {
            let empty = NSTextField(labelWithString: "No results")
            empty.font = Words.body
            empty.textColor = Paint.faint
            empty.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 38).isActive = true
            empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let count = max(1, rows.count)
        listHeight?.constant = CGFloat(count) * QuickRow.tall + CGFloat(count - 1) * 2
            + CGFloat(heads) * (QuickGroup.tall + 2)

        sel = 0
        for (i, row) in rows.enumerated() { row.light(i == sel) }

        resize()
    }

    private func point(to row: QuickRow) {
        guard let where_ = rows.firstIndex(of: row) else { return }
        sel = where_
        for (i, one) in rows.enumerated() { one.light(i == sel) }
    }

    private func step(_ by: Int) {
        guard !rows.isEmpty else { return }
        sel = (sel + by + rows.count) % rows.count
        for (i, row) in rows.enumerated() { row.light(i == sel) }
    }

    /// Not pages: Apple's Activity Monitor, and every open app asked to quit.
    static let monitor = 10_000
    static let closeApps = 10_001

    private func run(_ index: Int) {
        if index == Quick.monitor {
            borrowed = false
            hide()
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if index == Quick.closeApps {
            borrowed = false
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                Web.closeEverything(on: nil) { _ in }
            }
            return
        }
        // Before hiding, not after: the fade's completion reads this, and the
        // window is about to come forward, so nothing should be given back.
        borrowed = false
        hide()
        // And after the menu is out of the way: a window rising under a panel
        // that is still fading is two things moving at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.onOpenPage?(index)
        }
    }

    // MARK: where it sits

    private func resize() {
        guard let panel = panel else { return }
        // 13 above the line you type in, 20 for the line itself, 11 down to
        // the hairline, the hairline, 6, the rows, then the footer if there
        // is one, and 12 below.
        let count = max(1, rows.count)
        let said: CGFloat = tail().isEmpty ? 0 : 8 + 15
        let height: CGFloat = 13 + 20 + 11 + 1 + 6
            + CGFloat(count) * QuickRow.tall + CGFloat(count - 1) * 2
            + CGFloat(heads) * (QuickGroup.tall + 2)
            + said + 10
        panel.setContentSize(NSSize(width: Quick.wide, height: height))
        place()
    }

    private func place() {
        guard let panel = panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.main ?? status?.button?.window?.screen
        guard let room = screen?.visibleFrame else { return }

        // Where ⌘space puts its own: the middle of the screen, high up, so
        // the list grows downwards into empty space rather than moving.
        var x = room.midX - size.width / 2
        var y = room.maxY - size.height - room.height * 0.16

        x = min(max(room.minX + 8, x), room.maxX - size.width - 8)
        y = max(room.minY + 8, y)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: the keyboard

    func controlTextDidChange(_ notification: Notification) {
        fill(field?.stringValue ?? "")
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            step(1); return true
        case #selector(NSResponder.moveUp(_:)):
            step(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            if sel < rows.count { run(rows[sel].index) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(); return true
        default:
            return false
        }
    }
}

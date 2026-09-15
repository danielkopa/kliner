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
import Carbon.HIToolbox

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

    private var lit = false

    init(index: Int, title: String, hint: String, symbol: String) {
        self.index = index
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        let picture = NSImageView()
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            picture.image = image
        }
        picture.contentTintColor = Paint.muted
        picture.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picture)

        let name = NSTextField(labelWithString: title)
        name.font = Words.body
        name.textColor = Paint.ink
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        let command = NSTextField(labelWithString: hint)
        command.font = Words.small
        command.textColor = Paint.faint
        command.alignment = .right
        command.lineBreakMode = .byTruncatingHead
        command.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        command.translatesAutoresizingMaskIntoConstraints = false
        addSubview(command)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),

            picture.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            picture.centerYAnchor.constraint(equalTo: centerYAnchor),
            picture.widthAnchor.constraint(equalToConstant: 16),
            picture.heightAnchor.constraint(equalToConstant: 16),

            name.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),

            command.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 12),
            command.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            command.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    /// The whole row is the button. The label inside it is not.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onPoint?(self) }
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
        }
    }
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

    private var status: NSStatusItem?
    private var hotkey: Hotkey?

    private var panel: MenuPanel?
    private var field: NSTextField?
    private var list: NSStackView?
    private var listHeight: NSLayoutConstraint?

    private var rows: [QuickRow] = []
    private var sel = 0
    /// Whether Kliner had a window on the screen before the menu opened. If
    /// it did not, closing the menu hands the screen back to whatever you
    /// were doing rather than leaving an empty app in front.
    private var borrowed = false

    private struct Entry {
        let index: Int
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
            button.toolTip = "Kliner — \(Combo.written)"
        }
        status = bar

        hotkey = Hotkey(key: Combo.key, modifiers: Combo.modifiers) { [weak self] in
            self?.toggle()
        }
    }

    /// Whether the key was taken. The window says so in Settings if it was
    /// not, rather than leaving somebody pressing a key that does nothing.
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

        let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        let ask = NSTextField()
        ask.font = Words.ask
        ask.textColor = Paint.ink
        ask.placeholderString = "What would you like tidied?"
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

        let foot = NSTextField(labelWithString:
            "↑↓ choose · ⏎ open · esc close · \(Combo.written) anywhere")
        foot.font = Words.small
        foot.textColor = Paint.faint
        foot.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(foot)

        let height = stack.heightAnchor.constraint(equalToConstant: 38)
        listHeight = height

        NSLayoutConstraint.activate([
            ask.topAnchor.constraint(equalTo: blur.topAnchor, constant: 13),
            ask.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            ask.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            // Said out loud, because the panel's height is worked out below
            // rather than measured, and a guess would leave a gap.
            ask.heightAnchor.constraint(equalToConstant: 22),

            hair.topAnchor.constraint(equalTo: ask.bottomAnchor, constant: 12),
            hair.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hair.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hair.heightAnchor.constraint(equalToConstant: 1),

            stack.topAnchor.constraint(equalTo: hair.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -8),
            height,

            foot.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 9),
            foot.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            foot.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            foot.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Clicking anywhere else puts it away, the way a menu does.
        NotificationCenter.default.addObserver(self, selector: #selector(slipped),
                                               name: NSWindow.didResignKeyNotification,
                                               object: panel)

        self.panel = panel
        return panel
    }

    @objc private func slipped() { hide() }

    // MARK: what is in it

    private var entries: [Entry] {
        var out = Action.all.enumerated().map { pair in
            Entry(index: pair.offset,
                  title: pair.element.title,
                  hint: pair.element.arguments.isEmpty
                        ? "" : "min " + pair.element.arguments.joined(separator: " "),
                  symbol: pair.element.symbol)
        }
        out.append(Entry(index: Action.all.count, title: "Settings",
                         hint: "", symbol: "gearshape"))
        return out
    }

    private func matching(_ typed: String) -> [Entry] {
        let want = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = entries
        guard !want.isEmpty else { return Array(all.prefix(6)) }
        let hits = all.filter { entry in
            entry.title.lowercased().contains(want)
                || entry.hint.lowercased().contains(want)
                || (entry.index < Action.all.count
                    && Action.all[entry.index].blurb.lowercased().contains(want))
        }
        return Array(hits.prefix(6))
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
        for entry in hits {
            let row = QuickRow(index: entry.index, title: entry.title,
                               hint: entry.hint, symbol: entry.symbol)
            row.onRun = { [weak self] index in self?.run(index) }
            row.onPoint = { [weak self] row in self?.point(to: row) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            rows.append(row)
        }

        if hits.isEmpty {
            let empty = NSTextField(labelWithString: "Nothing here goes by that name.")
            empty.font = Words.body
            empty.textColor = Paint.faint
            empty.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 38).isActive = true
            empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let count = max(1, rows.count)
        listHeight?.constant = CGFloat(count) * 38 + CGFloat(count - 1) * 2

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

    private func run(_ index: Int) {
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
        // 13 above the line you type in, 22 for the line itself, 12 down to
        // the hairline, the hairline, 8, the rows, 9, the footer, 12 below.
        let count = max(1, rows.count)
        let height: CGFloat = 13 + 22 + 12 + 1 + 8
            + CGFloat(count) * 38 + CGFloat(count - 1) * 2
            + 9 + 16 + 12
        panel.setContentSize(NSSize(width: 460, height: height))
        place()
    }

    private func place() {
        guard let panel = panel else { return }
        let size = panel.frame.size
        let screen = status?.button?.window?.screen ?? NSScreen.main
        guard let room = screen?.visibleFrame else { return }

        var x = room.midX - size.width / 2
        var y = room.maxY - size.height - 6

        if let button = status?.button, let window = button.window {
            let seat = window.convertToScreen(button.convert(button.bounds, to: nil))
            x = seat.midX - size.width / 2
            y = seat.minY - size.height - 6
        }

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

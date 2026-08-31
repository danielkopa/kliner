//
//  nimo — make your workspace clean.
//
//  A normal Mac application: an icon in the Dock, a window you open, a list
//  of the things nimo does down the side, and what nimo said in the middle.
//
//  The whole of nimo is a bash program that has been argued with for a long
//  time: it asks before it changes anything, it writes down what it did, and
//  "Put it all back" reverses it. None of that is reimplemented here. This is
//  the window on it — it runs the same `min`, carried inside the app.
//
//  Built with swiftc from the command line tools; there is no Xcode project,
//  because a project file is one more thing to drift.

import AppKit
import Foundation
import ServiceManagement

// MARK: - nimo's colours

enum Paint {
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: 1)
    }

    /// One colour that is two colours: macOS asks it which one when it draws,
    /// so the window follows the system without the app watching for it.
    static func pair(_ day: NSColor, _ night: NSColor) -> NSColor {
        NSColor(name: nil) { look in
            look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? night : day
        }
    }

    // Paper and ink, and three greys between them. No accent anywhere: the
    // only strong thing in the window is one button, and it is ink.
    static let ground = pair(rgb(250, 250, 250), rgb(13, 15, 15))
    static let line   = pair(rgb(232, 232, 233), rgb(30, 33, 33))
    static let hover  = pair(rgb(243, 243, 244), rgb(22, 25, 25))
    static let picked = pair(rgb(236, 236, 238), rgb(29, 33, 33))

    static let ink    = pair(rgb(17, 17, 19),    rgb(238, 240, 240))
    static let body   = pair(rgb(38, 38, 42),    rgb(206, 210, 210))
    static let muted  = pair(rgb(112, 112, 120), rgb(136, 143, 143))
    static let faint  = pair(rgb(156, 156, 164), rgb(104, 111, 111))
}

// MARK: - running nimo

/// One command, and what came back from it.
struct Outcome {
    let ok: Bool
    let text: String
}

enum Nimo {
    /// `min` lives inside the app, so the app is one thing you can move,
    /// delete, or hand to somebody.
    static var executable: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("nimo", isDirectory: true)
            .appendingPathComponent("min")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Runs `min` and waits. Call it off the main thread — some of these walk
    /// your whole home folder, and a window that freezes is a broken one.
    static func run(_ arguments: [String]) -> Outcome {
        guard let min = executable,
              FileManager.default.fileExists(atPath: min.path) else {
            return Outcome(ok: false, text: """
              nimo could not find its own copy of min.

              The app was unpacked incompletely. Move the whole Nimo app —
              not a piece of it — into Applications.
            """)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        // --color, not --no-color: nimo draws in colour, and throwing that
        // away is what makes a window look like a dumped log.
        task.arguments = [min.path] + arguments + ["--color", "--no-animation"]
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // nimo refuses to change anything without a terminal unless it is
        // told yes — which is what the dialog before this is for. Its stdin
        // is nothing at all, so nothing can wait for an answer a window
        // could never give.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "NO_COLOR")
        env["COLUMNS"] = "76"
        env["NIMO_FROM_APP"] = "1"
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return Outcome(ok: false, text: "nimo could not start: \(error.localizedDescription)")
        }

        // Read first, wait second: the other way round fills the pipe and
        // both sides stop for ever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return Outcome(ok: task.terminationStatus == 0,
                       text: String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - what the app can do

struct Action {
    let title: String        // what it is called down the side
    let blurb: String        // one line, at the top of its page
    let verb: String         // what the button says
    let arguments: [String]
    let asks: String?        // the question, or nil when it changes nothing
    let group: String        // the heading it sits under
    let symbol: String       // the small picture beside it


    static let all: [Action] = [
        Action(title: "Desktop",
               blurb: "Everything on your desktop, sorted into Desktop/Tidy by what it is. Nothing is deleted, and nothing is renamed.",
               verb: "Clear my desktop",
               arguments: ["desktop"],
               asks: "Move everything on your desktop into Desktop/Tidy, sorted by what it is?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk",
               symbol: "square.grid.2x2"),

        Action(title: "Downloads",
               blurb: "The same, for the folder everything lands in and nothing ever leaves.",
               verb: "Sort my downloads",
               arguments: ["downloads"],
               asks: "Sort your downloads into Downloads/Tidy?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk",
               symbol: "arrow.down.circle"),

        Action(title: "Screenshots",
               blurb: "Every loose screenshot gathered into Pictures/Screenshots, wherever it was dropped.",
               verb: "Gather them up",
               arguments: ["screenshots"],
               asks: "Gather every loose screenshot into Pictures/Screenshots?",
               group: "Your desk",
               symbol: "camera"),

        Action(title: "Wallpaper",
               blurb: "Step through the wallpapers your Mac already ships with. Nothing is downloaded.",
               verb: "Next wallpaper",
               arguments: ["next"],
               asks: nil,
               group: "Your screen",
               symbol: "photo"),

        Action(title: "Startup",
               blurb: "What launches itself when you sign in — and which of them nimo can turn off.",
               verb: "Look",
               arguments: ["startup", "--list"],
               asks: nil,
               group: "Your screen",
               symbol: "power"),

        Action(title: "What is big",
               blurb: "The folders in your home that are taking up the room, largest first.",
               verb: "Measure",
               arguments: ["top"],
               asks: nil,
               group: "Your disk",
               symbol: "chart.bar"),

        Action(title: "Free up space",
               blurb: "Caches and temporary files your apps rebuild by themselves. Your own files are never touched.",
               verb: "Free it up",
               arguments: ["clean"],
               asks: "Delete the caches and temporary files nimo found?\n\nThis one frees real space. Your own files are never touched.",
               group: "Your disk",
               symbol: "sparkles"),

        Action(title: "How it is",
               blurb: "Disk, memory, uptime, battery — how your computer is doing right now.",
               verb: "Check",
               arguments: ["doctor"],
               asks: nil,
               group: "Your computer",
               symbol: "waveform.path.ecg"),

        Action(title: "Put it all back",
               blurb: "Everything nimo has done, reversed, newest first. This is why nothing here is frightening.",
               verb: "Put it all back",
               arguments: ["undo", "--all"],
               asks: "Reverse everything nimo has done, newest first?",
               group: "Your computer",
               symbol: "arrow.uturn.backward"),
    ]
}

// MARK: - reading nimo back

/// A line of nimo's output, once somebody has worked out what it is.
enum Piece {
    case heading(String)                                     // ╭─ your desktop ──
    case rule                                                // the line above a total
    case row(String, String, String, Double?, Bool)          // label, value, note, bar, strong
    case good(String)
    case warn(String)
    case note(String)                                        // the dim lines at the end
    case text(String)
}

/// nimo draws a panel in a terminal, with box corners and columns held apart
/// by spaces. In a window that is somebody else's furniture: this reads the
/// panel back into what it always meant — a heading, some rows, a total, and
/// a few notes — and the window builds those out of real controls.
///
/// It reads nimo's own output rather than a second machine-readable format,
/// because a format that only the app uses is a format that goes stale.
enum Report {
    static let box = Set("─╭╮╰╯│")

    static func plain(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    /// Splits on two or more spaces, which is how nimo holds its columns apart.
    static func columns(_ text: String) -> [String] {
        text.replacingOccurrences(of: " {2,}", with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .filter { !$0.isEmpty }
    }

    static func parse(_ raw: String) -> [Piece] {
        var pieces: [Piece] = []

        for line in raw.components(separatedBy: "\n") {
            let strong = line.contains("\u{1B}[1m")
            let bare = plain(line)
            let t = bare.trimmingCharacters(in: .whitespaces)

            if t.isEmpty { continue }
            if t.hasPrefix("◍") { continue }          // the wordmark; the window has a title
            if t.hasPrefix("╰") { continue }          // the bottom of a panel is a shape, not a fact

            if t.hasPrefix("╭") {
                var title = t
                while let c = title.first, box.contains(c) || c == " " { title.removeFirst() }
                while let c = title.last,  box.contains(c) || c == " " { title.removeLast() }
                if !title.isEmpty { pieces.append(.heading(title)) }
                continue
            }

            if t.allSatisfy({ box.contains($0) }) {
                pieces.append(.rule)
                continue
            }

            if t.hasPrefix("✓") {
                pieces.append(.good(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if t.hasPrefix("✗") || t.hasPrefix("!") {
                pieces.append(.warn(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            let indent = bare.count - bare.drop(while: { $0 == " " }).count
            var parts = columns(t)

            if indent >= 4 && parts.count >= 2 {
                let label = parts.removeFirst()

                // A run of blocks and dots is a picture of a proportion, and a
                // window can draw that properly instead of spelling it.
                var bar: Double?
                if let last = parts.last, !last.isEmpty,
                   last.allSatisfy({ $0 == "█" || $0 == "·" }) {
                    bar = Double(last.filter { $0 == "█" }.count) / Double(last.count)
                    parts.removeLast()
                }

                let value = parts.first ?? ""
                let note = parts.count > 1 ? parts.dropFirst().joined(separator: "  ") : ""
                pieces.append(.row(label, value, note, bar, strong))
                continue
            }

            if indent <= 3 {
                pieces.append(.note(t))
            } else {
                pieces.append(.text(t))
            }
        }

        return pieces
    }
}

// MARK: - text that knows how wide it is

/// An NSTextField will not work out its own height from a width unless it is
/// told what the width turned out to be. This tells it.
final class Wrapping: NSTextField {
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            super.layout()
        }
    }
}

// MARK: - starting itself

/// An app you have to open by hand every morning is an app you stop using.
/// macOS 13 has one honest way to ask; older ones do not, and nimo says so
/// rather than writing a plist behind your back.
enum Login {
    static var possible: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var on: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    /// Returns what went wrong, or nil when it worked.
    static func set(_ wanted: Bool) -> String? {
        guard #available(macOS 13.0, *) else {
            return "Opening at login needs macOS 13 or newer."
        }
        do {
            if wanted { try SMAppService.mainApp.register() }
            else      { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - a row down the side

/// A name, and under it three quiet words saying what it is. No box, no
/// border — just a soft fill when it is the one you are on.
final class Row: NSView {
    let index: Int
    var onClick: ((Int) -> Void)?

    private let name = NSTextField(labelWithString: "")
    private var chosen = false
    private var hovering = false

    init(_ item: Action, index: Int) {
        self.index = index
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        name.stringValue = item.title
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        repaint()
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()      // a layer colour does not follow the system by itself
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { onClick?(index) }

    func choose(_ yes: Bool) { chosen = yes; repaint() }

    private func repaint() {
        name.textColor = chosen ? Paint.ink : Paint.muted
        name.font = NSFont.systemFont(ofSize: 13.5, weight: chosen ? .medium : .regular)

        var background = NSColor.clear
        if chosen { background = Paint.picked } else if hovering { background = Paint.hover }
        // .cgColor answers for whichever appearance is current, so ask under
        // this view's own.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = background.cgColor
        }
    }
}

/// The one button. Ink, a soft round end, and nothing else on the page
/// competing with it.
final class Pill: NSButton {
    private var live = true

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 16
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    func set(_ words: String, live able: Bool) {
        live = able
        isEnabled = able
        let text = NSMutableAttributedString(string: "  " + words + "  ")
        text.addAttributes([
            .foregroundColor: able ? Paint.ground : Paint.faint,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        ], range: NSRange(location: 0, length: text.length))
        attributedTitle = text
        repaint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        let colour = live ? Paint.ink : Paint.picked
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = colour.cgColor
        }
    }
}

// MARK: - the window

final class Main: NSObject, NSWindowDelegate {
    let window: NSWindow

    private let titleLabel = NSTextField(labelWithString: "")
    private let blurbLabel = Wrapping(labelWithString: "")
    private var runButton: Pill!
    private let spinner    = NSProgressIndicator()
    private let scroll     = NSScrollView()
    private let report     = NSStackView()
    private var rows: [Row] = []

    private var chosen = 0
    private var busy = false
    private var seen: Set<Int> = []

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        super.init()

        window.title = "nimo"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Paint.ground
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 480)
        window.delegate = self
        _ = window.setFrameAutosaveName("nimo.main")

        build()
        show(0)
        window.center()
    }

    // MARK: building it

    private func build() {
        guard let content = window.contentView else { return }

        // ---- down the side ----------------------------------------------
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let mark = NSTextField(labelWithString: "nimo")
        mark.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        mark.textColor = Paint.ink
        stack.addArrangedSubview(mark)
        stack.setCustomSpacing(26, after: mark)

        for (i, item) in Action.all.enumerated() {
            let row = Row(item, index: i)
            row.onClick = { [weak self] which in self?.show(which) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 190).isActive = true
            rows.append(row)
        }

        // ---- the page ----------------------------------------------------
        // No card, no second surface, no border round anything. One hairline
        // between the list and the work, and paper either side of it.
        let edge = NSBox()
        edge.boxType = .custom
        edge.borderWidth = 0
        edge.fillColor = Paint.line
        edge.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(edge)

        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = Paint.ink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        blurbLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        blurbLabel.textColor = Paint.muted
        blurbLabel.maximumNumberOfLines = 3
        blurbLabel.lineBreakMode = .byWordWrapping
        blurbLabel.preferredMaxLayoutWidth = 460
        blurbLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(blurbLabel)

        runButton = Pill(target: self, action: #selector(go))
        content.addSubview(runButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(spinner)

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        report.orientation = .vertical
        report.alignment = .leading
        report.spacing = 0
        report.edgeInsets = NSEdgeInsets(top: 4, left: 46, bottom: 40, right: 46)
        report.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = report

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 48),
            stack.widthAnchor.constraint(equalToConstant: 214),

            edge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 246),
            edge.topAnchor.constraint(equalTo: content.topAnchor),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            titleLabel.leadingAnchor.constraint(equalTo: edge.trailingAnchor, constant: 46),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -46),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),

            blurbLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            blurbLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -60),
            blurbLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            runButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            runButton.topAnchor.constraint(equalTo: blurbLabel.bottomAnchor, constant: 24),

            spinner.leadingAnchor.constraint(equalTo: runButton.trailingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            scroll.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 34),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            report.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            report.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            report.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
    }

    // MARK: drawing what nimo said

    private func line(_ view: NSView, inset: CGFloat = 92) {
        view.translatesAutoresizingMaskIntoConstraints = false
        report.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: report.widthAnchor, constant: -inset).isActive = true
    }

    private func words(_ text: String, size: CGFloat, weight: NSFont.Weight,
                       colour: NSColor, top: CGFloat, bottom: CGFloat) {
        let field = Wrapping(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = colour
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            field.topAnchor.constraint(equalTo: holder.topAnchor, constant: top),
            field.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -bottom),
        ])
        line(holder)
    }

    private func draw(_ pieces: [Piece]) {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for piece in pieces {
            switch piece {
            case .heading(let text):
                words(text, size: 12, weight: .medium, colour: Paint.faint, top: 26, bottom: 8)

            case .rule:
                // A rule was a way of drawing a gap on a terminal. Here a gap
                // is a gap.
                let air = NSView()
                air.translatesAutoresizingMaskIntoConstraints = false
                air.heightAnchor.constraint(equalToConstant: 14).isActive = true
                line(air)

            case .row(let label, let value, _, _, let strong):
                // The trailing half of a row is nimo telling a terminal what
                // to type next. There is a button here instead.
                line(Said(label: label, value: value, strong: strong))

            case .good(let text):
                words(text, size: 14, weight: .semibold, colour: Paint.ink, top: 8, bottom: 6)

            case .warn(let text):
                words(text, size: 14, weight: .medium, colour: Paint.body, top: 8, bottom: 6)

            case .note:
                // nimo's last lines tell a terminal what to type next. There
                // is nothing to type here, so they are not shown.
                break

            case .text(let text):
                words(text, size: 13.5, weight: .regular, colour: Paint.body, top: 5, bottom: 5)
            }
        }

        // A panel that appears is easier to read than one swapped underneath you.
        scroll.alphaValue = 0
        report.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            scroll.animator().alphaValue = 1
        }
    }

    private func say(_ text: String) {
        draw([.text(text)])
    }

    // MARK: using it

    private func show(_ index: Int) {
        guard index >= 0, index < Action.all.count else { return }
        chosen = index
        let item = Action.all[index]

        for (i, row) in rows.enumerated() { row.choose(i == index) }

        titleLabel.stringValue = item.title
        blurbLabel.stringValue = item.blurb
        runButton.set(item.verb, live: !busy)

        if seen.contains(index) { return }

        // Open a page and it fills in by itself. The ones that only look just
        // look; the ones that would change something show you what they would
        // change and touch nothing — nimo's own --dry-run, which is the same
        // measurement the real run uses.
        run(item, preview: item.asks != nil)
    }

    @objc private func go() {
        let item = Action.all[chosen]

        if let question = item.asks {
            let alert = NSAlert()
            alert.messageText = item.verb
            alert.informativeText = question
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Do it")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        run(item)
    }

    private func run(_ item: Action, preview: Bool = false) {
        guard !busy else { return }
        busy = true
        seen.insert(chosen)
        runButton.set(item.verb, live: false)
        spinner.startAnimation(nil)
        say("working …")

        // Only after somebody has said yes does --yes go anywhere near nimo,
        // and a preview cannot be given it at all.
        let arguments: [String]
        if preview {
            arguments = item.arguments + ["--dry-run"]
        } else {
            arguments = item.asks == nil ? item.arguments : item.arguments + ["--yes"]
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                let pieces = Report.parse(result.text)
                if pieces.isEmpty { self.say("nimo said nothing at all.") }
                else { self.draw(pieces) }
                self.spinner.stopAnimation(nil)
                self.busy = false
                self.runButton.set(Action.all[self.chosen].verb, live: true)
            }
        }
    }

    /// Closing the window puts nimo away; the Dock icon brings it back. It is
    /// not a document, so there is nothing to lose by closing it.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

// MARK: - one thing nimo said

/// A name, and what it came to. Two pieces of text on one line, the second one
/// starting at the same place every time so the eye can run down them — no
/// rules, no dots, no columns drawn round them.
final class Said: NSView {
    init(label: String, value: String, strong: Bool) {
        super.init(frame: .zero)

        let left = NSTextField(labelWithString: label)
        left.font = NSFont.systemFont(ofSize: 13.5, weight: strong ? .medium : .regular)
        left.textColor = Paint.muted
        left.lineBreakMode = .byTruncatingTail
        left.translatesAutoresizingMaskIntoConstraints = false
        addSubview(left)

        let right = Wrapping(labelWithString: value)
        right.font = NSFont.systemFont(ofSize: 13.5, weight: strong ? .semibold : .regular)
        right.textColor = Paint.ink
        right.maximumNumberOfLines = 0
        right.lineBreakMode = .byWordWrapping
        right.translatesAutoresizingMaskIntoConstraints = false
        addSubview(right)

        translatesAutoresizingMaskIntoConstraints = false
        let column = left.widthAnchor.constraint(equalToConstant: 168)
        column.priority = .defaultHigh

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            column,
            right.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 180),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            right.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            left.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - the app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var main: Main!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        main = Main()
        main.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { main?.window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: the menu bar along the top

    private func buildMenu() -> NSMenu {
        let bar = NSMenu()

        let appHolder = NSMenuItem()
        bar.addItem(appHolder)
        let app = NSMenu()
        let about = NSMenuItem(title: "About nimo",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        app.addItem(about)

        app.addItem(.separator())
        let login = NSMenuItem(title: "Open nimo at login",
                               action: #selector(toggleLogin(_:)),
                               keyEquivalent: "")
        login.target = self
        login.state = Login.on ? .on : .off
        login.isEnabled = Login.possible
        app.addItem(login)

        app.addItem(.separator())
        let terminal = NSMenuItem(title: "Open nimo in Terminal…",
                                  action: #selector(openInTerminal), keyEquivalent: "")
        terminal.target = self
        app.addItem(terminal)

        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide nimo",
                               action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: "Quit nimo",
                               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appHolder.submenu = app

        let editHolder = NSMenuItem()
        bar.addItem(editHolder)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Copy",
                                action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Select All",
                                action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editHolder.submenu = edit

        let windowHolder = NSMenuItem()
        bar.addItem(windowHolder)
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Minimise",
                                  action: #selector(NSWindow.performMiniaturize(_:)),
                                  keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Close",
                                  action: #selector(NSWindow.performClose(_:)),
                                  keyEquivalent: "w"))
        windowHolder.submenu = window
        NSApp.windowsMenu = window

        return bar
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        if let trouble = Login.set(sender.state != .on) {
            let alert = NSAlert()
            alert.messageText = "nimo could not change that"
            alert.informativeText = trouble
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        // Ask macOS what it actually is now, rather than assuming it worked.
        sender.state = Login.on ? .on : .off
    }

    @objc private func openInTerminal() {
        guard let min = Nimo.executable else { return }
        // One quote is the only thing that can go wrong in a path, so it is
        // the one thing worth escaping.
        let quoted = min.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
        activate
        do script "'\(quoted)'"
        end tell
        """
        if let apple = NSAppleScript(source: script) {
            var trouble: NSDictionary?
            apple.executeAndReturnError(&trouble)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "nimo \(Nimo.version)"
        alert.informativeText = """
        make your workspace clean

        Everything in this window is the same nimo you can run in a terminal, \
        and everything it changes it writes down first — "Put it all back" \
        reverses the lot.

        It never touches anything outside your home folder, never asks for an \
        administrator, and never uses the network.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open the website")
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://danielkopa.github.io/nimo/") {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// A normal app: an icon in the Dock, and a window when you open it.
_ = application.setActivationPolicy(.regular)
application.run()

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

    static let ground    = rgb(11, 13, 14)
    static let side      = rgb(14, 17, 19)
    static let line      = rgb(29, 34, 37)
    static let raised    = rgb(19, 23, 25)
    static let ink       = rgb(236, 239, 241)
    static let body      = rgb(212, 219, 222)
    static let muted     = rgb(154, 164, 171)
    static let faint     = rgb(106, 118, 121)
    static let accent    = rgb(95, 211, 198)
    static let onAccent  = rgb(4, 33, 30)
    static let warm      = rgb(217, 186, 116)
    static let hot       = rgb(224, 115, 106)
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

    static let all: [Action] = [
        Action(title: "Desktop",
               blurb: "Everything on your desktop, sorted into Desktop/Tidy by what it is. Nothing is deleted, and nothing is renamed.",
               verb: "Clear my desktop",
               arguments: ["desktop"],
               asks: "Move everything on your desktop into Desktop/Tidy, sorted by what it is?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk"),

        Action(title: "Downloads",
               blurb: "The same, for the folder everything lands in and nothing ever leaves.",
               verb: "Sort my downloads",
               arguments: ["downloads"],
               asks: "Sort your downloads into Downloads/Tidy?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk"),

        Action(title: "Screenshots",
               blurb: "Every loose screenshot gathered into Pictures/Screenshots, wherever it was dropped.",
               verb: "Gather them up",
               arguments: ["screenshots"],
               asks: "Gather every loose screenshot into Pictures/Screenshots?",
               group: "Your desk"),

        Action(title: "Wallpaper",
               blurb: "Step through the wallpapers your Mac already ships with. Nothing is downloaded.",
               verb: "Next wallpaper",
               arguments: ["next"],
               asks: nil,
               group: "Your screen"),

        Action(title: "Startup",
               blurb: "What launches itself when you sign in — and which of them nimo can turn off.",
               verb: "Look",
               arguments: ["startup", "--list"],
               asks: nil,
               group: "Your screen"),

        Action(title: "What is big",
               blurb: "The folders in your home that are taking up the room, largest first.",
               verb: "Measure",
               arguments: ["top"],
               asks: nil,
               group: "Your disk"),

        Action(title: "What could go",
               blurb: "Caches and temporary files your apps rebuild by themselves. This only looks — it cannot change anything at all.",
               verb: "Have a look",
               arguments: ["preview"],
               asks: nil,
               group: "Your disk"),

        Action(title: "Free it up",
               blurb: "The same list, actually removed. Your own files are never touched.",
               verb: "Free it up",
               arguments: ["clean"],
               asks: "Delete the caches and temporary files nimo found?\n\nThis one frees real space. Your own files are never touched.",
               group: "Your disk"),

        Action(title: "How it is",
               blurb: "Disk, memory, uptime, battery — how your computer is doing right now.",
               verb: "Check",
               arguments: ["doctor"],
               asks: nil,
               group: "Your computer"),

        Action(title: "Put it all back",
               blurb: "Everything nimo has done, reversed, newest first. This is why nothing here is frightening.",
               verb: "Put it all back",
               arguments: ["undo", "--all"],
               asks: "Reverse everything nimo has done, newest first?",
               group: "Your computer"),
    ]
}

// MARK: - reading nimo back

/// nimo says things in seven escape codes and nothing else — reset, bold,
/// dim, green, yellow, red, cyan. This turns them into a drawn panel, so the
/// window shows nimo's own colours rather than a log with the colour lost.
enum Screen {
    static func render(_ text: String, size: CGFloat) -> NSAttributedString {
        let plain = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let heavy = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)

        let out = NSMutableAttributedString()
        var colour = Paint.body
        var bold = false
        var piece = ""

        func flush() {
            if piece.isEmpty { return }
            out.append(NSAttributedString(string: piece, attributes: [
                .foregroundColor: colour,
                .font: bold ? heavy : plain,
            ]))
            piece = ""
        }

        func apply(_ code: String) {
            // "1;36" is two instructions, and an empty one means reset
            let parts = code.isEmpty ? [""] : code.components(separatedBy: ";")
            for part in parts {
                switch part {
                case "", "0":  colour = Paint.body;  bold = false
                case "1":      colour = Paint.ink;   bold = true
                case "2":      colour = Paint.faint
                case "31":     colour = Paint.hot
                case "32":     colour = Paint.accent   // nimo's yes is cyan
                case "33":     colour = Paint.warm
                case "36":     colour = Paint.accent
                default:       break
                }
            }
        }

        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\u{1B}" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "[" {
                    var j = text.index(after: next)
                    var code = ""
                    while j < text.endIndex, text[j] != "m", code.count < 16 {
                        code.append(text[j])
                        j = text.index(after: j)
                    }
                    if j < text.endIndex, text[j] == "m" {
                        flush()
                        apply(code)
                        i = text.index(after: j)
                        continue
                    }
                }
            }
            piece.append(text[i])
            i = text.index(after: i)
        }
        flush()
        return out
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

final class Row: NSButton {
    let index: Int

    init(action item: Action, index: Int, target: AnyObject, selector: Selector) {
        self.index = index
        super.init(frame: .zero)

        self.title = item.title
        self.target = target
        self.action = selector
        self.tag = index
        self.isBordered = false
        self.alignment = .left
        self.wantsLayer = true
        self.layer?.cornerRadius = 7
        self.contentTintColor = Paint.muted
        self.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        self.translatesAutoresizingMaskIntoConstraints = false
        paint(selected: false)
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    func paint(selected: Bool) {
        let text = NSMutableAttributedString(string: title)
        text.addAttributes([
            .foregroundColor: selected ? Paint.onAccent : Paint.muted,
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular),
        ], range: NSRange(location: 0, length: text.length))
        self.attributedTitle = text
        self.layer?.backgroundColor = selected ? Paint.accent.cgColor : NSColor.clear.cgColor
    }
}

// MARK: - the window

final class Main: NSObject, NSWindowDelegate {
    let window: NSWindow

    private let titleLabel = NSTextField(labelWithString: "")
    private let blurbLabel = NSTextField(labelWithString: "")
    private let runButton  = NSButton(title: "", target: nil, action: nil)
    private let console    = NSTextView()
    private var rows: [Row] = []

    private var chosen = 0
    private var busy = false
    private var seen: Set<Int> = []

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        super.init()

        window.title = "nimo"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Paint.ground
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 820, height: 520)
        window.delegate = self
        _ = window.setFrameAutosaveName("nimo.main")

        build()
        show(0)
        window.center()
    }

    // MARK: building it

    private func build() {
        guard let content = window.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = Paint.ground.cgColor

        // ---- down the side ----------------------------------------------
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = Paint.side.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let edge = NSBox()
        edge.boxType = .custom
        edge.borderWidth = 0
        edge.fillColor = Paint.line
        edge.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(edge)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        let mark = NSTextField(labelWithString: "◍  nimo")
        mark.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        mark.textColor = Paint.accent
        stack.addArrangedSubview(mark)

        let version = NSTextField(labelWithString: Nimo.version.isEmpty
                                  ? "make your workspace clean"
                                  : "version " + Nimo.version)
        version.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        version.textColor = Paint.faint
        stack.addArrangedSubview(version)
        stack.setCustomSpacing(20, after: version)

        var lastGroup = ""
        for (i, item) in Action.all.enumerated() {
            if item.group != lastGroup {
                lastGroup = item.group
                let head = NSTextField(labelWithString: item.group.uppercased())
                head.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                head.textColor = Paint.faint
                if i > 0 { stack.setCustomSpacing(18, after: stack.arrangedSubviews.last ?? head) }
                stack.addArrangedSubview(head)
                stack.setCustomSpacing(8, after: head)
            }

            let row = Row(action: item, index: i, target: self, selector: #selector(pick(_:)))
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalToConstant: 216),
                row.heightAnchor.constraint(equalToConstant: 30),
            ])
            rows.append(row)
        }

        // ---- the page ----------------------------------------------------
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = Paint.ink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        blurbLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        blurbLabel.textColor = Paint.muted
        blurbLabel.maximumNumberOfLines = 3
        blurbLabel.lineBreakMode = .byWordWrapping
        blurbLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(blurbLabel)

        runButton.bezelStyle = .rounded
        runButton.controlSize = .large
        runButton.bezelColor = Paint.accent
        runButton.target = self
        runButton.action = #selector(go)
        runButton.keyEquivalent = "\r"
        runButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(runButton)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Paint.raised
        scroll.scrollerKnobStyle = .light
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 11
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = Paint.line.cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        console.isEditable = false
        console.isSelectable = true
        console.drawsBackground = false
        console.textContainerInset = NSSize(width: 20, height: 18)
        console.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        console.textColor = Paint.body
        console.isHorizontallyResizable = true
        console.isVerticallyResizable = true
        console.autoresizingMask = [.width, .height]
        console.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
        // nimo draws in a fixed-width panel. Reflowing it to the window puts
        // every box corner in the wrong place, so it scrolls sideways instead.
        console.textContainer?.widthTracksTextView = false
        console.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                      height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = console

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 240),

            edge.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            edge.topAnchor.constraint(equalTo: content.topAnchor),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: edge.trailingAnchor, constant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),

            blurbLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            blurbLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -60),
            blurbLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            runButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            runButton.topAnchor.constraint(equalTo: blurbLabel.bottomAnchor, constant: 18),
            runButton.heightAnchor.constraint(equalToConstant: 34),

            scroll.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            scroll.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26),
        ])
    }

    // MARK: using it

    @objc private func pick(_ sender: NSButton) {
        show(sender.tag)
    }

    private func show(_ index: Int) {
        guard index >= 0, index < Action.all.count else { return }
        chosen = index
        let item = Action.all[index]

        for (i, row) in rows.enumerated() { row.paint(selected: i == index) }

        titleLabel.stringValue = item.title
        blurbLabel.stringValue = item.blurb
        setButton(title: item.verb, enabled: !busy)

        if seen.contains(index) { return }

        // Anything that only looks can just look — you should not have to ask
        // a program to tell you how much room you have left.
        if item.asks == nil {
            run(item)
        } else {
            put("\n  \u{1B}[2mnimo will show you exactly what it did, here.\u{1B}[0m\n")
        }
    }

    private func setButton(title: String, enabled: Bool) {
        let text = NSMutableAttributedString(string: title)
        text.addAttributes([
            .foregroundColor: enabled ? Paint.onAccent : Paint.faint,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ], range: NSRange(location: 0, length: text.length))
        runButton.attributedTitle = text
        runButton.isEnabled = enabled
        runButton.bezelColor = enabled ? Paint.accent : Paint.raised
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
            alert.window.appearance = NSAppearance(named: .darkAqua)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        run(item)
    }

    private func run(_ item: Action) {
        guard !busy else { return }
        busy = true
        seen.insert(chosen)
        setButton(title: item.verb, enabled: false)
        put("\n  \u{1B}[2mworking …\u{1B}[0m\n")

        // Only after somebody has said yes does --yes go anywhere near nimo.
        let arguments = item.asks == nil ? item.arguments : item.arguments + ["--yes"]

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                let body = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.put(body.isEmpty
                         ? "\n  \u{1B}[2mnimo said nothing at all.\u{1B}[0m\n"
                         : "\n" + body + "\n")
                self.busy = false
                self.setButton(title: Action.all[self.chosen].verb, enabled: true)
            }
        }
    }

    private func put(_ text: String) {
        console.textStorage?.setAttributedString(Screen.render(text, size: 12))
        console.scrollToBeginningOfDocument(nil)
    }

    /// Closing the window puts nimo away; the Dock icon brings it back. It is
    /// not a document, so there is nothing to lose by closing it.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
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

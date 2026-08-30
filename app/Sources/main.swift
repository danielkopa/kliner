//
//  nimo — a clean workspace, from the menu bar.
//
//  The whole of nimo is a bash program that has been argued with for a long
//  time: it asks before it changes anything, it writes down what it did, and
//  min undo puts it back. None of that is reimplemented here. This is the
//  window on it — a menu bar item that runs the same `min`, bundled inside
//  the app, and shows you what it said.
//
//  Built with swiftc from the command line tools; there is no Xcode project,
//  because a project file is one more thing to drift.

import AppKit
import Foundation

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

    /// Runs `min` and waits. Call it off the main thread — some of these
    /// walk your whole home folder, and a menu that freezes is a broken one.
    static func run(_ arguments: [String]) -> Outcome {
        guard let min = executable,
              FileManager.default.fileExists(atPath: min.path) else {
            return Outcome(ok: false, text: """
            nimo could not find its own copy of min.

            The app was unpacked incompletely. Download it again, and move
            the whole Nimo app — not a piece of it — into Applications.
            """)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [min.path] + arguments + ["--no-color", "--no-animation"]
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // A GUI has no terminal, and nimo refuses to change anything without
        // one unless it is told yes — which is exactly what the dialog before
        // this was for. Its stdin is nothing at all, so nothing can sit there
        // waiting for an answer that will never come.
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["COLUMNS"] = "72"
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

        let text = String(data: data, encoding: .utf8) ?? ""
        return Outcome(ok: task.terminationStatus == 0, text: text)
    }
}

// MARK: - the actions in the menu

/// A thing the menu can do.
///
/// `asks` is the difference between "look at this" and "change this": nimo
/// itself asks in a terminal, and there is no terminal here, so the app has
/// to ask in its own voice before it passes --yes on.
struct Action {
    let title: String
    let arguments: [String]
    let asks: String?      // the question, or nil when it changes nothing
    let separatorBefore: Bool

    init(_ title: String, _ arguments: [String], asks: String? = nil, rule: Bool = false) {
        self.title = title
        self.arguments = arguments
        self.asks = asks
        self.separatorBefore = rule
    }

    static let all: [Action] = [
        Action("Clear my desktop", ["desktop"],
               asks: "Move everything on your desktop into Desktop/Tidy, sorted by what it is?\n\nNothing is deleted, and nimo can put it all back."),
        Action("Sort my downloads", ["downloads"],
               asks: "Sort your downloads into Downloads/Tidy?\n\nNothing is deleted, and nimo can put it all back."),
        Action("Gather loose screenshots", ["screenshots"],
               asks: "Gather every loose screenshot into Pictures/Screenshots?"),

        Action("Next wallpaper", ["next"], rule: true),
        Action("Previous wallpaper", ["prev"]),

        Action("What starts when I sign in", ["startup", "--list"], rule: true),
        Action("What is taking up room", ["top"]),
        Action("How is my computer", ["doctor"]),
        Action("What could be freed", ["preview"]),

        Action("Free it up", ["clean"], asks:
               "Delete the caches and temporary files nimo found?\n\nThis one frees real space. Your own files are never touched.",
               rule: true),

        Action("Put it all back", ["undo", "--all"],
               asks: "Reverse everything nimo has done, newest first?", rule: true),
    ]
}

// MARK: - the window that shows what happened

/// nimo talks in a fixed-width panel, so this reads it back in one.
///
/// One window per action, reused: ask twice and you get the same window with
/// the new answer in it, not a pile of them.
final class OutputWindow {
    private static var windows: [String: OutputWindow] = [:]

    private let window: NSWindow
    private let view: NSTextView

    private init(title: String) {
        let frame = NSRect(x: 0, y: 0, width: 640, height: 470)

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let text = NSTextView(frame: frame)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 20, height: 18)
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // nimo draws in a fixed-width panel, so the text must not be reflowed
        // to the window — it scrolls sideways instead, and the panel stays a
        // panel. Without this the corners of every box end up in the wrong
        // place the moment somebody drags the window narrower.
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width, .height]
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude)
        scroll.hasHorizontalScroller = true
        scroll.documentView = text

        let w = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered,
                         defer: false)
        w.title = title
        w.contentView = scroll
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("nimo.\(title)")
        w.center()

        self.window = w
        self.view = text
    }

    private static func window(for title: String) -> OutputWindow {
        if let existing = windows[title] { return existing }
        let made = OutputWindow(title: title)
        windows[title] = made
        return made
    }

    /// Puts a window on screen straight away, so the click has an answer
    /// before nimo has finished thinking.
    static func waiting(title: String) -> OutputWindow {
        let panel = window(for: title)
        panel.view.string = "\n  working …\n"
        NSApp.activate(ignoringOtherApps: true)
        panel.window.makeKeyAndOrderFront(nil)
        return panel
    }

    func finish(with text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        view.string = body.isEmpty ? "\n  nimo said nothing at all.\n" : body
        view.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - the app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            // A template image is drawn in one colour, so it follows a light
            // or a dark menu bar without being told.
            if let icon = NSImage(named: "menubar") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.title = "◍"
            }
            button.toolTip = "nimo — make your workspace clean"
        }

        item.menu = buildMenu()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for (i, action) in Action.all.enumerated() {
            if action.separatorBefore { menu.addItem(.separator()) }

            let entry = NSMenuItem(title: action.title,
                                   action: #selector(perform(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.tag = i
            menu.addItem(entry)
        }

        menu.addItem(.separator())

        let terminal = NSMenuItem(title: "Open nimo in Terminal…",
                                  action: #selector(openInTerminal),
                                  keyEquivalent: "")
        terminal.target = self
        menu.addItem(terminal)

        let about = NSMenuItem(title: "About nimo",
                               action: #selector(showAbout),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit nimo",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        return menu
    }

    @objc private func perform(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < Action.all.count else { return }
        let action = Action.all[sender.tag]

        if busy {
            let alert = NSAlert()
            alert.messageText = "nimo is still busy"
            alert.informativeText = "One thing at a time. Wait for the window that is open to fill in."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }

        if let question = action.asks {
            let alert = NSAlert()
            alert.messageText = action.title
            alert.informativeText = question
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Do it")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        // Only after somebody has said yes does --yes go anywhere near nimo.
        let arguments = action.asks == nil
            ? action.arguments
            : action.arguments + ["--yes"]

        let panel = OutputWindow.waiting(title: action.title)
        busy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                panel.finish(with: result.text)
                self.busy = false
            }
        }
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
            var error: NSDictionary?
            apple.executeAndReturnError(&error)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "nimo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.informativeText = """
        make your workspace clean

        Everything in this menu is the same nimo you can run in a terminal, \
        and everything it changes it writes down first — "Put it all back" \
        reverses the lot.

        It never touches anything outside your home folder, never asks for an \
        administrator, and never uses the network.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open the website")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://danielkopa.github.io/nimo/") {
            NSWorkspace.shared.open(url)
        }
    }
}

// A menu bar app and nothing else: no Dock icon, no window until you ask for
// one. The same shape as every other small Mac tool that lives up there.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

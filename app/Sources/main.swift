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
import QuartzCore
import ServiceManagement

// MARK: - nimo's colours

enum Paint {
    // On glass a fixed grey is a mistake: the wallpaper is behind the text, so
    // the text has to be told by macOS what it should be. These are the system
    // colours every Mac app uses — they change with the appearance, and they
    // stay legible over whatever happens to be on the desktop.
    static let line   = NSColor.separatorColor
    static let hover  = NSColor.quaternaryLabelColor
    static let picked = NSColor.unemphasizedSelectedContentBackgroundColor

    static let ink    = NSColor.labelColor
    static let body   = NSColor.labelColor
    static let muted  = NSColor.secondaryLabelColor
    static let faint  = NSColor.tertiaryLabelColor

    /// The one button, and the words on it.
    static let strong = NSColor.labelColor
    static let onStrong = NSColor.textBackgroundColor
    static let ground = NSColor.textBackgroundColor
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

/// A second thing a page can do, beside the one big button.
struct Extra {
    let title: String
    let arguments: [String]
    let asks: String?
}

struct Action {
    let title: String        // what it is called down the side
    let blurb: String        // one line, at the top of its page
    let verb: String         // what the big button says
    let arguments: [String]
    let asks: String?        // the question, or nil when it changes nothing
    let group: String        // rows of the same group sit together
    let symbol: String       // the small picture beside it
    let extras: [Extra]      // the smaller buttons next to the big one
    let reveal: String?      // a folder this page is about, to open in Finder
    let walks: Bool          // rows on this page can be stepped into

    init(title: String, blurb: String, verb: String, arguments: [String],
         asks: String?, group: String, symbol: String,
         extras: [Extra] = [], reveal: String? = nil, walks: Bool = false) {
        self.title = title; self.blurb = blurb; self.verb = verb
        self.arguments = arguments; self.asks = asks; self.group = group
        self.symbol = symbol; self.extras = extras; self.reveal = reveal
        self.walks = walks
    }

    /// Not one of the things nimo does — the place where you say how it
    /// should do them.
    static let settings = Action(title: "Settings",
                                 blurb: "How nimo behaves, what it may touch, and where it starts from.",
                                 verb: "",
                                 arguments: [],
                                 asks: nil,
                                 group: "",
                                 symbol: "gearshape")

    /// Where the window opens. Not a thing nimo does — a look at what there
    /// is to do, so arriving somewhere calm is the first thing that happens.
    static let home = Action(title: "Home",
                             blurb: "What your Mac looks like right now. Nothing here has been changed.",
                             verb: "Look again",
                             arguments: ["doctor"],
                             asks: nil,
                             group: "",
                             symbol: "house")

    static let putBack = "Move everything back where it was?\n\nnimo wrote down every move it made, so this is exact."

    static let all: [Action] = [
        home,

        Action(title: "Desktop",
               blurb: "Everything on your desktop, sorted into Desktop/Tidy by what it is. Nothing is deleted, and nothing is renamed.",
               verb: "Clear my desktop",
               arguments: ["desktop"],
               asks: "Move everything on your desktop into Desktop/Tidy, sorted by what it is?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk",
               symbol: "square.grid.2x2",
               extras: [Extra(title: "Put this back", arguments: ["desktop", "--undo"], asks: putBack)],
               reveal: "Desktop"),

        Action(title: "Downloads",
               blurb: "The same, for the folder everything lands in and nothing ever leaves.",
               verb: "Sort my downloads",
               arguments: ["downloads"],
               asks: "Sort your downloads into Downloads/Tidy?\n\nNothing is deleted, and nimo can put it all back.",
               group: "Your desk",
               symbol: "arrow.down.circle",
               extras: [Extra(title: "Put this back", arguments: ["downloads", "--undo"], asks: putBack)],
               reveal: "Downloads"),

        Action(title: "Screenshots",
               blurb: "Every loose screenshot gathered into Pictures/Screenshots, wherever it was dropped.",
               verb: "Gather them up",
               arguments: ["screenshots"],
               asks: "Gather every loose screenshot into Pictures/Screenshots?",
               group: "Your desk",
               symbol: "camera",
               extras: [Extra(title: "Put this back", arguments: ["screenshots", "--undo"], asks: putBack)],
               reveal: "Pictures"),

        Action(title: "Wallpaper",
               blurb: "Step through the wallpapers your Mac already ships with. Nothing is downloaded.",
               verb: "Next",
               arguments: ["next"],
               asks: nil,
               group: "Your screen",
               symbol: "photo",
               extras: [Extra(title: "Previous", arguments: ["prev"], asks: nil),
                        Extra(title: "The one I had", arguments: ["wallpaper", "--restore"], asks: nil)]),

        Action(title: "Startup",
               blurb: "What launches itself when you sign in — and which of them nimo can turn off.",
               verb: "Look again",
               arguments: ["startup", "--list"],
               asks: nil,
               group: "Your screen",
               symbol: "power"),

        Action(title: "What is big",
               blurb: "The folders in your home that are taking up the room. Click one to look inside it.",
               verb: "Measure",
               arguments: ["top"],
               asks: nil,
               group: "Your disk",
               symbol: "chart.bar",
               walks: true),

        Action(title: "Free up space",
               blurb: "Caches and temporary files your apps rebuild by themselves. Your own files are never touched.",
               verb: "Free it up",
               arguments: ["clean"],
               asks: "Delete the caches and temporary files nimo found?\n\nThis one frees real space. Your own files are never touched.",
               group: "Your disk",
               symbol: "sparkles",
               extras: [Extra(title: "Only look", arguments: ["preview"], asks: nil)]),

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
               symbol: "arrow.uturn.backward",
               extras: [Extra(title: "Only look", arguments: ["undo", "--all", "--dry-run"], asks: nil)]),
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

// MARK: - what macOS will let nimo touch

/// macOS does not let an app decide what it may read; it lets a person decide,
/// once, in a prompt or in System Settings. So nimo cannot grant itself
/// anything — what it can do is ask at a moment you were expecting to be
/// asked, say plainly what is still shut, and take you to the switch.
enum Access {
    static var desktop: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
    static var downloads: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Reading a protected folder is what raises the prompt the first time, so
    /// asking and checking are the same act.
    @discardableResult
    static func may(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    /// Full Disk Access has no API to ask about. Every app finds out the same
    /// way: try to read a file only that permission opens, and see.
    static var everything: Bool {
        let locked = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return FileManager.default.isReadableFile(atPath: locked.path)
    }

    /// System Settings moved its panes between macOS versions, so try the one
    /// this machine is likely to have and fall back to the older name.
    static func settings(_ pane: String) {
        let tries = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?\(pane)",
        ]
        for spelling in tries {
            if let url = URL(string: spelling), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - what you have chosen

/// nimo keeps its settings in ~/.nimo/config as `key = value`, one to a line,
/// and reads that file rather than sourcing it. The app writes the same file,
/// leaving every line it does not recognise exactly where it was — the two of
/// them share one set of settings, not two.
enum Config {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nimo", isDirectory: true)
            .appendingPathComponent("config")
    }

    static func value(_ key: String) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") {
            let bare = line.trimmingCharacters(in: .whitespaces)
            if bare.isEmpty || bare.hasPrefix("#") { continue }
            guard let split = bare.firstIndex(of: "=") else { continue }
            let name = bare[..<split].trimmingCharacters(in: .whitespaces)
            if name == key {
                return String(bare[bare.index(after: split)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func set(_ key: String, _ value: String) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var kept: [String] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.components(separatedBy: "\n") {
                let bare = line.trimmingCharacters(in: .whitespaces)
                if let split = bare.firstIndex(of: "="), !bare.hasPrefix("#") {
                    let name = bare[..<split].trimmingCharacters(in: .whitespaces)
                    if name == key { continue }        // this one is being replaced
                }
                kept.append(line)
            }
        }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        kept.append("\(key) = \(value)")
        try? (kept.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
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

// MARK: - easing

/// A layer-backed view in AppKit has implicit animation switched off, so a
/// colour set on it snaps. This eases it instead — which is the whole
/// difference between a window that feels made and one that flickers.
func ease(_ layer: CALayer?, to colour: NSColor, over seconds: Double = 0.13) {
    guard let layer = layer else { return }
    let target = colour.cgColor
    if let from = layer.backgroundColor, from != target {
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = seconds
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "backgroundColor")
    }
    layer.backgroundColor = target
}

// MARK: - a small square button

/// No words, one picture, and a fill under the pointer. For the chrome, where
/// a pill would be shouting.
final class Ghost: NSView {
    var onClick: (() -> Void)?

    /// A way out that is not there yet is drawn, not hidden — a row of
    /// controls that moves about is harder to use than one that dims.
    var isEnabled = true {
        didSet { repaint() }
    }

    private let icon = NSImageView()
    private var hovering = false

    init(_ symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        if let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            icon.image = picture
        }
        icon.contentTintColor = Paint.muted
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { if isEnabled { onClick?() } }
    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        icon.contentTintColor = !isEnabled ? Paint.faint : (hovering ? Paint.ink : Paint.muted)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: hovering && isEnabled ? Paint.hover : NSColor.clear)
        }
    }
}

// MARK: - the wordmark, which blinks

/// The quote after the o is nimo's eyes. Every few seconds they shut for a
/// tenth of a second, which is the whole of the animation — a thing that
/// blinks is alive, and a thing that blinks twice a minute is not a
/// distraction.
final class Wordmark: NSImageView {
    private let open = NSImage(named: "wordmark")
    private let shut = NSImage(named: "wordmark-blink")
    private var pending: Timer?

    init() {
        super.init(frame: .zero)
        open?.isTemplate = true
        shut?.isTemplate = true
        image = open
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignLeft
        translatesAutoresizingMaskIntoConstraints = false
        later()
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    deinit { pending?.invalidate() }

    private func later() {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Double.random(in: 4.5...9),
                                       repeats: false) { [weak self] _ in
            self?.blink()
        }
    }

    private func blink() {
        guard window != nil else { later(); return }
        image = shut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
            self?.image = self?.open
            // now and then, twice — the way a real blink sometimes doubles
            if Bool.random() && Bool.random() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
                    self?.image = self?.shut
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.image = self?.open
                    }
                }
            }
            self?.later()
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
    private let icon = NSImageView()
    private var chosen = false
    private var hovering = false
    private var wide: NSLayoutConstraint!
    private var atLeft: NSLayoutConstraint!
    private var inMiddle: NSLayoutConstraint!

    /// Narrowed to its picture, the row is still the row: same target, same
    /// fill, same place in the list. Only the word goes.
    func narrow(_ yes: Bool) {
        name.isHidden = yes
        atLeft.isActive = !yes
        inMiddle.isActive = yes
        wide.constant = yes ? 38 : 190
        toolTip = yes ? name.stringValue : nil
    }

    init(_ item: Action, index: Int) {
        self.index = index
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        if let picture = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            icon.image = picture
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        name.stringValue = item.title
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        wide = widthAnchor.constraint(equalToConstant: 190)
        atLeft = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        inMiddle = icon.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            wide,
            atLeft,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
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
        name.font = NSFont.systemFont(ofSize: 13, weight: chosen ? .medium : .regular)
        icon.contentTintColor = chosen ? Paint.ink : Paint.faint

        var background = NSColor.clear
        if chosen { background = Paint.picked } else if hovering { background = Paint.hover }
        // .cgColor answers for whichever appearance is current, so ask under
        // this view's own.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: background)
        }
    }
}

/// A button nimo draws itself.
///
/// A borderless NSButton puts its title where its cell wants it, not where the
/// frame is, so a pill with a height of its own ends up with the words sitting
/// off centre. This one is a view with a label pinned to both centres, which
/// is the only way to be sure.
final class Chip: NSView {
    enum Kind { case strong, quiet }

    var onClick: (() -> Void)?
    /// What this button is about, when the row it sits in has a name.
    var subject = ""
    var index = 0

    private let kind: Kind
    private let label = NSTextField(labelWithString: "")
    private var width: NSLayoutConstraint!
    private var live = true
    private var hovering = false

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16

        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        width = widthAnchor.constraint(equalToConstant: 80)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            width,
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    func set(_ words: String, live able: Bool = true) {
        live = able
        label.stringValue = words
        // The pill is as wide as the words in it, plus the same air either side.
        let padding: CGFloat = kind == .strong ? 20 : 16
        width.constant = max(64, ceil(label.intrinsicContentSize.width) + padding * 2)
        repaint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { if live { onClick?() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        if live { addCursorRect(bounds, cursor: .pointingHand) }
    }

    private func repaint() {
        // The strong one is a filled pill. The quiet ones are words, and only
        // become a shape when the pointer is on them — three slabs in a row is
        // three things shouting.
        let background: NSColor
        if !live {
            background = kind == .strong ? Paint.picked : NSColor.clear
            label.textColor = Paint.faint
        } else if kind == .strong {
            background = Paint.strong
            label.textColor = Paint.onStrong
        } else {
            background = hovering ? Paint.picked : NSColor.clear
            label.textColor = hovering ? Paint.ink : Paint.muted
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: background)
            self.layer?.opacity = self.hovering && self.live && self.kind == .strong ? 0.85 : 1
        }
    }
}

// MARK: - one setting

final class Setting: NSView {
    init(_ label: String, control: NSView) {
        super.init(frame: .zero)

        let name = NSTextField(labelWithString: label)
        name.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        name.textColor = Paint.ink
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)


        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            name.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -20),
            name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - the window

final class Main: NSObject, NSWindowDelegate {
    let window: NSWindow

    private let titleLabel = NSTextField(labelWithString: "")
    private var runButton: Chip!
    private let spinner    = NSProgressIndicator()
    private let scroll     = NSScrollView()
    private let report     = NSStackView()
    private var rows: [Row] = []
    private var settingsRow: Row!
    private let buttons = NSStackView()
    private var railWidth: NSLayoutConstraint!
    private var stackWidth: NSLayoutConstraint!
    private var markWidth: NSLayoutConstraint!
    private var sideStack: NSStackView!
    private var wordmark: Wordmark!
    private var groupLabels: [NSTextField] = []
    private var narrow = false
    private var foldButton: Ghost!
    private var backButton: Ghost!
    private var onButton: Ghost!
    private var chrome: NSStackView!
    private var chromeLeading: NSLayoutConstraint!
    private var behind: [Int] = []          // pages you came from
    private var ahead: [Int] = []           // pages you came back from
    private var walked: [String] = []       // how far into your home you have clicked

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
        // Glass: the window stops painting a background of its own, and the
        // effect view underneath everything blurs whatever is behind it.
        window.isOpaque = false
        window.backgroundColor = .clear
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
        let glass = NSVisualEffectView()
        glass.material = .sidebar
        glass.blendingMode = .behindWindow
        glass.state = .followsWindowActiveState
        window.contentView = glass
        let content: NSView = glass

        // The work sits on a second, slightly denser pane. The two halves read
        // apart without a box being drawn round either.
        let pane = NSVisualEffectView()
        pane.material = .contentBackground
        pane.blendingMode = .withinWindow
        pane.state = .followsWindowActiveState
        pane.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pane)

        // ---- down the side ----------------------------------------------
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        sideStack = stack

        // The wordmark, not the word — and it blinks. A template image, so
        // macOS draws it in whatever colour the text around it is: light,
        // dark, or over a wallpaper showing through the glass.
        let mark = Wordmark()
        mark.contentTintColor = Paint.ink
        wordmark = mark
        stack.addArrangedSubview(mark)
        markWidth = mark.widthAnchor.constraint(equalToConstant: 190)
        NSLayoutConstraint.activate([
            mark.heightAnchor.constraint(equalToConstant: 16),
            markWidth,
        ])
        stack.setCustomSpacing(26, after: mark)

        var lastGroup = ""
        for (i, item) in Action.all.enumerated() {
            if item.group != lastGroup, !item.group.isEmpty {
                lastGroup = item.group
                if let above = stack.arrangedSubviews.last, i > 0 {
                    stack.setCustomSpacing(18, after: above)
                }
                let head = NSTextField(labelWithString: "  " + item.group)
                head.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
                head.textColor = Paint.faint
                groupLabels.append(head)
                stack.addArrangedSubview(head)
                stack.setCustomSpacing(6, after: head)
            }

            let row = Row(item, index: i)
            row.onClick = { [weak self] which in self?.show(which) }
            stack.addArrangedSubview(row)
            rows.append(row)
            if i == 0 { stack.setCustomSpacing(20, after: row) }
        }

        // Settings is not one of the things nimo does, so it does not stand in
        // the same list. It waits at the bottom, under a hairline, where every
        // Mac keeps its gear.
        settingsRow = Row(Action.settings, index: Action.all.count)
        settingsRow.onClick = { [weak self] _ in self?.show(Action.all.count) }
        settingsRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(settingsRow)
        rows.append(settingsRow)

        let foot = NSBox()
        foot.boxType = .custom
        foot.borderWidth = 0
        foot.fillColor = Paint.line
        foot.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(foot)
        NSLayoutConstraint.activate([
            foot.leadingAnchor.constraint(equalTo: settingsRow.leadingAnchor, constant: 11),
            foot.trailingAnchor.constraint(equalTo: settingsRow.trailingAnchor, constant: -11),
            foot.bottomAnchor.constraint(equalTo: settingsRow.topAnchor, constant: -9),
            foot.heightAnchor.constraint(equalToConstant: 1),
        ])

        // ---- the page ----------------------------------------------------
        // No card, no second surface, no border round anything. One hairline
        // between the list and the work, and paper either side of it.
        let edge = NSBox()
        edge.boxType = .custom
        edge.borderWidth = 0
        edge.fillColor = Paint.line
        edge.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(edge)

        // The chrome, where a Mac puts it: along the top, just past the three
        // lights, so the window has one row of controls and not three corners
        // of them.
        let fold = Ghost("sidebar.left")
        fold.onClick = { [weak self] in self?.foldSide() }
        fold.toolTip = "Hide the list  ⌘B"
        foldButton = fold

        let back = Ghost("chevron.left")
        back.onClick = { [weak self] in self?.goBack() }
        back.toolTip = "Back  ⌘["
        backButton = back

        let on = Ghost("chevron.right")
        on.onClick = { [weak self] in self?.goForward() }
        on.toolTip = "Forward  ⌘]"
        onButton = on

        chrome = NSStackView(views: [fold, back, on])
        chrome.orientation = .horizontal
        chrome.spacing = 2
        chrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chrome)

        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        titleLabel.textColor = Paint.ink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        runButton = Chip(.strong)
        runButton.onClick = { [weak self] in self?.go() }

        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 9
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

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

        railWidth = edge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 246)
        // Past the three lights when the list is open; past the rail when it
        // is shut, so nothing ever sits on top of anything.
        chromeLeading = chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 78)
        stackWidth = stack.widthAnchor.constraint(equalToConstant: 214)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            stackWidth,

            settingsRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                settingsRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            pane.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            pane.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pane.topAnchor.constraint(equalTo: content.topAnchor),
            pane.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            railWidth,
            edge.topAnchor.constraint(equalTo: content.topAnchor),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            chromeLeading,
            chrome.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: edge.trailingAnchor, constant: 46),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -46),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 66),

            buttons.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -44),
            buttons.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),

            spinner.leadingAnchor.constraint(equalTo: buttons.trailingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            scroll.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 34),
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

    /// Home is doctor's own reading, laid out as four figures and a short
    /// list of what is worth doing about them. Nothing new is measured for
    /// it — it is the same numbers, arranged for a person arriving.
    private func drawHome(_ pieces: [Piece]) {
        var figures: [String: String] = [:]
        for piece in pieces {
            if case .row(let label, let value, _, _, _) = piece { figures[label] = value }
        }

        // The four figures first, because they are the answer to "how is it".
        let wanted = [("Desktop", "on your desktop"), ("Downloads", "in downloads"),
                      ("Junk", "worth freeing"), ("Disk", "free")]
        let figuresRow = NSStackView()
        figuresRow.orientation = .horizontal
        figuresRow.distribution = .fillEqually
        figuresRow.alignment = .top
        figuresRow.spacing = 16
        var any = false
        for (key, caption) in wanted {
            var figure = figures[key] ?? "—"
            if key == "Disk", let space = figure.components(separatedBy: " free").first {
                figure = space
            }
            if figures[key] != nil { any = true }
            figuresRow.addArrangedSubview(Stat(figure, caption))
        }
        if any {
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            figuresRow.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(figuresRow)
            NSLayoutConstraint.activate([
                figuresRow.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                figuresRow.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                figuresRow.topAnchor.constraint(equalTo: holder.topAnchor, constant: 2),
                figuresRow.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -4),
            ])
            line(holder)
        }

        // Then the disk twice — as it is, and as it would be. Two bars answer
        // "what would this actually do" better than a sentence claiming it.
        var total = 0.0, free = 0.0
        if let disk = figures["Disk"] {
            let parts = disk.components(separatedBy: " of ")
            free = bytes(parts.first?.replacingOccurrences(of: " free", with: "") ?? "") ?? 0
            total = parts.count > 1 ? (bytes(parts[1]) ?? 0) : 0
        }
        let junk = bytes(figures["Junk"] ?? "") ?? 0

        if total > 0 {
            let used = max(0, total - free)
            let both = NSStackView()
            both.orientation = .vertical
            both.alignment = .leading
            both.spacing = 16
            both.translatesAutoresizingMaskIntoConstraints = false

            let now = Bar(caption: "Now",
                          used: used - junk, freeable: junk, total: total, lit: true)
            both.addArrangedSubview(now)

            if junk > 0 {
                let after = Bar(caption: "After freeing it up — \(figures["Junk"] ?? "") more free",
                                used: used - junk, freeable: 0, total: total, lit: false)
                both.addArrangedSubview(after)
                after.widthAnchor.constraint(equalTo: both.widthAnchor).isActive = true
            }
            now.widthAnchor.constraint(equalTo: both.widthAnchor).isActive = true

            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(both)
            NSLayoutConstraint.activate([
                both.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                both.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                both.topAnchor.constraint(equalTo: holder.topAnchor, constant: 24),
                both.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -6),
            ])
            line(holder)
        }

        // ---- what is worth doing about it ------------------------------
        words("Worth doing", size: 12, weight: .regular, colour: Paint.faint,
              top: 26, bottom: 6)

        var said = false

        if !Access.may(Access.desktop) || !Access.may(Access.downloads) {
            line(Suggest("nimo cannot see your files yet",
                         verb: "Ask for everything", strong: true) { [weak self] in
                             self?.askFromHome()
                         })
            said = true
        }

        if let count = figures["Desktop"], !count.hasPrefix("0") {
            line(Suggest("\(count) on your desktop",
                         verb: "Clear it", strong: true) { [weak self] in
                             self?.show(1)
                         })
            said = true
        }

        if let count = figures["Downloads"], !count.hasPrefix("0") {
            line(Suggest("\(count) in Downloads",
                         verb: "Sort it", strong: false) { [weak self] in
                             self?.show(2)
                         })
            said = true
        }

        if let junk = figures["Junk"], !junk.hasPrefix("0") {
            line(Suggest("\(junk) of caches",
                         verb: "Free it", strong: false) { [weak self] in
                             self?.show(7)
                         })
            said = true
        }

        if !said {
            words("Nothing needs doing. Your Mac is clear.",
                  size: 14, weight: .medium, colour: Paint.ink, top: 6, bottom: 6)
        }
    }

    /// Stopping one thing by name, which is what --only is for. nimo still
    /// asks; the dialog here is that question.
    private func stopThis(_ name: String) {
        guard !name.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Stop \(name) from starting?"
        alert.informativeText = "It is not uninstalled and nothing is deleted — it just stops launching itself when you sign in. Put it all back reverses this."
        alert.addButton(withTitle: "Stop it")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        launch(["startup", "--only", name, "--yes"])
    }

    private func askFromHome() {
        Access.may(Access.desktop)
        Access.may(Access.downloads)
        Access.may(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures"))
        Access.may(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
        seen.remove(0)
        show(0)
    }

    private func draw(_ pieces: [Piece]) {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if chosen == 0 && !isSettings {
            drawHome(pieces)
            settle()
            return
        }

        // nimo lists what it can turn off, then says "nimo only reports
        // these:" and lists the rest. Everything after that sentence belongs
        // to somebody else, so nothing after it gets a button.
        var stoppable = !isSettings && Action.all[chosen].arguments.first == "startup"

        for piece in pieces {
            if case .note(let text) = piece, text.contains("only reports") {
                stoppable = false
            }

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
                let walkable = !isSettings
                    && Action.all[chosen].walks
                    && label.hasSuffix("/")
                if stoppable, !label.isEmpty {
                    line(Suggest(label,
                                 verb: "Stop", strong: false, name: label) { [weak self] in
                                     self?.stopThis(label)
                                 })
                    break
                }
                let said = Said(label: label, value: value, strong: strong, walkable: walkable)
                if walkable {
                    let name = String(label.dropLast())
                    said.onOpen = { [weak self] in self?.walkInto(name) }
                }
                line(said)

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

        settle()
    }

    /// A page that arrives a line at a time reads better than one swapped
    /// underneath you. Eighteen milliseconds between lines is enough to feel
    /// like settling and not enough to feel like waiting; after fourteen lines
    /// the rest come in together, because nobody wants to watch a list deal
    /// itself out.
    private func settle() {
        report.layoutSubtreeIfNeeded()
        let start = CACurrentMediaTime()

        for (i, view) in report.arrangedSubviews.enumerated() {
            view.wantsLayer = true

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -7          // AppKit's y grows upward, so this falls
            rise.toValue = 0

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let both = CAAnimationGroup()
            both.animations = [rise, fade]
            both.duration = 0.28
            both.beginTime = start + Double(min(i, 14)) * 0.018
            both.fillMode = .backwards
            both.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.layer?.add(both, forKey: "arriving")
        }
    }

    private func say(_ text: String) {
        draw([.text(text)])
    }

    // MARK: using it

    private var isSettings: Bool { chosen == Action.all.count }

    @objc func goBack() {
        guard let last = behind.popLast() else { return }
        ahead.append(chosen)
        show(last, remember: false)
    }

    @objc func goForward() {
        guard let next = ahead.popLast() else { return }
        behind.append(chosen)
        show(next, remember: false)
    }

    private func showArrows() {
        backButton.isEnabled = !behind.isEmpty
        onButton.isEnabled = !ahead.isEmpty
    }

    private func show(_ index: Int, remember: Bool = true) {
        guard index >= 0, index <= Action.all.count else { return }
        if remember, index != chosen {
            behind.append(chosen)
            ahead = []
        }
        chosen = index
        walked = []
        showArrows()

        for (i, row) in rows.enumerated() { row.choose(i == index) }

        let item = index == Action.all.count ? Action.settings : Action.all[index]
        titleLabel.stringValue = index == 0 ? "Your Mac, right now" : item.title
        fitButtons()

        if isSettings {
            drawSettings()
            return
        }

        if seen.contains(index) { return }

        // Open a page and it fills in by itself. The ones that only look just
        // look; the ones that would change something show you what they would
        // change and touch nothing — nimo's own --dry-run, which is the same
        // measurement the real run uses.
        run(item, preview: item.asks != nil)
    }

    /// The big button, then whatever else this page can do. Rebuilt whenever
    /// the page changes, because what a page can do depends on where you are
    /// standing in it.
    private func fitButtons() {
        for view in buttons.arrangedSubviews {
            buttons.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !isSettings else { return }

        let item = Action.all[chosen]
        runButton.set(item.verb, live: !busy)
        buttons.addArrangedSubview(runButton)

        if !walked.isEmpty {
            buttons.addArrangedSubview(quiet("Back") { [weak self] in self?.walkUp() })
        }

        for (i, extra) in item.extras.enumerated() {
            buttons.addArrangedSubview(quiet(extra.title) { [weak self] in self?.runExtra(i) })
        }

        if item.reveal != nil {
            buttons.addArrangedSubview(quiet("Show in Finder") { [weak self] in self?.revealFolder() })
        }
    }

    private func quiet(_ words: String, _ then: @escaping () -> Void) -> Chip {
        let chip = Chip(.quiet)
        chip.set(words, live: !busy)
        chip.onClick = then
        return chip
    }

    private func runExtra(_ which: Int) {
        let item = Action.all[chosen]
        guard which >= 0, which < item.extras.count else { return }
        let extra = item.extras[which]

        if let question = extra.asks {
            let alert = NSAlert()
            alert.messageText = extra.title
            alert.informativeText = question
            alert.addButton(withTitle: "Do it")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        launch(extra.asks == nil ? extra.arguments : extra.arguments + ["--yes"])
    }

    private func revealFolder() {
        guard let folder = Action.all[chosen].reveal else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(folder)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    // MARK: walking into a folder

    private func walkUp() {
        if !walked.isEmpty { walked.removeLast() }
        walkHere()
    }

    private func walkInto(_ name: String) {
        walked.append(name)
        walkHere()
    }

    private func walkHere() {
        fitButtons()
        var arguments = ["top"]
        if !walked.isEmpty { arguments.append(walked.joined(separator: "/")) }
        launch(arguments)
    }

    // MARK: settings

    private func drawSettings() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let login = NSSwitch()
        login.state = Login.on ? .on : .off
        login.isEnabled = Login.possible
        login.target = self
        login.action = #selector(loginChanged(_:))
        line(Setting("Open nimo when I sign in", control: login))

        let days = NSPopUpButton()
        days.addItems(withTitles: ["7 days", "30 days", "90 days"])
        days.selectItem(withTitle: (Config.value("days") ?? "30") + " days")
        if days.indexOfSelectedItem < 0 { days.selectItem(withTitle: "30 days") }
        days.target = self
        days.action = #selector(daysChanged(_:))
        line(Setting("Old means older than", control: days))

        line(Setting("nimo in a terminal",
                     control: quiet("Open…") { [weak self] in self?.openTerminal() }))

        // ---- what macOS will let it touch --------------------------------
        // The row says what is true; the button does the only thing there is
        // to do about it. Neither needs a sentence under it.
        divider()

        let shut = [("Desktop", Access.may(Access.desktop)),
                    ("Downloads", Access.may(Access.downloads))].filter { !$0.1 }
        let files = shut.isEmpty
            ? "nimo can read your folders"
            : "nimo has not been let into " + shut.map { $0.0 }.joined(separator: " or ")
        line(Setting(files,
                     control: quiet(shut.isEmpty ? "Check again" : "Ask for everything") {
                         [weak self] in self?.askForEverything()
                     }))

        line(Setting(Access.everything
                        ? "Full Disk Access is on"
                        : "Full Disk Access is off — some caches stay put",
                     control: quiet(Access.everything ? "Settings" : "Turn on…") {
                         Access.settings("Privacy_AllFiles")
                     }))

        line(Setting("Changing your wallpaper",
                     control: quiet("Settings") { Access.settings("Privacy_Automation") }))

        divider()
        words("nimo \(Nimo.version) · MIT · github.com/danielkopa/nimo",
              size: 12, weight: .regular, colour: Paint.faint, top: 2, bottom: 4)

        settle()
    }

    @objc private func loginChanged(_ sender: NSSwitch) {
        if let trouble = Login.set(sender.state == .on) {
            let alert = NSAlert()
            alert.messageText = "nimo could not change that"
            alert.informativeText = trouble
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        // Ask macOS what it actually is now, rather than assuming it worked.
        sender.state = Login.on ? .on : .off
    }

    @objc private func daysChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? "30 days"
        Config.set("days", title.replacingOccurrences(of: " days", with: ""))
    }

    private func openTerminal() {
        guard let min = Nimo.executable else { return }
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

    private func go() {
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
        spin(arguments)
    }

    private func launch(_ arguments: [String]) {
        guard !busy else { return }
        busy = true
        seen.insert(chosen)
        runButton.set(Action.all[chosen].verb, live: false)
        spinner.startAnimation(nil)
        say("working …")
        spin(arguments)
    }

    private func spin(_ arguments: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                let pieces = Report.parse(result.text)
                if pieces.isEmpty { self.say("nimo said nothing at all.") }
                else { self.draw(pieces) }
                self.spinner.stopAnimation(nil)
                self.busy = false
                self.fitButtons()
            }
        }
    }

    /// The list folds down to its pictures and back. Everything stays where
    /// it was — same rows, same order, same fills — only the words go, and
    /// each row keeps its name as a tooltip so nothing is lost.
    @objc func foldSide() {
        narrow.toggle()

        for row in rows { row.narrow(narrow) }
        for head in groupLabels { head.isHidden = narrow }
        wordmark.isHidden = narrow
        markWidth.constant = narrow ? 38 : 190
        stackWidth.constant = narrow ? 38 : 214
        railWidth.constant = narrow ? 70 : 246
        chromeLeading.constant = narrow ? 92 : 78
        foldButton.toolTip = narrow ? "Show the list  ⌘B" : "Hide the list  ⌘B"

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// ⌘1 … ⌘9 for the list, ⌘, for the gear. A window you can only reach
    /// with a mouse is a window somebody has not finished.
    @objc func goByNumber(_ sender: NSMenuItem) {
        show(sender.tag)
    }

    @objc func openSettings() {
        show(Action.all.count)
    }

    /// Closing the window puts nimo away; the Dock icon brings it back. It is
    /// not a document, so there is nothing to lose by closing it.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

// MARK: - a disk, drawn

/// Sizes as nimo prints them, back into numbers, so they can be drawn.
func bytes(_ text: String) -> Double? {
    let parts = text.split(separator: " ")
    guard let first = parts.first, let value = Double(first) else { return nil }
    let unit = parts.count > 1 ? parts[1].uppercased() : "B"
    switch unit {
    case "KB": return value * 1_000
    case "MB": return value * 1_000_000
    case "GB": return value * 1_000_000_000
    case "TB": return value * 1_000_000_000_000
    default:   return value
    }
}

/// One line of disk: what is taken, the part of it nimo could give back, and
/// what is already free. Two of these — now, and after — is the honest way to
/// answer "what would this actually do".
final class Bar: NSView {
    init(caption: String, used: Double, freeable: Double, total: Double, lit: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: caption)
        title.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        title.textColor = Paint.faint
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 5
        track.layer?.masksToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)
        track.effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = Paint.line.cgColor
        }

        func slice(_ colour: NSColor) -> NSView {
            let piece = NSView()
            piece.wantsLayer = true
            piece.translatesAutoresizingMaskIntoConstraints = false
            track.addSubview(piece)
            piece.effectiveAppearance.performAsCurrentDrawingAppearance {
                piece.layer?.backgroundColor = colour.cgColor
            }
            return piece
        }

        let safeTotal = max(total, 1)
        let taken = slice(Paint.muted)
        let give  = slice(lit ? Paint.strong : Paint.line)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.topAnchor.constraint(equalTo: topAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            track.heightAnchor.constraint(equalToConstant: 10),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),

            taken.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            taken.topAnchor.constraint(equalTo: track.topAnchor),
            taken.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            taken.widthAnchor.constraint(equalTo: track.widthAnchor,
                                         multiplier: max(0.002, min(1, used / safeTotal))),

            give.leadingAnchor.constraint(equalTo: taken.trailingAnchor),
            give.topAnchor.constraint(equalTo: track.topAnchor),
            give.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            give.widthAnchor.constraint(equalTo: track.widthAnchor,
                                        multiplier: max(0.0, min(1, freeable / safeTotal))),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - a number worth looking at

/// One figure, large, with what it is underneath.
final class Stat: NSView {
    init(_ figure: String, _ caption: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let big = NSTextField(labelWithString: figure)
        big.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        big.textColor = Paint.ink
        big.lineBreakMode = .byTruncatingTail
        big.translatesAutoresizingMaskIntoConstraints = false
        addSubview(big)

        let small = NSTextField(labelWithString: caption)
        small.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        small.textColor = Paint.faint
        small.lineBreakMode = .byTruncatingTail
        small.translatesAutoresizingMaskIntoConstraints = false
        addSubview(small)

        NSLayoutConstraint.activate([
            big.leadingAnchor.constraint(equalTo: leadingAnchor),
            big.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            big.topAnchor.constraint(equalTo: topAnchor),
            small.leadingAnchor.constraint(equalTo: leadingAnchor),
            small.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            small.topAnchor.constraint(equalTo: big.bottomAnchor, constant: 3),
            small.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - something worth doing

/// Something nimo noticed, and the one button that deals with it.
final class Suggest: NSView {
    /// What this row is about, for a button that needs to name it.
    private(set) var name = ""

    init(_ headline: String, verb: String, strong: Bool,
         name: String = "", then: @escaping () -> Void) {
        super.init(frame: .zero)
        self.name = name
        translatesAutoresizingMaskIntoConstraints = false

        let top = NSTextField(labelWithString: headline)
        top.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        top.textColor = Paint.ink
        top.lineBreakMode = .byTruncatingTail
        top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)


        let button = Chip(strong ? .strong : .quiet)
        button.set(verb)
        button.index = tag
        button.subject = name
        button.onClick = then
        addSubview(button)

        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = Paint.line
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            top.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -20),
            top.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - one thing nimo said

/// A name, and what it came to. Two pieces of text on one line, the second one
/// starting at the same place every time so the eye can run down them — no
/// rules, no dots, no columns drawn round them.
final class Said: NSView {
    var onOpen: (() -> Void)?

    private var hovering = false
    private let arrow = NSImageView()

    init(label: String, value: String, strong: Bool, walkable: Bool = false) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

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

        if walkable, let picture = NSImage(systemSymbolName: "chevron.right",
                                           accessibilityDescription: nil) {
            picture.isTemplate = true
            arrow.image = picture
        }
        arrow.contentTintColor = Paint.faint
        arrow.alphaValue = 0
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        let column = left.widthAnchor.constraint(equalToConstant: 168)
        column.priority = .defaultHigh

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            left.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            column,
            right.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 188),
            right.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -8),
            right.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            right.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            left.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
            arrow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 11),
            arrow.heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard onOpen != nil else { return }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { onOpen?() }

    override func resetCursorRects() {
        if onOpen != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    private func repaint() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            arrow.animator().alphaValue = hovering ? 1 : 0
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: hovering ? Paint.hover : NSColor.clear)
        }
    }
}

// MARK: - the app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var main: Main!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The window first: the menu points at it, so it has to exist.
        main = Main()
        NSApp.mainMenu = buildMenu()
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

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(Main.openSettings), keyEquivalent: ",")
        settings.target = main
        app.addItem(.separator())
        app.addItem(settings)

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

        let view = NSMenuItem()
        bar.addItem(view)
        let look = NSMenu(title: "View")
        let fold = NSMenuItem(title: "Hide the list",
                              action: #selector(Main.foldSide), keyEquivalent: "b")
        fold.target = main
        look.addItem(fold)
        look.addItem(.separator())

        let back = NSMenuItem(title: "Back", action: #selector(Main.goBack), keyEquivalent: "[")
        back.target = main
        look.addItem(back)
        let on = NSMenuItem(title: "Forward", action: #selector(Main.goForward), keyEquivalent: "]")
        on.target = main
        look.addItem(on)
        view.submenu = look

        // Everything nimo does, by number.
        let goHolder = NSMenuItem()
        bar.addItem(goHolder)
        let go = NSMenu(title: "Go")
        for (i, item) in Action.all.enumerated() where i < 9 {
            let entry = NSMenuItem(title: item.title,
                                   action: #selector(Main.goByNumber(_:)),
                                   keyEquivalent: String(i + 1))
            entry.target = main
            entry.tag = i
            go.addItem(entry)
        }
        goHolder.submenu = go

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

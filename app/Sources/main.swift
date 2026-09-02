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
import UserNotifications

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

              The app was unpacked incompletely. Move the whole Kliner app —
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
    /// When a page's actions are all one gesture — forward, back, undo — a row
    /// of words is heavier than a row of pictures.
    let symbol: String?

    init(title: String, arguments: [String], asks: String?, symbol: String? = nil) {
        self.title = title; self.arguments = arguments
        self.asks = asks; self.symbol = symbol
    }
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
    /// Whether opening the page may run it. Asking nothing is not the same as
    /// changing nothing: Next changes your wallpaper the moment it runs, so
    /// arriving on that page must not run it.
    let looksOnly: Bool
    /// Draw this page's buttons as one group of pictures.
    let symbolic: Bool
    /// The picture for the big button. The row down the side says what the
    /// page is; this says what pressing it does.
    let does: String

    init(title: String, blurb: String, verb: String, arguments: [String],
         asks: String?, group: String, symbol: String, does: String = "play",
         extras: [Extra] = [], reveal: String? = nil, walks: Bool = false,
         looksOnly: Bool = true, symbolic: Bool = true) {
        self.title = title; self.blurb = blurb; self.verb = verb
        self.arguments = arguments; self.asks = asks; self.group = group
        self.symbol = symbol; self.extras = extras; self.reveal = reveal
        self.walks = walks; self.looksOnly = looksOnly; self.symbolic = symbolic
        self.does = does
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
                             symbol: "house",
                             does: "arrow.clockwise")

    static let putBack = "Move everything back where it was?\n\nnimo wrote down every move it made, so this is exact."

    static let all: [Action] = [
        home,

        Action(title: "Desktop",
               blurb: "Everything on your desktop, sorted into Desktop/Tidy by what it is. Nothing is deleted, and nothing is renamed.",
               verb: "Clear my desktop",
               arguments: ["desktop"],
               asks: "Move everything on your desktop into Desktop/Tidy, sorted by what it is?\n\nNothing is deleted. Put this back reverses it.",
               group: "Your desk",
               symbol: "square.grid.2x2",
               does: "tray.and.arrow.down",
               extras: [Extra(title: "Put this back", arguments: ["desktop", "--undo"], asks: putBack,
                              symbol: "arrow.uturn.backward")],
               reveal: "Desktop"),

        Action(title: "Downloads",
               blurb: "The same, for the folder everything lands in and nothing ever leaves.",
               verb: "Sort my downloads",
               arguments: ["downloads"],
               asks: "Sort your downloads into Downloads/Tidy?\n\nNothing is deleted. Put this back reverses it.",
               group: "Your desk",
               symbol: "arrow.down.circle",
               does: "tray.and.arrow.down",
               extras: [Extra(title: "Put this back", arguments: ["downloads", "--undo"], asks: putBack,
                              symbol: "arrow.uturn.backward")],
               reveal: "Downloads"),

        Action(title: "Wallpaper",
               blurb: "Step through the wallpapers your Mac already ships with. Nothing is downloaded.",
               verb: "Next",
               arguments: ["next"],
               asks: nil,
               group: "Your screen",
               symbol: "photo",
               does: "chevron.right",
               extras: [Extra(title: "Previous", arguments: ["prev"], asks: nil,
                              symbol: "chevron.left"),
                        Extra(title: "The one I had", arguments: ["wallpaper", "--restore"],
                              asks: nil, symbol: "arrow.uturn.backward")],
               looksOnly: false, symbolic: true),

        Action(title: "Startup",
               blurb: "What launches itself when you sign in — and which of them nimo can turn off.",
               verb: "Look again",
               arguments: ["startup", "--list"],
               asks: nil,
               group: "Your screen",
               symbol: "power",
               does: "arrow.clockwise"),

        Action(title: "What is big",
               blurb: "The folders in your home that are taking up the room. Click one to look inside it.",
               verb: "Measure",
               arguments: ["top"],
               asks: nil,
               group: "Your disk",
               symbol: "chart.bar",
               does: "arrow.clockwise",
               walks: true),

        Action(title: "Free up space",
               blurb: "Caches and temporary files your apps rebuild by themselves. Your own files are never touched.",
               verb: "Free it up",
               arguments: ["clean"],
               asks: "Delete the caches and temporary files nimo found?\n\nYour own files are never touched.",
               group: "Your disk",
               symbol: "sparkles",
               does: "sparkles",
               extras: [Extra(title: "Only look", arguments: ["preview"], asks: nil, symbol: "eye")]),

        Action(title: "How it is",
               blurb: "Disk, memory, uptime, battery — how your computer is doing right now.",
               verb: "Check",
               arguments: ["doctor"],
               asks: nil,
               group: "Your computer",
               symbol: "waveform.path.ecg",
               does: "arrow.clockwise"),

        Action(title: "Put it all back",
               blurb: "Everything nimo has done, reversed, newest first. This is why nothing here is frightening.",
               verb: "Put it all back",
               arguments: ["undo", "--all"],
               asks: "Reverse everything nimo has done, newest first?",
               group: "Your computer",
               symbol: "arrow.uturn.backward",
               does: "arrow.uturn.backward",
               extras: [Extra(title: "Only look", arguments: ["undo", "--all", "--dry-run"], asks: nil,
                              symbol: "eye")]),
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

// MARK: - a word when it is done

/// A job takes a few seconds and you may have gone elsewhere. macOS will say
/// so for us, once you have allowed it — and if you have not, nothing here
/// complains about it.
enum Word {
    static func ask() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func say(_ headline: String, _ detail: String) {
        let centre = UNUserNotificationCenter.current()
        centre.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let note = UNMutableNotificationContent()
            note.title = headline
            note.body = detail
            centre.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: note, trigger: nil))
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
    /// Three frames, not two. An eye that goes open, half, shut, half, open
    /// reads as an eye closing; two frames read as a flicker.
    private let open  = NSImage(named: "wordmark")
    private let half  = NSImage(named: "wordmark-half")
    private let shut  = NSImage(named: "wordmark-blink")
    private let small     = NSImage(named: "mascot")
    private let smallHalf = NSImage(named: "mascot-half")
    private let smallShut = NSImage(named: "mascot-blink")

    private var pending: Timer?
    private var folded = false
    private var stage = 0            // 0 open, 1 halfway, 2 shut

    init() {
        super.init(frame: .zero)
        // Every one of them is a template: macOS draws the shape in the colour
        // of the text beside it, so the face is never a black blob.
        for picture in [open, half, shut, small, smallHalf, smallShut] {
            picture?.isTemplate = true
        }
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignLeft
        translatesAutoresizingMaskIntoConstraints = false
        wake()
        later()
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    deinit { pending?.invalidate() }

    /// Folded down to a rail there is no room for a word, so the face goes
    /// there instead — and it blinks the same way.
    func fold(_ yes: Bool) {
        folded = yes
        imageAlignment = yes ? .alignCenter : .alignLeft
        wake()
    }

    private func wake() {
        let frames = folded ? [small, smallHalf, smallShut] : [open, half, shut]
        image = frames[min(stage, 2)]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// Look at it and it looks back.
    override func mouseEntered(with event: NSEvent) { blink() }

    private func later() {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Double.random(in: 4...8),
                                       repeats: false) { [weak self] _ in
            self?.blink()
        }
    }

    /// Down in two steps, held, and up in two. Sixty milliseconds a step is
    /// the shortest that still reads as a movement rather than a glitch.
    private func blink() {
        guard window != nil, stage == 0 else { later(); return }
        run([(1, 0.06), (2, 0.06), (2, 0.07), (1, 0.06), (0, 0)]) { [weak self] in
            guard let self = self else { return }
            self.glance()
            if Bool.random() && Bool.random() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    self.run([(1, 0.05), (2, 0.06), (1, 0.05), (0, 0)]) { self.later() }
                }
            } else {
                self.later()
            }
        }
    }

    /// A blink that ends with a small look sideways. Two points is nothing on
    /// its own and everything at this size: it turns a shutter into a glance.
    private func glance() {
        wantsLayer = true
        let look = CAKeyframeAnimation(keyPath: "transform.translation.x")
        look.values = [0, Bool.random() ? 2.0 : -2.0, 0]
        look.keyTimes = [0, 0.45, 1]
        look.duration = 0.5
        look.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(look, forKey: "glance")
    }

    private func run(_ steps: [(Int, Double)], then: @escaping () -> Void) {
        guard let (next, wait) = steps.first else { then(); return }
        stage = next
        wake()
        if steps.count == 1 { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.run(Array(steps.dropFirst()), then: then)
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            self.name.animator().alphaValue = yes ? 0 : 1
        }
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
        // Busy is not broken. The strong button keeps its fill and dims;
        // turning it into a grey slab made it look like it had stopped
        // working rather than like it was working.
        let background: NSColor
        if kind == .strong {
            background = Paint.strong
            label.textColor = Paint.onStrong
        } else {
            background = hovering && live ? Paint.picked : NSColor.clear
            label.textColor = !live ? Paint.faint : (hovering ? Paint.ink : Paint.muted)
        }

        var strength: Float = 1
        if !live { strength = 0.4 } else if hovering && kind == .strong { strength = 0.86 }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: background)
            self.layer?.opacity = strength
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
    private var welcoming = false
    private var step = 0
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

        window.title = "Kliner"
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
        if Config.value("welcomed") == nil {
            welcoming = true
            for row in rows { row.choose(false) }
            drawWelcome()          // each step sets its own title
        } else {
            show(0)
        }
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
        // A template image takes its colour from here; the folded face is not
        // one, so this simply does not reach it.
        mark.contentTintColor = Paint.ink
        wordmark = mark
        stack.addArrangedSubview(mark)
        markWidth = mark.widthAnchor.constraint(equalToConstant: 190)
        NSLayoutConstraint.activate([
            mark.heightAnchor.constraint(equalToConstant: 22),
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

        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 9
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        scroll.contentView = TopClip()
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
        // The last light ends at x = 72; four points of air after it.
        chromeLeading = chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 76)
        stackWidth = stack.widthAnchor.constraint(equalToConstant: 214)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
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
            // The lights are 12pt across with their centres on y = 20 in a
            // standard title bar; a 26pt button centred on the same line
            // starts at 7.
            chrome.topAnchor.constraint(equalTo: content.topAnchor, constant: 7),

            titleLabel.leadingAnchor.constraint(equalTo: edge.trailingAnchor, constant: 46),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -46),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 62),

            buttons.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -44),
            buttons.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),

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
    /// The first time, and only the first time: four pages that say what this
    /// is and what it will not do, and *then* ask macOS for anything. Being
    /// asked for your Desktop by a window you have not read yet is how an app
    /// gets refused.
    private func drawWelcome() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in buttons.arrangedSubviews {
            buttons.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch step {
        case 0:
            titleLabel.stringValue = "Hello"
            line(Floating())
            words("Kliner tidies the parts of a Mac that quietly get away from you.",
                  size: 15, weight: .medium, colour: Paint.ink, top: 4, bottom: 10)
            words("Eighty things on the desktop. Three hundred in Downloads. A wallpaper you never chose.",
                  size: 13.5, weight: .regular, colour: Paint.muted, top: 0, bottom: 6)

        case 1:
            titleLabel.stringValue = "What it does"
            for item in Action.all where item.title != "Home" {
                line(Told(item.symbol, item.title, item.blurb))
            }

        case 2:
            titleLabel.stringValue = "Nothing is lost"
            line(Told("arrow.uturn.backward", "It writes down every move",
                      "Put it all back reverses any of it, newest first."))
            line(Told("house", "It stays in your home folder",
                      "Nothing outside it is read, moved or removed."))
            line(Told("lock.open", "It never asks for an administrator",
                      "And it never uses the network."))
            line(Told("questionmark.circle", "It asks before it changes anything",
                      "Every page shows you what it would do first."))

        case 3:
            titleLabel.stringValue = "One last thing"
            words("macOS decides what an app may read, not the app.",
                  size: 15, weight: .medium, colour: Paint.ink, top: 4, bottom: 8)
            words("Left alone it asks once per folder, over and over. Full Disk Access is the one switch that ends that — and Kliner still only reads inside your home.",
                  size: 13.5, weight: .regular, colour: Paint.muted, top: 0, bottom: 14)
            line(Told("folder", "Your folders", "Desktop, Downloads, Pictures, Documents."))
            line(Told("externaldrive", "Full Disk Access", "Optional. It only stops the asking."))

        default:
            break
        }

        // ---- the way through ---------------------------------------------
        if step > 0 {
            buttons.addArrangedSubview(quiet("Back") { [weak self] in
                self?.step -= 1
                self?.drawWelcome()
            })
        }

        let on = Chip(.strong)
        on.set(step < 3 ? "Next" : "Ask macOS, and start")
        on.onClick = { [weak self] in
            guard let self = self else { return }
            if self.step < 3 {
                self.step += 1
                self.drawWelcome()
                return
            }
            Word.ask()
            self.askForEverything()
            self.finishWelcome()
            self.show(0)
        }
        buttons.addArrangedSubview(on)

        if step == 3 {
            buttons.addArrangedSubview(quiet("Skip for now") { [weak self] in
                self?.finishWelcome()
                self?.show(0)
            })
        }

        line(Dots(of: 4, at: step))
        settle()
    }

    private func finishWelcome() {
        welcoming = false
        Config.set("welcomed", "yes")
    }

    private func drawHome(_ pieces: [Piece]) {
        var figures: [String: String] = [:]
        for piece in pieces {
            if case .row(let label, let value, _, _, _) = piece { figures[label] = value }
        }

        // The disk first, because it is the picture. The figures under it,
        // because they are the caption.
        var total = 0.0, free = 0.0
        if let disk = figures["Disk"] {
            let parts = disk.components(separatedBy: " of ")
            free = bytes(parts.first?.replacingOccurrences(of: " free", with: "") ?? "") ?? 0
            total = parts.count > 1 ? (bytes(parts[1]) ?? 0) : 0
        }
        let junk = bytes(figures["Junk"] ?? "") ?? 0

        if total > 0 {
            let used = max(0, total - free)
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            let disk = Disk(used: used - junk, freeable: junk, total: total,
                            freeNow: (figures["Disk"] ?? "").replacingOccurrences(of: " of ", with: " free of "),
                            freeAfter: junk > 0 ? "\(size(free + junk)) after freeing it up" : "")
            disk.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(disk)
            NSLayoutConstraint.activate([
                disk.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                disk.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                disk.topAnchor.constraint(equalTo: holder.topAnchor, constant: 4),
                disk.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8),
            ])
            line(holder)
        }

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
                figuresRow.topAnchor.constraint(equalTo: holder.topAnchor, constant: 20),
                figuresRow.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -4),
            ])
            line(holder)
        }

        // ---- what is worth doing about it ------------------------------
        words("Worth doing", size: 12.5, weight: .regular, colour: Paint.faint,
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
                             self?.show(6)
                         })
            said = true
        }

        if !said {
            words("Nothing needs doing. Your Mac is clear.",
                  size: 13.5, weight: .medium, colour: Paint.ink, top: 6, bottom: 6)
        }
    }

    /// Stopping one thing by name, which is what --only is for. nimo still
    /// asks; the dialog here is that question.
    private func stopThis(_ name: String) {
        guard !name.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Stop \(name) from starting?"
        alert.informativeText = "It is not uninstalled. It stops launching itself when you sign in, and Put it all back reverses that."
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
                words(text, size: 12.5, weight: .regular, colour: Paint.faint,
                      top: 26, bottom: 8)

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

            // One size for everything nimo says. Weight and colour carry the
            // difference; a second size only makes the page look assembled
            // out of two pages.
            case .good(let text):
                words(text, size: 13.5, weight: .medium, colour: Paint.ink, top: 7, bottom: 6)

            case .warn(let text):
                words(text, size: 13.5, weight: .medium, colour: Paint.body, top: 7, bottom: 6)

            case .note:
                // nimo's last lines tell a terminal what to type next. There
                // is nothing to type here, so they are not shown.
                break

            case .text(let text):
                words(text, size: 13.5, weight: .regular, colour: Paint.body, top: 6, bottom: 6)
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

    /// While nimo is off doing the thing, the page holds its face.
    private func waiting() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        line(Thinking())
        settle()
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
        if welcoming {
            welcoming = false
            Config.set("welcomed", "yes")
        }
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

        // Open a page and it fills in by itself — but only if arriving cannot
        // change anything. The ones that ask show their --dry-run; the ones
        // that act without asking, like Next, wait for you to press the button.
        if item.asks != nil {
            run(item, preview: true)
        } else if item.looksOnly {
            run(item)
        } else {
            seen.insert(index)
            draw([.text("Ready when you are.")])
        }
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

        // One group, one picture each, a hairline between them, and the words
        // on the tooltips. The page title already says what you are looking
        // at; three sentences of buttons under it said it again.
        let group = NSStackView()
        group.orientation = .horizontal
        group.spacing = 0
        group.wantsLayer = true
        group.layer?.cornerRadius = 9
        group.translatesAutoresizingMaskIntoConstraints = false
        group.effectiveAppearance.performAsCurrentDrawingAppearance {
            group.layer?.backgroundColor = Paint.picked.cgColor
        }

        func hairline() {
            let hair = NSBox()
            hair.boxType = .custom
            hair.borderWidth = 0
            hair.fillColor = Paint.line
            hair.translatesAutoresizingMaskIntoConstraints = false
            hair.widthAnchor.constraint(equalToConstant: 1).isActive = true
            hair.heightAnchor.constraint(equalToConstant: 16).isActive = true
            group.addArrangedSubview(hair)
        }

        let first = Ghost(item.does)
        first.onClick = { [weak self] in self?.go() }
        first.toolTip = item.verb
        first.isEnabled = !busy
        group.addArrangedSubview(first)

        if !walked.isEmpty {
            hairline()
            let up = Ghost("arrow.up.left")
            up.toolTip = "Back out of this folder"
            up.isEnabled = !busy
            up.onClick = { [weak self] in self?.walkUp() }
            group.addArrangedSubview(up)
        }

        for (i, extra) in item.extras.enumerated() {
            hairline()
            let button = Ghost(extra.symbol ?? "circle")
            button.toolTip = extra.title
            button.isEnabled = !busy
            button.onClick = { [weak self] in self?.runExtra(i) }
            group.addArrangedSubview(button)
        }

        if item.reveal != nil {
            hairline()
            let finder = Ghost("folder")
            finder.toolTip = "Show in Finder"
            finder.isEnabled = !busy
            finder.onClick = { [weak self] in self?.revealFolder() }
            group.addArrangedSubview(finder)
        }

        buttons.addArrangedSubview(group)
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

    /// Desktop/Tidy/Images if nimo has already made it, the folder itself if
    /// it has not. Either way you end up looking at the thing the row named.
    private func openKind(_ folder: String, _ kind: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tidy = home.appendingPathComponent(folder)
            .appendingPathComponent("Tidy")
            .appendingPathComponent(kind)
        let target = FileManager.default.fileExists(atPath: tidy.path)
            ? tidy : home.appendingPathComponent(folder)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path)
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

        words("Kliner", size: 12.5, weight: .regular, colour: Paint.faint, top: 2, bottom: 8)

        let login = NSSwitch()
        login.state = Login.on ? .on : .off
        login.isEnabled = Login.possible
        login.target = self
        login.action = #selector(loginChanged(_:))
        line(Setting("Open when I sign in", control: login))

        let days = NSPopUpButton()
        days.addItems(withTitles: ["7 days", "30 days", "90 days"])
        days.selectItem(withTitle: (Config.value("days") ?? "30") + " days")
        if days.indexOfSelectedItem < 0 { days.selectItem(withTitle: "30 days") }
        days.target = self
        days.action = #selector(daysChanged(_:))
        line(Setting("Old means older than", control: days))

        line(Setting("In a terminal",
                     control: quiet("Open") { [weak self] in self?.openTerminal() }))

        // ---- what macOS will let it touch --------------------------------
        // Each row says what is true; the button does the only thing there is
        // to do about it.
        words("Access", size: 12.5, weight: .regular, colour: Paint.faint,
              top: 30, bottom: 8)

        // Full Disk Access first, because it is the one that ends the asking.
        // Folder by folder, macOS prompts again for every folder nimo has not
        // been in yet; with this on it never prompts at all.
        line(Setting(Access.everything ? "Full Disk Access, on" : "Full Disk Access, off",
                     control: quiet(Access.everything ? "Settings" : "Turn on") {
                         [weak self] in self?.explainFullDisk()
                     }))

        let openFolders = Access.may(Access.desktop) && Access.may(Access.downloads)
        line(Setting(openFolders ? "Your folders" : "Your folders, not yet",
                     control: quiet(openFolders ? "Check again" : "Ask") {
                         [weak self] in self?.askForEverything()
                     }))

        line(Setting("Changing your wallpaper",
                     control: quiet("Settings") { Access.settings("Privacy_Automation") }))

        words("Kliner \(Nimo.version) · MIT · kliner.app",
              size: 12.5, weight: .regular, colour: Paint.faint, top: 32, bottom: 4)

        settle()
    }

    /// The same hairline the list down the side uses, across the page.
    private func divider() {
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = Paint.line
        rule.translatesAutoresizingMaskIntoConstraints = false

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(rule)
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 30),
            rule.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            rule.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
        line(holder)
    }

    /// Reading a folder is what raises the prompt, so asking and checking are
    /// the same act. Then the page is drawn again from whatever you answered.
    /// macOS will not let an app switch this on, and it will not let it point
    /// at itself in the list either. What it can do is say which switch, and
    /// open the page it is on.
    private func explainFullDisk() {
        if Access.everything {
            Access.settings("Privacy_AllFiles")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Turn on Full Disk Access for Kliner"
        alert.informativeText = """
        Settings will open on the right page. Switch Kliner on in the list, \
        then come back — it will stop asking about folders one at a time.

        Nothing else changes: Kliner still only reads inside your home folder.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Access.settings("Privacy_AllFiles")
    }

    private func askForEverything() {
        Access.may(Access.desktop)
        Access.may(Access.downloads)
        Access.may(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures"))
        Access.may(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents"))
        drawSettings()
    }

    @objc private func loginChanged(_ sender: NSSwitch) {
        if let trouble = Login.set(sender.state == .on) {
            let alert = NSAlert()
            alert.messageText = "Kliner could not change that"
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
        fitButtons()
        waiting()

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
        fitButtons()
        waiting()
        spin(arguments)
    }

    private func spin(_ arguments: [String]) {
        // Which page asked. A run takes seconds, and in those seconds you can
        // be somewhere else — Settings, most often, because it is the one you
        // click while something is still going. Its answer belongs to the page
        // that asked for it and nowhere else.
        let asked = chosen

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                guard self.chosen == asked else {
                    self.busy = false
                    self.fitButtons()
                    return
                }
                let pieces = Report.parse(result.text)
                if pieces.isEmpty { self.say("Kliner said nothing at all.") }
                else { self.draw(pieces) }

                // Only for the ones that changed something, and only the line
                // nimo already wrote — no second opinion invented here.
                if !arguments.contains("--dry-run"), arguments.contains("--yes") {
                    for piece in pieces {
                        if case .good(let done) = piece {
                            Word.say(Action.all[asked].title, done)
                            break
                        }
                    }
                }
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            for head in self.groupLabels { head.animator().alphaValue = self.narrow ? 0 : 1 }
        }
        for row in rows { row.narrow(narrow) }
        for head in groupLabels { head.isHidden = narrow }
        wordmark.fold(narrow)
        markWidth.constant = narrow ? 38 : 190
        stackWidth.constant = narrow ? 38 : 214
        railWidth.constant = narrow ? 70 : 246
        chromeLeading.constant = narrow ? 90 : 76
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

/// And back again, in the units nimo would have used.
func size(_ value: Double) -> String {
    let units: [(Double, String)] = [(1_000_000_000_000, "TB"), (1_000_000_000, "GB"),
                                     (1_000_000, "MB"), (1_000, "KB")]
    for (scale, name) in units where value >= scale {
        return String(format: value / scale >= 10 ? "%.0f %@" : "%.1f %@", value / scale, name)
    }
    return String(format: "%.0f B", value)
}

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

/// The disk as one bar: what is taken, the part nimo could give back, and
/// what is already free — with the only two numbers that matter written under
/// it. Two bars said the same thing twice; this says it once.
final class Disk: NSView {
    init(used: Double, freeable: Double, total: Double, freeNow: String, freeAfter: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 6
        track.layer?.masksToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)
        track.effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = Paint.picked.cgColor
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

        let whole = max(total, 1)
        let taken = slice(Paint.muted)
        let give  = slice(Paint.strong)

        let now = NSTextField(labelWithString: freeNow)
        now.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        now.textColor = Paint.muted
        now.translatesAutoresizingMaskIntoConstraints = false
        addSubview(now)

        let after = NSTextField(labelWithString: freeAfter)
        after.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        after.textColor = Paint.faint
        after.alignment = .right
        after.translatesAutoresizingMaskIntoConstraints = false
        addSubview(after)

        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.heightAnchor.constraint(equalToConstant: 12),

            taken.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            taken.topAnchor.constraint(equalTo: track.topAnchor),
            taken.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            taken.widthAnchor.constraint(equalTo: track.widthAnchor,
                                         multiplier: max(0.004, min(1, used / whole))),

            give.leadingAnchor.constraint(equalTo: taken.trailingAnchor),
            give.topAnchor.constraint(equalTo: track.topAnchor),
            give.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            give.widthAnchor.constraint(equalTo: track.widthAnchor,
                                        multiplier: max(0.0, min(1, freeable / whole))),

            now.leadingAnchor.constraint(equalTo: leadingAnchor),
            now.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 11),
            now.bottomAnchor.constraint(equalTo: bottomAnchor),
            after.trailingAnchor.constraint(equalTo: trailingAnchor),
            after.firstBaselineAnchor.constraint(equalTo: now.firstBaselineAnchor),
            after.leadingAnchor.constraint(greaterThanOrEqualTo: now.trailingAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }
}

// MARK: - a line with a picture beside it

/// A picture, a name, and one line under it. What the welcome is made of.
final class Told: NSView {
    init(_ symbol: String, _ name: String, _ note: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        if let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            icon.image = picture
        }
        icon.contentTintColor = Paint.muted
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: name)
        title.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        title.textColor = Paint.ink
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let under = Wrapping(labelWithString: note)
        under.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        under.textColor = Paint.faint
        under.maximumNumberOfLines = 2
        under.lineBreakMode = .byWordWrapping
        under.translatesAutoresizingMaskIntoConstraints = false
        addSubview(under)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            under.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            under.trailingAnchor.constraint(equalTo: trailingAnchor),
            under.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            under.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

/// Where you are in the welcome. Four dots, one of them lit.
final class Dots: NSView {
    init(of many: Int, at here: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var last: NSView?
        for i in 0..<many {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            addSubview(dot)
            dot.effectiveAppearance.performAsCurrentDrawingAppearance {
                dot.layer?.backgroundColor = (i == here ? Paint.ink : Paint.picked).cgColor
            }
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: i == here ? 18 : 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
                dot.centerYAnchor.constraint(equalTo: centerYAnchor),
                dot.leadingAnchor.constraint(equalTo: last?.trailingAnchor ?? leadingAnchor,
                                             constant: last == nil ? 0 : 6),
            ])
            last = dot
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

// MARK: - the face, drifting

/// The face on the welcome page, floating the way something weightless does.
/// It is the only thing on that page that moves, and it is what tells you the
/// app has a character rather than a control panel.
final class Floating: NSView {
    private let face = NSImageView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        face.contentTintColor = Paint.ink
        face.imageScaling = .scaleProportionallyUpOrDown
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 132),
            face.leadingAnchor.constraint(equalTo: leadingAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: 76),
            face.heightAnchor.constraint(equalToConstant: 76),
        ])

        drift()
        blinkLater()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    private var pending: Timer?
    deinit { pending?.invalidate() }

    private func drift() {
        face.wantsLayer = true

        let up = CABasicAnimation(keyPath: "transform.translation.y")
        up.fromValue = -5
        up.toValue = 5
        up.duration = 2.4
        up.autoreverses = true
        up.repeatCount = .infinity
        up.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(up, forKey: "drifting")

        let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = -0.045
        tilt.toValue = 0.045
        tilt.duration = 3.7
        tilt.autoreverses = true
        tilt.repeatCount = .infinity
        tilt.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(tilt, forKey: "tilting")
    }

    private func blinkLater() {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2...5),
                                       repeats: false) { [weak self] _ in
            guard let self = self, self.window != nil else { return }
            self.step(["mascot-half", "mascot-blink", "mascot-half", "mascot"], 0)
        }
    }

    private func step(_ names: [String], _ i: Int) {
        guard i < names.count else { blinkLater(); return }
        let picture = NSImage(named: names[i])
        picture?.isTemplate = true
        face.image = picture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.step(names, i + 1)
        }
    }
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

// MARK: - a scroll view that starts at the top

/// AppKit's clip view is not flipped, so a document view shorter than the
/// scroll view sits at the *bottom* of it. That is why every page had a hole
/// above it and its content pushed to the floor. One override fixes the lot.
final class TopClip: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - thinking

/// nimo, breathing, while it works. A spinner says a machine is busy; a face
/// that blinks says somebody is looking at the thing you asked about.
final class Thinking: NSView {
    /// nimo's own outline, measured off the artwork: the radius of the shape
    /// at seventy-two angles, as a fraction of its widest. The ring that turns
    /// while you wait traces this, so it goes round the face rather than round
    /// a circle the face happens to sit in.
    static let outline: [CGFloat] = [
        0.9560, 0.9355, 0.9150, 0.8974, 0.8798, 0.8592, 0.8592, 0.8710, 0.9032,
        0.9443, 0.9736, 0.9941, 1.0000, 0.9883, 0.9589, 0.9091, 0.8504, 0.7889,
        0.7419, 0.7947, 0.8504, 0.9091, 0.9589, 0.9883, 1.0000, 0.9941, 0.9736,
        0.9355, 0.9032, 0.8710, 0.8534, 0.8592, 0.8739, 0.8974, 0.9150, 0.9355,
        0.9501, 0.9589, 0.9501, 0.9326, 0.9032, 0.8592, 0.8035, 0.7566, 0.7273,
        0.7126, 0.7097, 0.7449, 0.7830, 0.8299, 0.8651, 0.8915, 0.9032, 0.9062,
        0.9003, 0.9003, 0.8915, 0.8798, 0.8534, 0.8211, 0.7859, 0.7449, 0.7185,
        0.7038, 0.7185, 0.7507, 0.7977, 0.8475, 0.8974, 0.9384, 0.9560, 0.9589,
    ]

    private let face = NSImageView()
    private let ring = CAShapeLayer()
    private var pending: Timer?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        face.contentTintColor = Paint.muted
        face.imageScaling = .scaleProportionallyUpOrDown
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: 88),
            face.heightAnchor.constraint(equalToConstant: 88),
        ])

        layer?.addSublayer(ring)
        breathe()
        blinkLater()
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    deinit { pending?.invalidate() }

    /// The shape, as a path, at whatever size it is asked for.
    private static func path(around middle: CGPoint, reach: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (i, r) in outline.enumerated() {
            let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(outline.count)
            let point = CGPoint(x: middle.x + cos(angle) * reach * r,
                                y: middle.y + sin(angle) * reach * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    override func layout() {
        super.layout()
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = bounds
        ring.path = Thinking.path(around: middle, reach: 74)
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.lineCap = .round
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.ring.strokeColor = Paint.muted.cgColor
        }
        travel()
    }

    /// A short piece of the outline, going round it. The whole outline drawn
    /// at once would be a box round the face; a piece of it going round is
    /// something waiting.
    private func travel() {
        guard ring.animation(forKey: "travelling") == nil else { return }
        ring.strokeStart = 0
        ring.strokeEnd = 0.16

        let head = CABasicAnimation(keyPath: "strokeEnd")
        head.fromValue = 0.16
        head.toValue = 1.16

        let tail = CABasicAnimation(keyPath: "strokeStart")
        tail.fromValue = 0.0
        tail.toValue = 1.0

        let both = CAAnimationGroup()
        both.animations = [head, tail]
        both.duration = 2.2
        both.repeatCount = .infinity
        both.timingFunction = CAMediaTimingFunction(name: .linear)
        ring.add(both, forKey: "travelling")
    }

    /// Slower than a spinner on purpose: nimo is thinking, not straining.
    private func breathe() {
        face.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 0.94
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(pulse, forKey: "breathing")
    }

    /// The same movement the wordmark makes, in the same steps.
    private func close(_ steps: [(String, Double)], then: @escaping () -> Void) {
        guard let (name, wait) = steps.first else { then(); return }
        let picture = NSImage(named: name)
        picture?.isTemplate = true
        face.image = picture
        if steps.count == 1 { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.close(Array(steps.dropFirst()), then: then)
        }
    }

    private func blinkLater() {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Double.random(in: 1...2.4),
                                       repeats: false) { [weak self] _ in
            guard let self = self, self.window != nil else { return }
            self.close([("mascot-half", 0.06), ("mascot-blink", 0.07),
                        ("mascot-half", 0.06), ("mascot", 0)]) {
                self.blinkLater()
            }
        }
    }
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
        let about = NSMenuItem(title: "About Kliner",
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
        let terminal = NSMenuItem(title: "Open in Terminal…",
                                  action: #selector(openInTerminal), keyEquivalent: "")
        terminal.target = self
        app.addItem(terminal)

        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide Kliner",
                               action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: "Quit Kliner",
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
            alert.messageText = "Kliner could not change that"
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
        alert.messageText = "Kliner \(Nimo.version)"
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
           let url = URL(string: "https://kliner.app") {
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

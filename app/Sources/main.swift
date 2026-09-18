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

// MARK: - one type scale, one spacing scale

/// Ten sizes of text on nine pages is what "nothing lines up" looks like from
/// the outside. There are six here, and nothing outside this enum names a
/// point size.
enum Words {
    /// The name of the page, once, at the top of it.
    /// The name of the page, in the row along the top, on the same line as
    /// everything else in it. Two weights, because it is written as a trail:
    /// where you are, in the place it belongs. Small, because a title bar is
    /// a title bar and not a headline.
    static let title  = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let trail  = NSFont.systemFont(ofSize: 14, weight: .regular)
    /// The one line that opens the setup.
    static let hero   = NSFont.systemFont(ofSize: 25, weight: .semibold)
    /// A number worth reading across the room. Monospaced digits, so a figure
    /// that changes does not shuffle the words after it.
    static let figure = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
    /// The top of a card, or a line that opens a group.
    static let head   = NSFont.systemFont(ofSize: 15, weight: .semibold)
    /// Everything anybody actually reads.
    ///
    /// Fourteen, not thirteen. Measured off the picture: its running text is
    /// about fourteen points set on twenty-seven, and beside it a Mac app at
    /// the system thirteen on seventeen reads as something squashed to fit.
    static let body   = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let strong = NSFont.systemFont(ofSize: 14, weight: .medium)
    /// A caption under something, or a column heading over one.
    static let small  = NSFont.systemFont(ofSize: 12, weight: .regular)
    /// A label on a control, and nothing else.
    static let tiny   = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// The word over a card or a figure, set small and spaced in capitals.
    static let label  = NSFont.systemFont(ofSize: 11, weight: .semibold)

    /// A figure in a table, which has to line up with the figure above it.
    static let column = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)

    /// The line you type into in the menu that ⌘K opens. Bigger than the
    /// window's own text, because it is the only thing on its row and the
    /// first thing your eye lands on.
    static let ask    = NSFont.systemFont(ofSize: 17, weight: .regular)

    // ---- the overview, which is read from further away ---------------------
    /// The one number the page is about. Nothing else on the page is this big,
    /// which is what makes it the one number the page is about.
    static let huge   = NSFont.systemFont(ofSize: 58, weight: .medium)
    /// GB, beside it. A unit set at the same size as its figure is a second
    /// figure; set small and quiet it is a unit.
    static let unit   = NSFont.systemFont(ofSize: 21, weight: .regular)
    /// The paragraph under the number, and the line under a row's name.
    static let lead   = NSFont.systemFont(ofSize: 15, weight: .regular)
    /// The name of a row on the overview.
    static let entry  = NSFont.systemFont(ofSize: 17, weight: .regular)
    /// The command a row stands for, set in the terminal's own letters so it
    /// reads as something you could type, because it is.
    static let typed  = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    /// The name along the top of a card. Set in sentence case at a readable
    /// size, not in small spaced capitals: a card's name is a name, and the
    /// capitals were a label on a filing box.
    static let cardName = NSFont.systemFont(ofSize: 19, weight: .semibold)
}

/// Every gap in the window is one of these. Four points apart, so two things
/// that should look the same distance apart are the same distance apart.
enum Step {
    static let hair:  CGFloat = 4
    static let tight: CGFloat = 8
    static let close: CGFloat = 12
    static let air:   CGFloat = 16
    static let wide:  CGFloat = 24
    static let page:  CGFloat = 32
    static let edge:  CGFloat = 40

    /// The row across the top of the window, and the line everything in it
    /// stands on.
    ///
    /// macOS puts the three lights in a 28 point title bar, 14 across, so
    /// their middle is at 13, and nothing Kliner draws can move them. The
    /// lights and the chrome sit on that line; the page's own tab is in the
    /// band under it, hanging off it onto the card, which is where the
    /// picture puts it and where a tab strip has always gone.
    static let bar:   CGFloat = 28
    static let lights: CGFloat = 13
    /// From the top of the window to the top of the card: the title bar, and
    /// the band under it that the tab hangs in.
    static let crown: CGFloat = 52
}

// MARK: - nimo's colours

enum Paint {
    /// Kliner's own colours, the ones the site is drawn in. The window used to
    /// be system grey over glass, which meant it took its colour from whatever
    /// wallpaper happened to be behind it: on a warm photograph the whole app
    /// went brown. These do not move.
    private static func of(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green:   CGFloat((value >> 8) & 0xFF) / 255,
                blue:    CGFloat(value & 0xFF) / 255,
                alpha:   1)
    }

    /// One colour, told twice: what it is on a light Mac and what it is on a
    /// dark one. macOS asks the block again when the appearance changes, so
    /// nothing in the window has to be repainted by hand to follow the system.
    private static func duo(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { look in
            look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? Paint.of(dark) : Paint.of(light)
        }
    }

    // ---- the surfaces, lightest first --------------------------------------
    //
    // Kliner is a light window with one warm colour in it. The ground is a
    // grey you can tell from the cards standing on it; the cards are the
    // lighter thing, because a card darker than the page reads as a hole.
    /// The window's own ground.
    static let veil = duo(0xE9E8E6, 0x121211)
    /// The side of the window. The same ground: the list stands on the page
    /// rather than in a compartment of its own.
    static let rail   = duo(0xE9E8E6, 0x121211)
    /// A card standing on the ground.
    static let card   = duo(0xF6F5F3, 0x1C1C1B)
    /// And a panel standing on that card is lighter again.
    static let panel  = duo(0xFFFFFF, 0x242423)
    /// Kept for anything measured against the page rather than drawn on it.
    static let ground = duo(0xF1F0EE, 0x181817)

    static let line   = duo(0xE4E2DE, 0x2E2E2C)
    static let hover  = duo(0xEDECE9, 0x272726)
    /// The row you are on, and the fill under anything chosen.
    static let picked = duo(0xE6E4E0, 0x2B2B29)
    /// The unlit half of anything that fills, and the ground under a chip.
    static let track  = duo(0xEAE8E4, 0x2A2A28)

    // ---- what is written on them -------------------------------------------
    static let ink    = duo(0x171614, 0xF7F6F4)
    static let body   = duo(0x3A3835, 0xC9C7C3)
    static let muted  = duo(0x7A7772, 0x94918C)
    static let faint  = duo(0xA9A6A0, 0x6E6B67)

    /// One warm colour, and nothing else.
    ///
    /// Every dashboard reaches for a hue and then puts it on the button, the
    /// selected row, the first bar of the chart and the icon beside a job —
    /// four coloured things, which is four things shouting. There is one here,
    /// and it is spent in one place at a time. Everything that would have been
    /// a second and a third colour is a *texture* instead: the same orange,
    /// hatched, dotted, barred. A breakdown in five hues is a chart to be
    /// decoded; the same breakdown in five weaves is read in order.
    static let accent   = duo(0xC2510D, 0xE2721C)
    static let onAccent = duo(0xFFFFFF, 0xFFFFFF)
    /// The two steps down from it, for a breakdown that wants three.
    static let accentMid  = duo(0xE8761F, 0xC9631A)
    static let accentSoft = duo(0xF6B183, 0x8F4715)
    /// Better than it was. The only other colour in the window, and it is
    /// never the thing you look at first.
    static let better   = duo(0x1E9E63, 0x35B87A)
    /// A lift rather than a tint: the same light the card is made of, a
    /// little more of it.
    static let wash     = duo(0x000000, 0xFFFFFF).withAlphaComponent(0.05)

    /// A breakdown drawn in five hues is a chart to be decoded. Drawn as one
    /// light falling away it is the same reading, in order, and the eye
    /// starts at the biggest slice without being told to.
    static func band(_ i: Int) -> NSColor {
        switch i {
        case 0:  return accent
        case 1:  return accentMid
        case 2:  return accentSoft
        default: break
        }
        let steps: [CGFloat] = [0.34, 0.26, 0.20, 0.15, 0.11]
        return ink.withAlphaComponent(i - 3 < steps.count ? steps[i - 3] : 0.09)
    }

    /// The one button, and the words on it.
    static let strong = accent
    static let onStrong = onAccent
}

/// A plain rectangle of one of Kliner's colours, which repaints itself when
/// the Mac changes from light to dark. The window is built out of two of
/// these instead of two sheets of glass.
final class Surface: NSView {
    private let colour: NSColor
    private let round: CGFloat
    private let edged: Bool

    init(_ colour: NSColor, round: CGFloat = 0, edged: Bool = false) {
        self.colour = colour
        self.round = round
        self.edged = edged
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = round
        layer?.borderWidth = edged ? 1 : 0
        // A page scrolling inside a rounded card has to stop at the corner,
        // or the first line of it pokes out past the curve.
        layer?.masksToBounds = round > 0
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.colour.cgColor
            if self.edged { self.layer?.borderColor = Paint.line.cgColor }
        }
    }
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
    /// What one of this page's rows is, in a word. It is the caption under the
    /// count at the top of the page, and every page has one, so every page can
    /// say how many of them there are.
    let counts: String

    init(title: String, blurb: String, verb: String, arguments: [String],
         asks: String?, group: String, symbol: String, does: String = "play",
         counts: String = "things", extras: [Extra] = [], reveal: String? = nil,
         walks: Bool = false, looksOnly: Bool = true, symbolic: Bool = true) {
        self.title = title; self.blurb = blurb; self.verb = verb
        self.arguments = arguments; self.asks = asks; self.group = group
        self.symbol = symbol; self.extras = extras; self.reveal = reveal
        self.walks = walks; self.looksOnly = looksOnly; self.symbolic = symbolic
        self.does = does; self.counts = counts
    }

    /// One entry in the list down the side. Five places, not nine rows and
    /// four headings over them: a list you read is a list you can take in at
    /// a glance, and what is inside a place belongs on the place's own page.
    struct Place {
        let title: String
        let symbol: String
        /// Which of the things below live here, in the order they appear.
        let holds: [Int]
    }

    static let places: [Place] = [
        Place(title: "Home", symbol: "house", holds: [0]),
        Place(title: "Desk", symbol: "square.grid.2x2", holds: [1, 2]),
        Place(title: "Screen", symbol: "display", holds: [3, 4]),
        Place(title: "Disk", symbol: "internaldrive", holds: [5, 6]),
        Place(title: "Computer", symbol: "cpu", holds: [7, 8]),
    ]

    /// Which place a page belongs to.
    static func place(of index: Int) -> Place? {
        places.first { $0.holds.contains(index) }
    }

    /// Not one of the things nimo does, the place where you say how it
    /// should do them.
    static let help = Action(title: "Help",
                             blurb: "Every key Kliner answers to.",
                             verb: "",
                             arguments: [],
                             asks: nil,
                             group: "",
                             symbol: "questionmark.circle")

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
               counts: "things on your desktop",
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
               counts: "things in Downloads",
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
               counts: "wallpapers your Mac ships with",
               extras: [Extra(title: "Previous", arguments: ["prev"], asks: nil,
                              symbol: "chevron.left"),
                        Extra(title: "The one I had", arguments: ["wallpaper", "--restore"],
                              asks: nil, symbol: "arrow.uturn.backward")],
               looksOnly: false, symbolic: true),

        Action(title: "Startup",
               blurb: "What launches itself when you sign in, and which of them Kliner can turn off.",
               verb: "Look again",
               arguments: ["startup", "--list"],
               asks: nil,
               group: "Your screen",
               symbol: "power",
               does: "arrow.clockwise",
               counts: "things that launch themselves"),

        Action(title: "What is big",
               blurb: "The folders in your home that are taking up the room. Click one to look inside it.",
               verb: "Measure",
               arguments: ["top"],
               asks: nil,
               group: "Your disk",
               symbol: "chart.bar",
               does: "arrow.clockwise",
               counts: "folders in your home",
               walks: true),

        Action(title: "Free up space",
               blurb: "Caches and temporary files your apps rebuild by themselves. Your own files are never touched.",
               verb: "Free it up",
               arguments: ["clean"],
               asks: "Delete the caches and temporary files nimo found?\n\nYour own files are never touched.",
               group: "Your disk",
               symbol: "sparkles",
               does: "sparkles",
               counts: "caches your apps rebuild",
               extras: [Extra(title: "Only look", arguments: ["preview"], asks: nil, symbol: "eye")]),

        Action(title: "How it is",
               blurb: "Disk, memory, uptime and battery, as they are right now.",
               verb: "Check",
               arguments: ["doctor"],
               asks: nil,
               group: "Your computer",
               symbol: "waveform.path.ecg",
               does: "arrow.clockwise",
               counts: "readings"),

        Action(title: "Put it all back",
               blurb: "Everything nimo has done, reversed, newest first. This is why nothing here is frightening.",
               verb: "Put it all back",
               arguments: ["undo", "--all"],
               asks: "Reverse everything nimo has done, newest first?",
               group: "Your computer",
               symbol: "arrow.uturn.backward",
               does: "arrow.uturn.backward",
               counts: "changes Kliner can reverse",
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
    /// The answer comes back on whatever thread macOS feels like, so it is
    /// handed on from the main one — the setup page draws itself with it.
    static func ask(_ then: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { yes, _ in
                DispatchQueue.main.async { then(yes) }
            }
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

    /// A click lands on whatever is under the mouse, and what is under the
    /// mouse here is the picture. NSImageView is an NSControl, and NSControl
    /// eats mouseDown rather than handing it up — so without this, pressing
    /// the middle of a button does nothing and only its margin works.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
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
    /// Every face Kliner has, by the name of its file. `""` is the one it
    /// wears; the rest are the ones it puts on for a moment and takes off.
    ///
    /// Three frames to shut an eye, not two: open, half, shut reads as an eye
    /// closing, where two frames read as a flicker.
    private static let faces = ["", "-half", "-blink", "-left", "-right",
                                "-round", "-dash"]

    private var pending: Timer?
    private var folded = false
    private var worn = ""

    init() {
        super.init(frame: .zero)
        // Every one of them is a template: macOS draws the shape in the colour
        // of the text beside it, so the face is never a black blob.
        for base in ["wordmark", "mascot"] {
            for face in Wordmark.faces {
                NSImage(named: base + face)?.isTemplate = true
            }
        }
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignLeft
        translatesAutoresizingMaskIntoConstraints = false
        wear("")
        later()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    deinit { pending?.invalidate() }

    /// Folded down to a rail there is no room for a word, so the face goes
    /// there instead, and it wears the same faces.
    func fold(_ yes: Bool) {
        folded = yes
        imageAlignment = yes ? .alignCenter : .alignLeft
        wear(worn)
    }

    private func wear(_ face: String) {
        // The word's quotes have a letter right behind them, so it cannot look
        // to the left. The face has room either side.
        var want = face
        if !folded, face == "-left" { want = "-right" }
        worn = want
        image = NSImage(named: (folded ? "mascot" : "wordmark") + want)
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

    /// The whole turn: eyes shut, eyes round, eyes a pair of dashes, eyes shut
    /// again, and back to the quotes it started with. Sixty milliseconds a
    /// step for the shutting, and a beat on each face it puts on, which is the
    /// difference between a thing with a face and a thing with a picture of
    /// one.
    private func blink() {
        guard window != nil, worn == "" else { later(); return }
        wear(Bool.random() ? "-left" : "-right")
        walk([("-half", 0.06), ("-blink", 0.06), ("-blink", 0.07),
              ("-round", 0.42),
              ("-dash", 0.38),
              ("-blink", 0.07), ("-half", 0.06), ("", 0)]) { [weak self] in
            self?.later()
        }
    }

    private func walk(_ steps: [(String, Double)], then: @escaping () -> Void) {
        guard let (face, wait) = steps.first else { then(); return }
        wear(face)
        if steps.count == 1 { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.walk(Array(steps.dropFirst()), then: then)
        }
    }
}

// MARK: - a row down the side

/// A name, and under it three quiet words saying what it is. No box, no
/// border — just a soft fill when it is the one you are on.
final class Row: NSView {
    let index: Int
    var onClick: ((Int) -> Void)?
    /// Pressing the chevron opens or shuts what is inside this place.
    var onFold: (() -> Void)?

    /// A search did not match this row.
    var ruledOut = false
    /// The place this row is inside is shut.
    var shutAway = false

    private let name = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let count = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    /// Whether this row has anything under it to open and shut.
    private var canFold = false
    /// A row for one of the things inside a place, indented under it.
    private let under: Bool
    private var chosen = false
    private var inside = false
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
        count.isHidden = yes || count.stringValue.isEmpty
        // A chevron on a row 38 points wide is a chevron under every click,
        // and the row would open and shut instead of opening its page.
        chevron.isHidden = yes || !canFold
        atLeft.isActive = !yes
        inMiddle.isActive = yes
        wide.constant = yes ? 38 : 214
        toolTip = yes ? name.stringValue : nil
    }

    /// A row for one of the things inside a place has nothing to say at a
    /// rail's width: the place above it is already there.
    var isUnder: Bool { under }

    convenience init(_ item: Action, index: Int) {
        self.init(item.title, symbol: item.symbol, index: index)
    }

    init(_ title: String, symbol: String, index: Int, under: Bool = false) {
        self.index = index
        self.under = under
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        if let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            icon.image = picture
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        name.stringValue = title
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        // How many things are in there, the way every list down the side of a
        // window says it: quietly, at the right-hand end of the row.
        count.font = Words.tiny
        count.alignment = .right
        count.isHidden = true
        count.translatesAutoresizingMaskIntoConstraints = false
        addSubview(count)

        // And, on a place that holds more than one thing, the chevron that
        // opens and shuts it. Every list of this shape has one, and without
        // it thirteen rows is thirteen rows whether you want them or not.
        chevron.isHidden = true
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        // The width of the list, not a little less than it: a row 190 wide
        // in a list 214 wide leaves 24 points of nothing at the right-hand
        // end of every row, which is where the count and the chevron go.
        wide = widthAnchor.constraint(equalToConstant: 214)
        atLeft = icon.leadingAnchor.constraint(equalTo: leadingAnchor,
                                               constant: under ? 32 : 10)
        inMiddle = icon.centerXAnchor.constraint(equalTo: centerXAnchor)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: under ? 32 : 34),
            wide,
            atLeft,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: under ? 13 : 15),
            icon.heightAnchor.constraint(equalToConstant: under ? 13 : 15),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor,
                                           constant: Step.tight),
            count.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 9),
            chevron.heightAnchor.constraint(equalToConstant: 9),
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
    /// The chevron opens and shuts what is inside this place; the rest of
    /// the row goes to the page it names.
    override func mouseDown(with event: NSEvent) {
        let at = convert(event.locationInWindow, from: nil)
        if !chevron.isHidden, onFold != nil, at.x > chevron.frame.minX - 8 {
            onFold?()
            return
        }
        onClick?(index)
    }

    /// The picture and the words are controls of their own, and a control eats
    /// the click it is given. This view is the button; nothing inside it is.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    func choose(_ yes: Bool) { chosen = yes; repaint() }

    /// The page you are on lives in here, but is not this row. A place with
    /// its things listed under it does not take the fill as well — the fill
    /// belongs to the one row you are actually standing on.
    func within(_ yes: Bool) { inside = yes; repaint() }

    /// How many things are in the place this row opens. Nothing, when nobody
    /// has counted yet — a zero somebody has not measured is a lie.
    func holds(_ many: String?) {
        count.stringValue = many ?? ""
        count.isHidden = (many ?? "").isEmpty
        repaint()
    }

    /// This place can be opened and shut, and this is which it is.
    func folds(_ open: Bool) {
        let picture = NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right",
                              accessibilityDescription: nil)
        picture?.isTemplate = true
        chevron.image = picture
        canFold = true
        chevron.isHidden = name.isHidden
        repaint()
    }

    /// Whether this row is on the screen at all. A search can rule it out,
    /// the place it is inside can be shut, and a list folded to a rail has
    /// room for the places and nothing under them.
    func settle(_ narrowed: Bool) {
        isHidden = ruledOut || (under && (shutAway || narrowed))
    }

    private func repaint() {
        let lit = chosen || inside
        name.textColor = lit ? Paint.ink : Paint.muted
        name.font = lit ? Words.strong : Words.body
        icon.contentTintColor = chosen ? Paint.accent : Paint.faint
        count.textColor = Paint.faint
        chevron.contentTintColor = Paint.faint

        // A grey pill behind the page you are on says in a second way what
        // the darker word already says. The lift is not a second way: it is
        // the one mark in the window for where you are, the same lift the
        // button for the thing to do next is made of.
        var background = NSColor.clear
        if chosen { background = Paint.wash }
        if hovering && !chosen { background = Paint.hover }
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

        label.font = Words.strong
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

    /// What it says, so it can be told again without being told what it says.
    private(set) var words = ""

    func set(_ words: String, live able: Bool = true) {
        live = able
        self.words = words
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

    /// The picture and the words are controls of their own, and a control eats
    /// the click it is given. This view is the button; nothing inside it is.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

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

/// A labelled line to type on, the way every one of those flows asks for
/// anything: the label above it in small grey, the field under it, and a word
/// of help beneath when the field needs one.
///
/// The setup is a form now. It was four pages of prose about what Kliner is,
/// which is a thing to sit through; these ask you three questions and set the
/// app up out of the answers.
final class Ask: NSView {
    private let field = NSTextField()
    private let note = NSTextField(labelWithString: "")

    var text: String {
        get { field.stringValue.trimmingCharacters(in: .whitespaces) }
        set { field.stringValue = newValue }
    }

    init(_ label: String, hint: String, note detail: String = "", wide: CGFloat = 320) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: label)
        name.font = Words.small
        name.textColor = Paint.muted
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        field.placeholderString = hint
        field.font = Words.body
        field.textColor = Paint.ink
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 9
        field.layer?.borderWidth = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        note.stringValue = detail
        note.font = Words.small
        note.textColor = Paint.faint
        note.isHidden = detail.isEmpty
        note.translatesAutoresizingMaskIntoConstraints = false
        addSubview(note)

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.topAnchor.constraint(equalTo: topAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 7),
            field.widthAnchor.constraint(equalToConstant: wide),
            field.heightAnchor.constraint(equalToConstant: 34),
            note.leadingAnchor.constraint(equalTo: leadingAnchor),
            note.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 7),
            note.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            note.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.field.layer?.backgroundColor = Paint.track.cgColor
            self.field.layer?.borderColor = Paint.line.cgColor
        }
    }

    func focus() { window?.makeFirstResponder(field) }
}

/// One answer among a few, as a row you press rather than a menu you open.
/// Three choices in a menu is three clicks to see two words.
final class Choice: NSView {
    private let mark = NSView()
    private var picked = false
    var onPick: (() -> Void)?

    let value: String

    init(_ value: String, title: String, note: String) {
        self.value = value
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Panel.dress(self)

        mark.wantsLayer = true
        mark.layer?.cornerRadius = 7
        mark.layer?.borderWidth = 1.5
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        let name = NSTextField(labelWithString: title)
        name.font = Words.strong
        name.textColor = Paint.ink
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        let under = NSTextField(labelWithString: note)
        under.font = Words.small
        under.textColor = Paint.faint
        under.translatesAutoresizingMaskIntoConstraints = false
        addSubview(under)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 14),
            mark.heightAnchor.constraint(equalToConstant: 14),
            name.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 13),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            under.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            under.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            under.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
        ])
        choose(false)
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    func choose(_ yes: Bool) {
        picked = yes
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = yes ? Paint.ink.cgColor : Paint.line.cgColor
            ease(self.layer, to: yes ? Paint.wash : NSColor.clear)
            self.mark.layer?.borderColor = yes ? Paint.ink.cgColor : Paint.line.cgColor
            self.mark.layer?.backgroundColor = yes ? Paint.ink.cgColor : NSColor.clear.cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onPick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        choose(picked)
    }
}

final class Setting: NSView {
    init(_ label: String, control: NSView) {
        super.init(frame: .zero)

        let name = NSTextField(labelWithString: label)
        name.font = Words.body
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

    private let titleLabel = Trail()
    private let scroll     = Pages()
    private let report     = NSStackView()
    private var rows: [Row] = []
    private var settingsRow: Row!
    private let buttons = NSStackView()
    private var railWidth: NSLayoutConstraint!
    private var stackWidth: NSLayoutConstraint!
    private var markWidth: NSLayoutConstraint!
    private var sideStack: NSStackView!
    /// The list itself, which scrolls, and what it scrolls inside.
    private var listStack: NSStackView!
    private var listScroll: NSScrollView!
    private var listWidth: NSLayoutConstraint!
    /// The rows for the things inside a place, which go when the list folds.
    private var kids: [Row] = []
    /// The places somebody has shut, by the index of the first thing in them.
    private var shut: Set<Int> = []
    /// The word over the list, which goes when the list folds to its pictures.
    private var sideHeading: NSView!
    private var wordmark: Wordmark!
    private var groupLabels: [NSTextField] = []
    private var narrow = false

    /// Two things the row along the top says about the window as a whole,
    /// rather than about the page you happen to be on.
    private var agePill: Pill!
    private var modePill: Pill!
    private var lastRead: Date?
    private var ageTimer: Timer?
    /// When on, the buttons on every page read instead of doing. Not a label
    /// on a promise: `go` takes a different path, so there is no path left
    /// that changes a file while it is on.
    private var previewOnly = false
    private var welcoming = false
    /// The rows on the asking page, so each can be told what macOS said
    /// without the page being drawn again underneath them.
    /// The setup's own furniture: the face and the line about it down the
    /// rail, and the two buttons in the corners of the pane. Taken off the
    /// scrolling page, because a page that scrolls cannot hold anything in a
    /// corner, and all three flows this follows put them in one.
    private var aside: NSStackView!
    private var asideWords: Wrapping!
    private var onward: NSStackView!
    private var marker: Marker?
    /// What the setup has been told. Written to ~/.nimo/config when it
    /// finishes, which is the same file the CLI reads, so answering these
    /// changes what both of them do.
    private var callMe = ""
    private var startWith = "desktop"
    private var tidyName = "Tidy"
    private var atLogin = false
    private var nameField: Ask?
    private var tidyField: Ask?
    private var choices: [Choice] = []
    private var showing: Walk?
    private var undoing: Undoing?
    private var asking: [Told] = []
    /// What macOS said, kept so the page can be drawn again with the answers
    /// still on it. Drawing it again is what puts the way on underneath.
    private var answers: [(String, String, Bool)] = []
    private var asked = false
    private var step = 0
    /// Which step was showing, so a page knows which side it is arriving from.
    private var last = 0
    /// Which side the next page comes in from: -1 the left, 1 the right, 0
    /// straight down. Going back is going left, whatever number the page you
    /// are going back to happens to have.
    private var came: CGFloat = 0
    private var foldButton: Ghost!
    private var backButton: Ghost!
    private var onButton: Ghost!
    private var chrome: NSStackView!
    /// The line under the card: what Kliner is doing, and the way to ask again.
    private var strip: Strip!
    private var chromeLeading: NSLayoutConstraint!
    private var search: Seek!
    private var titleLeading: NSLayoutConstraint!
    private var titleCentre: NSLayoutConstraint!
    private var footStack: NSStackView!
    private var railLine: NSBox!
    private var barLine: NSBox!
    private var primary: Chip!
    private var helper: Helper!
    /// What Kliner was asked to do, in order, one at a time.
    private var queue: [Int] = []
    /// Whether the run that is finishing put the waiting face up.
    private var waited = false
    /// Whether a queue was worked through, so the end of it goes back to Home.
    private var ran = false
    private var mascot: Floating?

    /// Which setup has been read. Bumped whenever the setup changes, so a
    /// setup nobody has seen is shown once more rather than never again.
    static let setup = "4"

    /// What macOS decides about, in the order it is asked. Notifications are
    /// last on purpose: a banner is the smallest thing to be asked for, and
    /// asking for it first teaches nothing about the folders.
    private static func inHome(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
    }
    /// Which page an answer opens. Matched on the page's own arguments, so a
    /// page added later needs nothing changed here as well.
    static func page(for start: String) -> Int {
        for (i, item) in Action.all.enumerated()
            where item.arguments.first == start { return i }
        for (i, item) in Action.all.enumerated()
            where item.title == "What is big" && start == "disk" { return i }
        return 0
    }

    /// What Home can open on. The value is the page's own first argument, so
    /// nothing has to be translated between here and the list down the side.
    static let starts: [(String, String, String)] = [
        ("desktop", "My desktop", "Sorted into one folder by what things are."),
        ("downloads", "My downloads", "The same, for the folder everything lands in."),
        ("disk", "Whatever is taking the room", "The big things first, and what is safe to clear."),
    ]

    private static let gates: [(String, String, URL?)] = [
        ("menubar.dock.rectangle", "Your desktop", Access.desktop),
        ("arrow.down.circle", "Your downloads", Access.downloads),
        ("photo", "Your pictures", inHome("Pictures")),
        ("doc.text", "Your documents", inHome("Documents")),
        ("bell", "Notifications", nil),
    ]
    private var behind: [Int] = []          // pages you came from
    private var ahead: [Int] = []           // pages you came back from
    private var walked: [String] = []       // how far into your home you have clicked

    private var chosen = 0
    private var busy = false
    /// The row of quiet actions under the top bar. It is built once with
    /// whether Kliner was busy at that moment, and nothing held on to it, so
    /// when the run finished the row stayed grey and stayed unclickable until
    /// the page was drawn again. That is most of "nothing works".
    private var offered: [Chip] = []
    private var seen: Set<Int> = []
    /// What each page last said. Coming back to a page you have already opened
    /// redraws that, rather than walking your home folder again to be told the
    /// same thing.
    private var kept: [Int: [Piece]] = [:]
    /// Home is a reading of a machine that keeps changing, so it takes the
    /// reading again while you are looking at it.
    private var ticking: Timer?

    override init() {
        // Wide enough for the column of work to be its full width beside
        // the list, and tall enough for Home to be one screen rather than
        // half of one. A window that opens on half a page is a window that
        // asks you to resize it before you can read it.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        super.init()

        window.title = "Kliner"
        // Kliner is drawn as a light window — a grey page with paler cards on
        // it and one warm colour. Handed to a Mac in dark mode it would come
        // out as a different design wearing the same layout, so it asks for
        // the light one whatever the system is set to. Every colour in Paint
        // still has its dark half, ready for the day this becomes a choice.
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // No glass. A veil over the blur was supposed to stop the wallpaper's
        // colour reaching the page, and it did not: inside a vibrant
        // NSVisualEffectView macOS blends what stands on it with the material
        // behind, so a cool grey list still went brown over a warm photograph.
        // Depth is not worth a window that changes colour with the desktop.
        window.isOpaque = true
        window.backgroundColor = Paint.veil
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 520)
        window.delegate = self
        _ = window.setFrameAutosaveName("nimo.main")

        build()
        listen()
        window.center()
    }

    /// What the window shows, once it is actually on the screen.
    ///
    /// This used to happen in init, which runs before the window has been
    /// ordered front. The whole opening — the face coming up out of nothing,
    /// the words landing one at a time — played to an empty screen, and what
    /// you were finally shown was the last frame of it. Every complaint about
    /// the start was a complaint about never having seen it.
    func open() {
        // A rail of pictures is the shape this window was drawn as, and with
        // ⌘K answering from anywhere there is no longer much for a column of
        // names to do. ⌘B opens it, and the choice is remembered.
        if Config.value("rail") != "list" { fold(true, animated: false) }
        if Config.value("preview") == "on" {
            previewOnly = true
            modePill.lit(true)
        }
        // Every few seconds, because "scanned 12s ago" that still says 12s a
        // minute later is worse than not saying it at all.
        ageTimer?.invalidate()
        ageTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.sayAge()
        }

        if Config.value("welcomed") != Main.setup {
            welcoming = true
            for row in rows { row.choose(false) }
            drawWelcome()          // each step sets its own title
        } else {
            show(0)
        }
    }

    /// Home again, quietly, every half minute.
    ///
    /// A page saying how much room is left on a disk is out of date the moment
    /// it is drawn. It reads again while you are looking at it, but only while
    /// you are looking at it, and never while something else is running, so
    /// nothing ever moves under your hand.
    private func tick() {
        ticking?.invalidate()
        ticking = nil
        guard chosen == 0, isPage else { return }
        ticking = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
            [weak self] _ in
            guard let self = self else { return }
            guard self.chosen == 0, !self.busy, !self.welcoming,
                  self.window.isVisible, self.window.occlusionState.contains(.visible)
            else { return }
            self.kept[0] = nil
            self.run(Action.all[0], quietly: true)
        }
    }

    /// Up and down move through the list. A window you can only work with a
    /// mouse is a window somebody has not finished, and arrow keys are not
    /// something a menu can hold without taking them from every text field in
    /// the app, so this takes them only when nothing is being typed into and
    /// no modifier is held.
    private func listen() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.window else { return event }
            if self.window.firstResponder is NSTextView { return event }
            guard event.modifierFlags
                .intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            switch event.keyCode {
            case 125: self.walkList(1);  return nil     // down
            case 126: self.walkList(-1); return nil     // up
            default:  return event
            }
        }
    }

    // MARK: building it

    private func build() {
        let ground = Surface(Paint.veil)
        // Surface turns the autoresizing mask off, because everything else in
        // the window is laid out with constraints. A content view is not: the
        // window sets its frame directly, and one with the mask off and no
        // constraints of its own collapses to nothing.
        ground.translatesAutoresizingMaskIntoConstraints = true
        ground.autoresizingMask = [.width, .height]
        window.contentView = ground
        let content: NSView = ground

        // First thing in, so everything else stands on it: the slate that
        // stops the wallpaper's colour coming through the blur.
        let veil = Surface(Paint.veil)
        content.addSubview(veil)
        NSLayoutConstraint.activate([
            veil.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            veil.topAnchor.constraint(equalTo: content.topAnchor),
            veil.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // The work sits on one card, inset from the window's edges and round
        // at the corners. The list is not on it: the list is on the glass, and
        // the card is the page.
        let pane = Surface(Paint.card, round: 18, edged: true)
        content.addSubview(pane)

        // The list stands on its own slate.
        //
        // It used to stand on whatever the window's background happened to
        // be, and over a warm wallpaper that came out a warm grey — the brown
        // everybody could see and which no colour in this file could account
        // for, because none of them is warm. Taking the glass away was not
        // enough. This is opaque and it is the list's own, so there is
        // nothing behind it to come through.
        let slate = Surface(Paint.rail)
        content.addSubview(slate)
        NSLayoutConstraint.activate([
            slate.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            slate.topAnchor.constraint(equalTo: content.topAnchor),
            slate.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            slate.trailingAnchor.constraint(equalTo: pane.leadingAnchor),
        ])

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
        stack.setCustomSpacing(Step.close, after: mark)

        // The way to find a page belongs with the pages: under the mark, the
        // width of the list. In the row along the top it sat between the
        // chrome and the name of the page, which is nothing to do with either.
        let seek = Seek()
        seek.onType = { [weak self] words in self?.sieve(words) }
        seek.onGo = { [weak self] in self?.openFirstMatch() }
        search = seek
        stack.addArrangedSubview(seek)
        seek.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(Step.wide, after: seek)


        // The list scrolls. It is thirteen rows at a rhythm somebody can
        // read, and a window is as short as somebody drags it — pinned to the
        // top with Settings pinned to the bottom, the two used to meet in the
        // middle and stand on each other.
        let listed = NSStackView()
        listed.orientation = .vertical
        listed.alignment = .leading
        listed.spacing = 3
        listed.translatesAutoresizingMaskIntoConstraints = false

        let rolling = NSScrollView()
        rolling.drawsBackground = false
        rolling.backgroundColor = .clear
        rolling.borderType = .noBorder
        rolling.hasVerticalScroller = true
        rolling.autohidesScrollers = true
        rolling.scrollerStyle = .overlay
        rolling.contentView = TopClip()
        rolling.documentView = listed
        rolling.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rolling)
        listScroll = rolling
        listStack = listed

        // The list has a name over it, the way every list down the side of a
        // window does: small, spaced, in capitals, so it reads as a label on
        // the list rather than as the first row of it.
        let heading = Panel.label("Places")
        let headRoom = NSView()
        headRoom.translatesAutoresizingMaskIntoConstraints = false
        headRoom.addSubview(heading)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: headRoom.leadingAnchor, constant: 10),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: headRoom.trailingAnchor),
            heading.topAnchor.constraint(equalTo: headRoom.topAnchor),
            heading.bottomAnchor.constraint(equalTo: headRoom.bottomAnchor, constant: -Step.tight),
        ])
        listed.addArrangedSubview(headRoom)
        headRoom.widthAnchor.constraint(equalTo: listed.widthAnchor).isActive = true
        sideHeading = headRoom

        // Five places, each opening on the first of the things it holds. What
        // else is in a place is under the name of the one you are on, which
        // is one list to read instead of nine rows under four headings.
        for place in Action.places {
            guard let first = place.holds.first else { continue }
            let row = Row(place.title, symbol: place.symbol, index: first)
            row.onClick = { [weak self] which in self?.show(which) }
            listed.addArrangedSubview(row)
            rows.append(row)

            // And what is inside it, under it. It used to be reachable only
            // through a chevron on the name of the page you were already on,
            // which is a door with the handle on the inside: you had to be in
            // the room to find out the room had another one.
            guard place.holds.count > 1 else { continue }
            row.folds(true)
            row.onFold = { [weak self] in self?.foldPlace(first) }
            for which in place.holds {
                let item = Action.all[which]
                let kid = Row(item.title, symbol: item.symbol, index: which, under: true)
                kid.onClick = { [weak self] one in self?.show(one) }
                listed.addArrangedSubview(kid)
                rows.append(kid)
                kids.append(kid)
            }
        }

        // Settings and Help are not things nimo does, so they do not stand in
        // the same list. They wait at the bottom, under a hairline, where
        // every Mac keeps its gear.
        let feet = NSStackView()
        feet.orientation = .vertical
        feet.alignment = .leading
        feet.spacing = 2
        feet.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(feet)
        footStack = feet

        settingsRow = Row(Action.settings, index: Action.all.count)
        settingsRow.onClick = { [weak self] _ in self?.show(Action.all.count) }
        feet.addArrangedSubview(settingsRow)
        rows.append(settingsRow)

        let helpRow = Row(Action.help, index: Action.all.count + 1)
        helpRow.onClick = { [weak self] _ in self?.show(Action.all.count + 1) }
        feet.addArrangedSubview(helpRow)
        rows.append(helpRow)

        let foot = NSBox()
        foot.boxType = .custom
        foot.borderWidth = 0
        foot.fillColor = Paint.line
        foot.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(foot)
        NSLayoutConstraint.activate([
            foot.leadingAnchor.constraint(equalTo: feet.leadingAnchor, constant: 11),
            foot.widthAnchor.constraint(equalTo: settingsRow.widthAnchor, constant: -22),
            foot.bottomAnchor.constraint(equalTo: feet.topAnchor, constant: -Step.close),
            foot.heightAnchor.constraint(equalToConstant: 1),
        ])

        // ---- the page ----------------------------------------------------
        // One hairline in the whole window, between the list and the work.
        // The row along the top is not a strip of its own: it is the top of
        // the two surfaces, so it needs no line under it and no line in it.
        // Where the list stops and the page starts. It used to be drawn as a
        // hairline; the card has an edge of its own now, so this is only the
        // line everything is measured from.
        let edge = NSBox()
        edge.boxType = .custom
        edge.borderWidth = 0
        edge.fillColor = .clear
        edge.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(edge)
        railLine = edge

        // And one across, under the row along the top, so the page has a
        // header rather than a name floating over its first line. It stops at
        // the list, because the list is its own surface and a line drawn over
        // both of them turns the window into a grid of boxes.
        let under = NSBox()
        under.boxType = .custom
        under.borderWidth = 0
        under.fillColor = .clear
        under.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(under)
        barLine = under

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

        titleLabel.onClick = { [weak self] in self?.offerSiblings() }
        content.addSubview(titleLabel)

        // Under the card, on the glass: a line saying what Kliner is doing
        // and a way to ask again. Quiet enough to ignore, there when you look.
        let line = Strip()
        line.onAgain = { [weak self] in self?.refresh() }
        strip = line
        content.addSubview(line)



        // The right of the row is one thing: on the pages that do something,
        // the one thing that page is for. Kliner himself is in the corner of
        // the page below, and one of him is enough.
        let doIt = Chip(.strong)
        doIt.onClick = { [weak self] in self?.go() }
        primary = doIt

        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = Step.tight
        buttons.translatesAutoresizingMaskIntoConstraints = false
        // How old the reading is. A page of figures about a disk is out of
        // date the moment it is drawn, and a window that does not say so is a
        // window quietly asking to be believed.
        let age = Pill("")
        age.isHidden = true
        agePill = age
        buttons.addArrangedSubview(age)

        // And whether the buttons are allowed to do anything.
        let mode = Pill("Preview only", strong: previewOnly)
        mode.toolTip = "Read, never change"
        mode.onClick = { [weak self] in self?.flipPreview() }
        modePill = mode
        buttons.addArrangedSubview(mode)

        buttons.addArrangedSubview(doIt)
        content.addSubview(buttons)


        // Kliner, in the corner of the page, waiting to be given something to
        // do. Over the work rather than in it, so it is there whatever page
        // you are on and however far down it you have scrolled.
        let sitting = Helper()
        sitting.onClick = { [weak self] in self?.showActivity() }
        helper = sitting
        content.addSubview(sitting)

        // The rail during the setup: the face, and under it at the bottom the
        // one line about what this is. Open Analytics parks a quote down
        // there, Kaelor parks its welcome; the corner of the rail is where a
        // thing that is not the step itself belongs.
        let side = NSStackView()
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = Step.close
        side.isHidden = true
        side.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(side)
        aside = side

        let told = Wrapping(labelWithString: "")
        told.maximumNumberOfLines = 0
        told.lineBreakMode = .byWordWrapping
        told.translatesAutoresizingMaskIntoConstraints = false
        side.addArrangedSubview(told)
        told.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
        asideWords = told

        // Back on the left of the pane's bottom edge, the one thing to press
        // on the right of it. Not floating in the middle of the page under
        // whatever the page happens to be showing.
        let ahead = NSStackView()
        ahead.orientation = .horizontal
        ahead.alignment = .centerY
        ahead.spacing = Step.tight
        ahead.isHidden = true
        ahead.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(ahead)
        onward = ahead

        scroll.onBack = { [weak self] in self?.swipedBack() }
        scroll.onForward = { [weak self] in self?.swipedOn() }
        scroll.contentView = TopClip()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        report.orientation = .vertical
        // In the middle of the card, not against its left edge. Measured off
        // the picture: the column is about eight hundred points wide with a
        // margin either side of it, which is what stops a wide window from
        // being one long line of text and a great deal of nothing.
        report.alignment = .centerX
        report.spacing = 0
        // Room at the bottom for him to sit without anything under him.
        report.edgeInsets = NSEdgeInsets(top: Step.hair, left: Step.wide,
                                         bottom: 72, right: Step.wide)
        report.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = report

        railWidth = edge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 246)
        // Past the three lights when the list is open; past the rail when it
        // is shut, so nothing ever sits on top of anything.
        // The last light ends at x = 72; four points of air after it.
        chromeLeading = chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 76)
        stackWidth = stack.widthAnchor.constraint(equalToConstant: 214)

        // The tab stands at the left edge of the page it names, the way a tab
        // does. Centred in the row it read as a window title, which is what
        // the title bar behind it already is.
        titleCentre = titleLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor)
        titleCentre.priority = .defaultHigh
        titleLeading = titleLabel.leadingAnchor.constraint(equalTo: edge.trailingAnchor)
        titleLeading.priority = .defaultLow

        listWidth = rolling.widthAnchor.constraint(equalToConstant: 214)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Step.air),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Step.bar + Step.close),
            stackWidth,

            // Between the search and the hairline over Settings, and it
            // scrolls if the window is too short to hold all of it.
            rolling.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            rolling.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: Step.air),
            rolling.bottomAnchor.constraint(equalTo: foot.topAnchor, constant: -Step.close),
            listWidth,

            listed.leadingAnchor.constraint(equalTo: rolling.contentView.leadingAnchor),
            listed.trailingAnchor.constraint(equalTo: rolling.contentView.trailingAnchor),
            listed.topAnchor.constraint(equalTo: rolling.contentView.topAnchor),

            feet.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            feet.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                         constant: -Step.air),

            // One card, inset from three edges of the window and starting
            // under the row along the top. The row is not a strip of its own:
            // it is the glass above the card, with the lights in it.
            pane.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            pane.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                           constant: -Step.tight),
            pane.topAnchor.constraint(equalTo: content.topAnchor,
                                      constant: Step.crown),
            pane.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                         constant: -Step.page),

            strip.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            strip.topAnchor.constraint(equalTo: pane.bottomAnchor),
            strip.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            railWidth,
            edge.topAnchor.constraint(equalTo: content.topAnchor),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            chromeLeading,
            // A 26 point button whose middle is on the lights' line starts at
            // 13 minus 13. Everything else in the row hangs off this one.
            chrome.centerYAnchor.constraint(equalTo: content.topAnchor,
                                            constant: Step.lights),

            // The bell is inside this row now, so the row is what is pinned.
            // Pinning the row to the bell inside it is a loop, and a loop is
            // a layout that quietly throws everything away.
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                              constant: -Step.air),
            buttons.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),

            titleCentre,
            titleLeading,
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chrome.trailingAnchor,
                                                constant: Step.air),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor,
                                                 constant: -Step.air),
            // Hanging off the bar onto the page: its bottom is inside the
            // card's top edge, so the two read as one shape.
            titleLabel.bottomAnchor.constraint(equalTo: pane.topAnchor, constant: 1),

            side.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Step.air),
            side.trailingAnchor.constraint(equalTo: edge.leadingAnchor, constant: -Step.air),
            side.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Step.wide),

            ahead.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: Step.edge),
            ahead.trailingAnchor.constraint(equalTo: pane.trailingAnchor,
                                            constant: -Step.edge),
            ahead.bottomAnchor.constraint(equalTo: pane.bottomAnchor,
                                          constant: -Step.air),

            // Kliner sits in the bottom right corner of the card, inside it,
            // not in the corner of the window under it.
            sitting.trailingAnchor.constraint(equalTo: pane.trailingAnchor,
                                              constant: -Step.air),
            sitting.bottomAnchor.constraint(equalTo: pane.bottomAnchor,
                                            constant: -Step.air),

            // The line the page's first words stand on, kept as a measure
            // now that the card's own edge is what you can see.
            under.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            under.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            under.topAnchor.constraint(equalTo: pane.topAnchor),
            under.heightAnchor.constraint(equalToConstant: 1),

            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: pane.topAnchor, constant: Step.air),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -1),

            report.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            report.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            report.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
    }

    // MARK: drawing what nimo said

    /// One thing down the page, in a column. Text that runs the whole width of
    /// a wide window is text nobody finishes a line of, so the column stops.
    private func line(_ view: NSView, inset: CGFloat = Step.wide * 2) {
        view.translatesAutoresizingMaskIntoConstraints = false
        report.addArrangedSubview(view)
        let full = view.widthAnchor.constraint(equalTo: report.widthAnchor, constant: -inset)
        full.priority = .defaultHigh
        full.isActive = true
        view.widthAnchor.constraint(lessThanOrEqualToConstant: Main.column).isActive = true
    }

    /// As wide as the work ever gets.
    static let column: CGFloat = 820

    private func words(_ text: String, _ font: NSFont, _ colour: NSColor,
                       top: CGFloat = Step.tight, bottom: CGFloat = Step.tight) {
        let field = Wrapping(labelWithString: text)
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.attributedStringValue = leaded(text, font, colour)
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
        harvest()
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // Nothing but the setup, until it is finished. The headline is under
        // the face, where the eye already is, so there is no page title, and
        // there is nothing else on the window to read instead.
        bare(true)

        // One face for the whole setup, not four. It stays put and leans over
        // whatever has just been written, which is what makes it read as
        // somebody showing you round. It lives in the rail rather than on the
        // page, so the page is the step and nothing else.
        let face = mascot ?? Floating(size: 56)
        let firstLook = mascot == nil
        mascot = face
        if face.superview !== aside {
            aside.insertArrangedSubview(face, at: 0)
        }
        asideWords.attributedStringValue =
            leaded("Four short pages, then I ask macOS for what I need. Nothing runs on your Mac until you press something.",
                   Words.small, Paint.faint)

        // How far in you are, at the top of the pane where the step is.
        let count = marker ?? Marker(of: 4)
        marker = count
        line(count)
        count.say(step)

        func headline(_ text: String) {
            words(text, Words.hero, Paint.ink, top: Step.close, bottom: Step.hair)
        }

        showing = nil
        undoing = nil

        switch step {
        case 0:
            headline("First, what should I call you?")
            words("It goes at the top of Home and nowhere else. Kliner has no account, and nothing about you leaves this Mac.",
                  Words.body, Paint.muted, top: 0, bottom: Step.air)
            let who = Ask("Your name", hint: "Daniel",
                          note: "Leave it blank and Home simply says hello.")
            who.text = callMe.isEmpty ? NSFullUserName() : callMe
            line(who)
            nameField = who

        case 1:
            headline("What should I start with?")
            words("Kliner takes you straight there when this is done. The other four are down the side whenever you want them.",
                  Words.body, Paint.muted, top: 0, bottom: Step.air)
            let five = Walk(Action.places)
            line(five)
            showing = five

            choices = []
            for (value, title, note) in Main.starts {
                let one = Choice(value, title: title, note: note)
                one.choose(value == startWith)
                one.onPick = { [weak self] in self?.pick(value) }
                line(one)
                choices.append(one)
            }

        case 2:
            headline("Where should things go?")
            words("Kliner never deletes. Everything it moves goes into one folder beside where it was, and Put it all back empties that folder again.",
                  Words.body, Paint.muted, top: 0, bottom: Step.air)
            let named = Ask("Folder name", hint: "Tidy",
                            note: "So a sorted desktop becomes Desktop/\(tidyName.isEmpty ? "Tidy" : tidyName).",
                            wide: 220)
            named.text = tidyName
            line(named)
            tidyField = named

            // The folder this page is naming, with things going into it and
            // coming back out. It is the page's own subject, moving.
            let back = Undoing()
            line(back)
            undoing = back

            if Login.possible {
                let toggle = NSSwitch()
                toggle.state = atLogin ? .on : .off
                toggle.target = self
                toggle.action = #selector(loginWanted(_:))
                line(Setting("Open Kliner when this Mac starts", control: toggle))
            }

        case 3:
            headline("One last thing, and it is yours to decide.")
            words("macOS decides what I may read, not me. One at a time, and only when you have answered does the next one come up.",
                  Words.body, Paint.muted, top: 0, bottom: Step.close)
            asking = []
            for (i, gate) in Main.gates.enumerated() {
                let row = Told(gate.0, gate.1, "waiting its turn")
                if i < answers.count {
                    row.say(answers[i].0, mark: answers[i].1, settled: answers[i].2)
                }
                line(row)
                asking.append(row)
            }

        default:
            break
        }

        // ---- the way through ---------------------------------------------
        // On the page, under what it has just said, not up in a row that is
        // hidden along with everything else. Words, because a picture of a
        // chevron is a thing to work out and this is somebody's first minute
        // with the app.
        let way = NSStackView()
        way.orientation = .horizontal
        way.alignment = .centerY
        way.spacing = Step.tight
        way.translatesAutoresizingMaskIntoConstraints = false

        // Nothing to press while macOS is asking: the pane is the rows, and
        // the way on appears when the last of them has an answer. Back sits in
        // the bottom-left corner of the pane and the one thing to press in the
        // bottom-right, rather than both floating in the middle of the page
        // under whatever the page happens to be showing.
        for view in onward.arrangedSubviews {
            onward.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if step > 0, step < 3 {
            let back = Chip(.quiet)
            back.set("Back")
            back.onClick = { [weak self] in
                guard let self = self else { return }
                self.step -= 1
                self.drawWelcome()
            }
            onward.addArrangedSubview(back)
        }

        // The slack between the two corners. A bare view has no size of its
        // own, so with the row pinned to both edges of the pane it is the one
        // thing that can grow, and it pushes Back left and the rest right.
        let slack = NSView()
        slack.translatesAutoresizingMaskIntoConstraints = false
        slack.setContentHuggingPriority(.init(1), for: .horizontal)
        slack.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        onward.addArrangedSubview(slack)

        if step == 2 {
            let skip = Chip(.quiet)
            skip.set("Skip for now")
            skip.onClick = { [weak self] in self?.openStart() }
            onward.addArrangedSubview(skip)
        }

        if step < 3 {
            let on = Chip(.strong)
            on.set(step < 2 ? "Next" : "Ask macOS")
            on.onClick = { [weak self] in
                guard let self = self else { return }
                if self.step < 2 {
                    self.step += 1
                    self.drawWelcome()
                    return
                }
                self.step = 3
                self.asked = false
                self.answers = []
                self.drawWelcome()
                self.askNext(0)
            }
            onward.addArrangedSubview(on)
        } else if asked {
            let start = Chip(.strong)
            start.set("Start")
            start.onClick = { [weak self] in self?.openStart() }
            onward.addArrangedSubview(start)
        }

        // The last page has one thing left to do, and the face is what asks
        // for it. On the pages before it, the thing to learn is that two
        // fingers turn the page, so the page says so, once, quietly.
        if step >= 2 {
            face.beckon()
        } else {
            face.relax()
            line(Nudge())
        }


        // Which side this page is coming from, and which way the head is
        // thrown by it. The head moves on its own clock; the words are the
        // page arriving. Those used to be one animation, and one animation is
        // why every page of the setup read as a new screen instead of
        // somebody turning to the next thing.
        let side: CGFloat = firstLook ? 0 : (step >= last ? 1 : -1)
        teach(side, first: firstLook)
        // The picture on a page counts itself in after the words that
        // introduce it, rather than sliding in with them as one more row.
        showing?.play(after: firstLook ? 0.62 : 0.30)
        undoing?.play(after: firstLook ? 0.62 : 0.30)
        if firstLook {
            face.arrive()
        } else if side == 0 {
            face.nod()
        } else {
            face.lean(side)
        }
        last = step
    }

    /// How a page of the setup arrives.
    ///
    /// The rest of the app settles down the page, a row at a time, which is
    /// right for a page of results. A page that is explaining something wants
    /// the other axis: the face first, then the headline, then each line under
    /// it coming in from the side it was going, further apart than the app's
    /// own rhythm, so it reads as somebody laying things out one at a time
    /// rather than a page appearing.
    private func teach(_ way: CGFloat, first: Bool) {
        report.layoutSubtreeIfNeeded()
        let start = CACurrentMediaTime() + 0.05
        var placed = 0

        for view in report.arrangedSubviews {
            view.wantsLayer = true

            // What was already here does not arrive again. The face is in the
            // rail and moves on its own clock; the step marker at the top of
            // the pane is furniture and holds still; a demonstration counts
            // itself in after the words that introduce it.
            if view === showing || view === undoing { continue }
            if view === marker {
                guard first else { continue }
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0
                show.toValue = 1
                show.duration = 0.3
                show.fillMode = .backwards
                view.layer?.add(show, forKey: "arriving")
                continue
            }

            // Out of the side you are travelling from, and up a little, so a
            // line lands rather than slides. The first line lands on its own;
            // everything under it follows a beat behind, close enough to read
            // as one movement and far enough apart to be counted.
            let across = CABasicAnimation(keyPath: "transform.translation.x")
            across.fromValue = 34 * way
            across.toValue = 0

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = placed == 0 ? -18 : (way == 0 ? -14 : -5)
            rise.toValue = 0

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            // The headline lands; everything under it slides in behind. A page
            // where every line does the same thing has no first beat, and a
            // page explaining something is nothing but beats.
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [0.94, 1.02, 1]
            swell.keyTimes = [0, 0.7, 1]

            let all = CAAnimationGroup()
            all.animations = placed == 0 ? [rise, swell, fade] : [across, rise, fade]
            all.duration = 0.52
            // The words wait for the face on the first page, and for the head
            // to have started moving on every page after it.
            all.beginTime = start + (first ? 0.34 : 0.10)
                + Double(min(placed, 9)) * 0.062
            all.fillMode = .backwards
            all.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.05, 0.3, 1)
            view.layer?.add(all, forKey: "arriving")
            placed += 1
        }
    }

    /// The setup, and nothing else. A window that shows you its list, its
    /// search and its buttons while it is still explaining itself is a window
    /// asking you to read two things at once.
    private func bare(_ yes: Bool) {
        for view: NSView? in [footStack, barLine, chrome, listScroll,
                              buttons, search, titleLabel, helper, strip] {
            view?.isHidden = yes
        }
        // The rail itself stays. It used to be folded away and the setup took
        // the whole window, which is a different app for four pages and then
        // yours. Kaelor and Open Analytics both keep their two panes through
        // the whole of it: the brand and a line about it down one side, the
        // step on the other. The window already had that shape.
        railLine?.isHidden = false
        aside?.isHidden = !yes
        onward?.isHidden = !yes
        Sheet.hide()
        railWidth.constant = narrow && !yes ? 70 : 246
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// The way out of the setup: the face, big, over the whole window, growing
    /// and fading as the app arrives underneath it. It is the last thing the
    /// setup does rather than the first thing it does, because a splash before
    /// anything has happened is a thing to sit through.
    private func curtain() {
        guard let over = window.contentView else { return }
        let big = NSImageView()
        let picture = NSImage(named: "mascot")
        picture?.isTemplate = true
        big.image = picture
        big.contentTintColor = Paint.ink
        big.imageScaling = .scaleProportionallyUpOrDown
        big.wantsLayer = true
        big.translatesAutoresizingMaskIntoConstraints = false
        over.addSubview(big)
        NSLayoutConstraint.activate([
            big.centerXAnchor.constraint(equalTo: over.centerXAnchor),
            big.centerYAnchor.constraint(equalTo: over.centerYAnchor),
            big.widthAnchor.constraint(equalToConstant: 180),
            big.heightAnchor.constraint(equalToConstant: 180),
        ])
        over.layoutSubtreeIfNeeded()

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.72
        grow.toValue = 2.4

        let go = CABasicAnimation(keyPath: "opacity")
        go.fromValue = 1
        go.toValue = 0

        let both = CAAnimationGroup()
        both.animations = [grow, go]
        both.duration = 0.72
        both.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        both.fillMode = .forwards
        both.isRemovedOnCompletion = false
        big.layer?.add(both, forKey: "leaving")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            big.removeFromSuperview()
        }
    }

    private func finishWelcome() {
        keep()
        welcoming = false
        mascot = nil
        bare(false)
        curtain()
        // Stamped with which setup was read, not just that one was. A setup
        // that grew a page is a setup nobody has seen, and the old `yes`
        // meant it was never shown again.
        Config.set("welcomed", Main.setup)
    }

    /// Home is the reading and then the list: how things stand across the top,
    /// what to do about it under that, and what is taking the room under that.
    ///
    /// The list is the point. Four figures tell you how your Mac is; a line
    /// you can press tells you what to do about it, which is what somebody
    /// opening a tidying app came for.
    private func drawHome(_ pieces: [Piece]) {
        var figures: [String: String] = [:]
        for piece in pieces {
            if case .row(let label, let value, _, _, _) = piece { figures[label] = value }
        }

        var total = 0.0, free = 0.0
        if let disk = figures["Disk"] {
            let parts = disk.components(separatedBy: " of ")
            free = bytes(parts.first?.replacingOccurrences(of: " free", with: "") ?? "") ?? 0
            total = parts.count > 1 ? (bytes(parts[1]) ?? 0) : 0
        }
        let junk = bytes(figures["Junk"] ?? "") ?? 0
        let used = max(0, total - free)
        let yours = max(0, used - junk)

        func count(_ key: String) -> Int {
            Int(figures[key]?.components(separatedBy: " ").first ?? "") ?? 0
        }

        func tally(_ many: Int) -> String? { many > 0 ? String(many) : nil }
        for row in rows {
            if row.isUnder {
                if row.index == 1 { row.holds(tally(count("Desktop"))) }
                if row.index == 2 { row.holds(tally(count("Downloads"))) }
            } else if row.index == 1 {
                row.holds(tally(count("Desktop") + count("Downloads")))
            }
        }

        // Hand the readings to the menu behind ⌘K, so pressing it anywhere
        // answers "how bad is it" without opening this window at all.
        Quick.shared.headline = junk > 0 ? size(junk) + " worth freeing"
                                         : "nothing worth freeing"
        Quick.shared.figures = [
            1: figures["Desktop"] ?? "",
            2: figures["Downloads"] ?? "",
            6: junk > 0 ? size(junk) : "",
        ].filter { !$0.value.isEmpty }

        // ---- the one number, and where the room is ---------------------------
        let head = NSStackView()
        head.orientation = .horizontal
        head.alignment = .top
        head.distribution = .fill
        head.spacing = 44
        head.translatesAutoresizingMaskIntoConstraints = false

        let left = NSStackView()
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 0
        left.translatesAutoresizingMaskIntoConstraints = false

        let over = NSTextField(labelWithString:
            junk > 0 ? "Carrying weight it does not need" : "Nothing it does not need")
        over.font = Words.body
        over.textColor = Paint.muted
        left.addArrangedSubview(over)
        left.setCustomSpacing(14, after: over)

        // The figure and its unit in one line, the unit small: a unit set at
        // the same size as its figure reads as a second figure.
        let said = size(junk > 0 ? junk : used)
        let bits = said.split(separator: " ")
        let shown = NSMutableAttributedString(
            string: String(bits.first ?? "0"),
            attributes: [.font: Words.huge, .foregroundColor: Paint.ink,
                         .kern: -1.4])
        if bits.count > 1 {
            shown.append(NSAttributedString(string: "  " + String(bits[1]),
                attributes: [.font: Words.unit, .foregroundColor: Paint.muted]))
        }
        let big = NSTextField(labelWithString: "")
        big.attributedStringValue = shown
        big.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(big)
        left.setCustomSpacing(16, after: big)

        let touch = count("Desktop") + count("Downloads")
        let prose = Wrapping(labelWithString: "")
        prose.maximumNumberOfLines = 0
        prose.lineBreakMode = .byWordWrapping
        prose.attributedStringValue = leaded(
            junk > 0
                ? "Nothing here is deleted \u{2014} everything Kliner moves goes somewhere "
                  + "you can find it, and one command puts it all back."
                : "There is nothing worth freeing. Everything Kliner has moved is "
                  + "still where you can find it.",
            Words.lead, Paint.muted)
        prose.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(prose)
        prose.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
        left.setCustomSpacing(18, after: prose)

        if touch > 0 {
            let read = NSTextField(labelWithString:
                whole(Double(touch)) + " things on your desktop and in downloads")
            read.font = Words.small
            read.textColor = Paint.faint
            left.addArrangedSubview(read)
            left.setCustomSpacing(26, after: read)
        }

        // Three readings of the disk as one narrowing shape. The point of the
        // picture is the last stop: almost none of what Kliner looks at is
        // ever thrown away.
        if total > 0 {
            let shape = Funnel([(value: total, name: "On the disk"),
                                (value: used,  name: "In use"),
                                (value: max(junk, total * 0.004), name: "Worth freeing")],
                               bytes: true)
            left.addArrangedSubview(shape)
            shape.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        }

        head.addArrangedSubview(left)

        // ---- where the space sits -------------------------------------------
        if total > 0 {
            let side = NSStackView()
            side.orientation = .vertical
            side.alignment = .leading
            side.spacing = 0
            side.translatesAutoresizingMaskIntoConstraints = false

            let cap = NSStackView()
            cap.orientation = .horizontal
            cap.spacing = 12
            let capName = NSTextField(labelWithString: "Where the space sits")
            capName.font = Words.body
            capName.textColor = Paint.muted
            let capSize = NSTextField(labelWithString: size(total))
            capSize.font = Words.body
            capSize.textColor = Paint.faint
            cap.addArrangedSubview(capName)
            cap.addArrangedSubview(stretch())
            cap.addArrangedSubview(capSize)
            side.addArrangedSubview(cap)
            cap.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
            side.setCustomSpacing(22, after: cap)

            let bands: [(name: String, size: Double)] = [
                (name: "Your files", size: yours),
                (name: "Worth freeing", size: junk),
                (name: "Free", size: free),
            ].filter { $0.size > 0 }

            let ringRow = NSStackView()
            ringRow.orientation = .horizontal
            ringRow.alignment = .centerY
            ringRow.spacing = 26
            ringRow.addArrangedSubview(Ring(bands, side: 150))

            let keys = NSStackView()
            keys.orientation = .vertical
            keys.alignment = .leading
            keys.spacing = 12
            for (i, band) in bands.enumerated() {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 12
                row.addArrangedSubview(Swatch(Weave.at(i), side: 18))
                let name = NSTextField(labelWithString: band.name)
                name.font = Words.body
                name.textColor = Paint.muted
                row.addArrangedSubview(name)
                row.addArrangedSubview(stretch())
                let much = NSTextField(labelWithString: size(band.size))
                much.font = Words.body
                much.textColor = Paint.ink
                row.addArrangedSubview(much)
                keys.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: keys.widthAnchor).isActive = true
            }
            ringRow.addArrangedSubview(keys)
            side.addArrangedSubview(ringRow)
            ringRow.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true

            // Twelve months of the pile building up — but only if nimo said so.
            // Last *changed*, not last opened: macOS keeps a last-used date in
            // Spotlight and reading it means one mdls per file, which is
            // minutes. This is free, true, and answers the question anybody
            // has, which is when all this arrived.
            let months = (figures["Months"] ?? "")
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if months.count == 12, months.contains(where: { $0 > 0 }) {
                side.setCustomSpacing(30, after: ringRow)

                let strip = NSStackView()
                strip.orientation = .horizontal
                strip.spacing = 12
                let stripName = NSTextField(labelWithString: "Last changed")
                stripName.font = Words.body
                stripName.textColor = Paint.muted
                strip.addArrangedSubview(stripName)
                strip.addArrangedSubview(stretch())

                // The key is the thing itself, four cells of it, so there is
                // nothing to learn before the strip can be read.
                let fewer = NSTextField(labelWithString: "fewer")
                fewer.font = Words.small
                fewer.textColor = Paint.faint
                strip.addArrangedSubview(fewer)
                strip.addArrangedSubview(Scale())
                let more = NSTextField(labelWithString: "more")
                more.font = Words.small
                more.textColor = Paint.faint
                strip.addArrangedSubview(more)

                side.addArrangedSubview(strip)
                strip.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
                side.setCustomSpacing(12, after: strip)

                let shape = DateFormatter()
                shape.dateFormat = "MMM"
                var names: [String] = []
                for back in stride(from: 11, through: 0, by: -2) {
                    if let when = Calendar.current.date(byAdding: .month,
                                                        value: -back, to: Date()) {
                        names.append(shape.string(from: when))
                    }
                }

                let heat = Heat(months, months: names)
                side.addArrangedSubview(heat)
                heat.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
            }

            head.addArrangedSubview(side)
            side.widthAnchor.constraint(equalToConstant: 392).isActive = true
        }

        line(Framed(head))
        gap(Step.close)

        // ---- everything ------------------------------------------------------
        let all = NSStackView()
        all.orientation = .vertical
        all.alignment = .leading
        all.spacing = 0
        all.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Everything")
        title.font = Words.body
        title.textColor = Paint.muted
        header.addArrangedSubview(title)
        header.addArrangedSubview(stretch())

        // The two that only move things can go together behind one question.
        // The one that empties the trash cannot: it is the only thing in
        // Kliner that deletes, so it keeps its own button and its own yes.
        let moving = [1, 2].filter { page in
            page == 1 ? count("Desktop") > 0 : count("Downloads") > 0
        }
        if moving.count > 1 {
            let sweep = Chip(.quiet)
            sweep.set("Tidy both")
            sweep.onClick = { [weak self] in self?.askTidy(moving) }
            header.addArrangedSubview(sweep)
        }

        all.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true
        all.setCustomSpacing(16, after: header)

        var left_ = 0
        func entry(_ weave: Weave, _ name: String, _ command: String, _ blurb: String,
                   figure: String, done: Bool, verb: String, page: Int,
                   pill: String? = nil) {
            if !done { left_ += 1 }
            let first = !done && left_ == 1
            let one = Entry(weave: weave, name: name, command: command, blurb: blurb,
                            pill: pill, figure: figure,
                            verb: done ? nil : verb, strong: first)
            one.onOpen = { [weak self] in self?.show(page) }
            one.onDo = { [weak self] in self?.startOn(page) }
            all.addArrangedSubview(one)
            one.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true
            let hair = rule()
            all.addArrangedSubview(hair)
            hair.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true
        }

        let sighted = Access.may(Access.desktop) && Access.may(Access.downloads)
        if !sighted {
            let ask = Entry(weave: .grid, name: "Let Kliner see your files",
                            command: "macOS has not been asked yet",
                            blurb: "It cannot read your desktop or your downloads until "
                                 + "you say so. Nothing is read before that.",
                            pill: nil, figure: "", verb: "Ask", strong: true)
            ask.onDo = { [weak self] in self?.askFromHome() }
            all.addArrangedSubview(ask)
            ask.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true
            let hair = rule()
            all.addArrangedSubview(hair)
            hair.widthAnchor.constraint(equalTo: all.widthAnchor).isActive = true
            left_ += 1
        }

        entry(.diagonal, "Desktop", "min desktop",
              "Everything loose on it moves into one dated folder, sorted by what it "
            + "is. Nothing is renamed and nothing is lost.",
              figure: figures["Desktop"] ?? "nothing on it",
              done: count("Desktop") == 0, verb: "Clear it", page: 1,
              pill: figures["Desktop older"])

        entry(.back, "Downloads", "min downloads",
              "The folder everything lands in and nothing ever leaves, sorted the "
            + "same way.",
              figure: figures["Downloads"] ?? "nothing in it",
              done: count("Downloads") == 0, verb: "Sort it", page: 2,
              pill: figures["Downloads older"])

        entry(.dots, "Worth freeing", "min clean",
              "Caches, old installers and the trash. The trash is the only thing "
            + "Kliner deletes, and only when you say so.",
              figure: junk > 0 ? size(junk) : "nothing to free",
              done: junk == 0, verb: "Free it", page: 6)

        if left_ == 0 {
            let clear = NSTextField(labelWithString: "Nothing needs doing. Your Mac is clear.")
            clear.font = Words.lead
            clear.textColor = Paint.ink
            all.addArrangedSubview(clear)
        }

        line(Framed(all))
        gap(Step.close)

        // ---- and what it has already done ------------------------------------
        let changed = (figures["Last change"] ?? "").trimmingCharacters(in: .whitespaces)
        let safe = Card(changed.isEmpty ? "Nothing here is deleted" : "What Kliner has done")
        let told = Wrapping(labelWithString: "")
        told.maximumNumberOfLines = 0
        told.lineBreakMode = .byWordWrapping
        told.attributedStringValue = leaded(
            changed.isEmpty
                ? "Kliner has not changed anything yet. When it does, it moves "
                  + "things and writes down every move, so you can have any of "
                  + "it back the way it was."
                : "Kliner moves things and writes down every move, so you can "
                  + "have any of it back the way it was.",
            Words.lead, Paint.muted)
        safe.add(told, gap: Step.hair)
        if !changed.isEmpty {
            let done = Job(changed.components(separatedBy: ", ").first ?? changed,
                           note: changed.components(separatedBy: ", ").dropFirst()
                                        .joined(separator: ", "),
                           done: true, verb: nil, symbol: "clock.arrow.circlepath")
            done.onOpen = { [weak self] in self?.show(8) }
            safe.add(done, gap: Step.tight)
        }
        safe.foot("Put something back") { [weak self] in self?.show(8) }
        line(safe)
        gap(Step.tight)
    }

    /// Go to a page and start the thing it does, which is what pressing the
    /// button on a line of the list means. It still asks: the question lives
    /// on the page, not here.
    private func startOn(_ index: Int) {
        guard index < Action.all.count else { return }
        show(index)
        // Opening a page starts a run of its own, the preview, and `run` drops
        // anything asked for while one is going. So the press was swallowed:
        // the page changed and nothing happened. It waits its turn now.
        once { [weak self] in
            guard let self = self, self.chosen == index else { return }
            self.go()
        }
    }

    /// Do this when nothing else is running. Gives up after a few seconds,
    /// because a job that never ends should not leave something queued behind
    /// it forever.
    private func once(_ then: @escaping () -> Void, tries: Int = 60) {
        guard busy else { then(); return }
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.once(then, tries: tries - 1)
        }
    }

    /// A list of things with a size each, drawn as the bar and the table of
    /// the same numbers. Anything nimo said that is not a sized row is left
    /// where it was, under the card.
    private func drawBreakdown(_ pieces: [Piece]) {
        var named: [(name: String, size: Double, folder: Bool)] = []
        var rest: [Piece] = []
        let asBytes = inBytes(pieces)
        let item = isPage ? Action.all[chosen] : nil

        for piece in pieces {
            guard case .row(let label, let value, _, _, _) = piece,
                  !label.isEmpty, let much = weigh(value) else {
                rest.append(piece)
                continue
            }
            named.append((name: label, size: much, folder: label.hasSuffix("/")))
        }

        // Biggest first. Everything downstream draws a ladder — the bars fall
        // left to right, the colour falls with them, the table reads down in
        // the same order — and all three of those were being handed the order
        // the CLI happened to print in. So the tallest bar sat on the far
        // right in the faintest shade, and the chart read as broken because
        // it was: three ladders, none of them agreeing.
        named.sort { $0.size > $1.size }

        /// Bytes read as bytes; everything else reads as a plain count.
        func amount(_ much: Double) -> String {
            asBytes ? size(much) : String(Int(much.rounded()))
        }

        let whole = named.reduce(0) { $0 + $1.size }
        if whole > 0 {
            let card = Card(!walked.isEmpty ? walked.joined(separator: "/")
                            : (item.map { $0.title } ?? "Your home folder"))

            card.add(Figure(amount(whole),
                            caption: walked.isEmpty
                                ? "across \(named.count) \(asBytes ? "folders" : "kinds")"
                                : "across \(named.count) inside \(walked.last ?? "")"))

            // Seven strengths of the one colour, then everything after that
            // rolled into the faintest of them.
            let shown = 7
            var shades: [NSColor] = []
            for (i, _) in named.enumerated() {
                shades.append(Paint.band(min(i, shown)))
            }
            // The bars are the picture and the table is the reading. A third
            // drawing of the same numbers between them — a stacked bar and a
            // row of dots naming every kind again — was the page saying one
            // thing three times, and the dots were the crowded line nobody
            // could read.
            card.add(Bars(named.map { (name: $0.name, size: $0.size) }, bytes: asBytes),
                     gap: Step.tight)

            card.add(Ledger(colour: nil, name: "What is in it",
                            share: "Share", size: asBytes ? "Size" : "How many",
                            head: true), gap: Step.air)
            for (i, one) in named.enumerated() {
                let row = Ledger(colour: shades[i],
                                 name: one.name,
                                 share: "\(Int((one.size / whole * 100).rounded()))%",
                                 size: amount(one.size),
                                 walkable: one.folder)
                if one.folder {
                    let inside = String(one.name.dropLast())
                    row.onOpen = { [weak self] in self?.walkInto(inside) }
                }
                card.add(row)
            }
            line(card)
            gap(Step.close)
        }

        for piece in rest {
            switch piece {
            case .heading(let text):
                // The card above is named after this page already. Printing
                // the panel's own heading again left "your desktop" sitting on
                // its own under the table, in the faintest grey there is.
                if whole > 0 { break }
                words(text, Words.small, Paint.faint, top: Step.air, bottom: Step.tight)
            case .good(let text):
                words(text, Words.strong, Paint.ink)
            case .warn(let text):
                words(text, Words.strong, Paint.body)
            case .text(let text):
                words(text, Words.body, Paint.body)
            case .row(let label, let value, _, _, let strong):
                if !label.isEmpty {
                    line(Said(label: label, value: value, strong: strong))
                }
            case .rule, .note:
                break
            }
        }
    }

    /// What a row is worth, as a number, whether nimo counted it in bytes or
    /// in things. Desktop and Downloads come back as kinds with a count each
    /// ("Images  42 items"), which is as much a breakdown as a list of folder
    /// sizes is, and it should be drawn like one.
    private func weigh(_ value: String) -> Double? {
        if let much = bytes(value) { return much }
        let first = value.split(separator: " ").first.map(String.init) ?? ""
        guard let many = Double(first.replacingOccurrences(of: ",", with: "")),
              many > 0 else { return nil }
        return many
    }

    /// Whether a page's numbers are sizes on a disk or counts of things.
    private func inBytes(_ pieces: [Piece]) -> Bool {
        for piece in pieces {
            guard case .row(let label, let value, _, _, _) = piece,
                  !label.isEmpty, weigh(value) != nil else { continue }
            return hasUnit(value)
        }
        return true
    }

    /// How many of a page's rows carry a number. Two is enough to be a
    /// breakdown; one is a fact.
    private func sized(_ pieces: [Piece]) -> Int {
        var count = 0
        for piece in pieces {
            guard case .row(let label, let value, _, _, _) = piece,
                  !label.isEmpty, weigh(value) != nil else { continue }
            count += 1
        }
        return count
    }

    /// The figures that stand across the top of a page.
    ///
    /// Every page gets them, not only the ones reporting on the machine: how
    /// many of whatever this page lists, how much room they take together
    /// where that can be worked out, and which one is the biggest. A page that
    /// opens with three numbers is a page you can read at a glance; a page
    /// that opens with forty rows is a page you have to work through.
    private func stats(_ pieces: [Piece]) -> [NSView] {
        guard isPage else { return [] }
        let item = Action.all[chosen]

        // The machine's own readings are already figures. Nothing to work out.
        if item.arguments.first == "doctor" {
            var out: [NSView] = []
            for piece in pieces {
                guard out.count < 4,
                      case .row(let label, let value, _, _, _) = piece,
                      !label.isEmpty, !value.isEmpty,
                      let read = reading(value) else { continue }
                out.append(Metric(label, note: read.note, big: read.big,
                                  of: read.ceiling, part: read.share))
            }
            return out
        }

        var listed: [(name: String, size: Double?)] = []
        for piece in pieces {
            guard case .row(let label, let value, _, _, _) = piece,
                  !label.isEmpty else { continue }
            listed.append((name: label, size: weigh(value)))
        }
        guard listed.count > 1 else { return [] }

        let asBytes = inBytes(pieces)
        func amount(_ much: Double) -> String {
            asBytes ? size(much) : String(Int(much.rounded()))
        }

        var out: [NSView] = [Metric(item.title,
                                    note: asBytes ? item.counts : "Kinds of thing in it",
                                    big: String(listed.count))]

        let weighed = listed.compactMap { $0.size }
        guard weighed.count > 1 else { return out }

        let whole = weighed.reduce(0, +)
        out.append(Metric("Together",
                          note: asBytes ? "How much room they take"
                                        : "How many there are altogether",
                          big: amount(whole)))

        if let big = listed.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }),
           let much = big.size, whole > 0 {
            out.append(Metric("Biggest", note: big.name, big: amount(much),
                              of: amount(whole), part: much / whole))
        }
        return out
    }

    /// One of nimo's rows, read as a figure worth standing at the top of a
    /// page: the number, what it is measured against if anything, and how far
    /// along that it is.
    private func reading(_ value: String)
        -> (note: String, big: String, ceiling: String?, share: Double?)? {
        let halves = value.components(separatedBy: " of ")
        if halves.count == 2 {
            let first = halves[0].replacingOccurrences(of: " free", with: "")
            let note = halves[0].hasSuffix("free") ? "Free of the whole" : "Of the whole"
            if let much = bytes(first), let whole = bytes(halves[1]), whole > 0 {
                return (note, first, halves[1], much / whole)
            }
            return (note, first, halves[1], nil)
        }

        // "84 files", "6 days", "72%": the number, and what it counts.
        let words = value.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = words.first,
              first.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil else {
            return nil
        }
        let rest = words.count > 1 ? words[1] : ""
        if first.hasSuffix("%"), let much = Double(first.dropLast()) {
            return (rest.isEmpty ? "Of the whole" : rest.capitalized,
                    first, nil, much / 100)
        }
        return (rest.isEmpty ? "Right now" : rest.capitalized, first, nil, nil)
    }

    /// Where you are, written as a trail: the group it belongs to, quietly,
    /// then the page itself. One label, two weights, so it reads as one line
    /// rather than as two labels that happen to be next to each other.
    private func trail(_ group: String, _ page: String) {
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: group, attributes: [
            .font: Words.trail, .foregroundColor: Paint.muted,
        ]))
        line.append(NSAttributedString(string: "  /  ", attributes: [
            .font: Words.trail, .foregroundColor: Paint.faint,
        ]))
        line.append(NSAttributedString(string: page, attributes: [
            .font: Words.title, .foregroundColor: Paint.ink,
        ]))
        let holds = Action.place(of: chosen)?.holds ?? []
        titleLabel.set(line, more: holds.count > 1)
        titleLabel.wear(Action.place(of: chosen)?.symbol
                        ?? (isSettings ? "gearshape" : "questionmark.circle"))

        // It changes as the page changes, so it fades rather than swapping:
        // two words appearing in place is a flicker, two words arriving is a
        // move from one page to another.
        titleLabel.wantsLayer = true
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0
        show.toValue = 1
        show.duration = 0.22
        show.timingFunction = CAMediaTimingFunction(name: .easeOut)
        titleLabel.layer?.add(show, forKey: "arriving")
    }

    /// He was doing the waiting in the middle of the page; now the page has
    /// come back, so he goes and sits down in the corner.
    private func settleHelper() {
        guard waited, !welcoming, let over = window.contentView else { return }
        waited = false
        let middle = scroll.convert(CGPoint(x: scroll.bounds.midX,
                                            y: scroll.bounds.midY), to: over)
        helper.land(from: middle)
    }

    /// Air between the cards. A stack view's own spacing would put the same
    /// gap inside them.
    private func gap(_ height: CGFloat) {
        let air = NSView()
        air.translatesAutoresizingMaskIntoConstraints = false
        air.heightAnchor.constraint(equalToConstant: height).isActive = true
        line(air)
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
        lastRead = Date()
        sayAge()

        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        others()

        if chosen == 0, isPage {
            drawHome(pieces)
            settle()
            return
        }

        // Anything that came back as a list of things with a size each is a
        // breakdown, and every breakdown is drawn the same way: the figures,
        // the bars, the bar cut into shares, then the table all three came
        // out of. One page shape, whichever page you are on.
        if isPage, sized(pieces) > 1 {
            drawBreakdown(pieces)
            settle()
            return
        }

        // nimo lists what it can turn off, then says "nimo only reports
        // these:" and lists the rest. Everything after that sentence belongs
        // to somebody else, so nothing after it gets a button.
        var stoppable = isPage && Action.all[chosen].arguments.first == "startup"

        // Every page is built the same way, out of the same cards, so moving
        // between them is moving between pages of one thing rather than
        // between nine little programs.
        var card: Card?

        func close() {
            guard let full = card else { return }
            line(full)
            gap(Step.close)
            card = nil
        }

        func begin(_ title: String) {
            close()
            card = Card(title)
        }

        func put(_ view: NSView, gap: CGFloat = 0) {
            if card == nil { begin(Action.all[chosen].title) }
            card?.add(view, gap: gap)
        }

        func say(_ text: String, _ font: NSFont, _ colour: NSColor) {
            let field = Wrapping(labelWithString: text)
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.attributedStringValue = leaded(text, font, colour)
            put(field, gap: Step.hair)
        }

        // A page that reports figures gets them across the top, the same way
        // Home does, before any of its rows are read.
        let across = NSStackView()
        across.orientation = .horizontal
        across.distribution = .fillEqually
        across.alignment = .top
        across.spacing = 12
        across.translatesAutoresizingMaskIntoConstraints = false
        for box in stats(pieces) { across.addArrangedSubview(box) }
        if across.arrangedSubviews.count > 1 {
            line(across)
            gap(14)
        }

        for piece in pieces {
            if case .note(let text) = piece, text.contains("only reports") {
                stoppable = false
            }

            switch piece {
            case .heading(let text):
                begin(text)

            case .rule:
                break

            case .row(let label, let value, _, _, let strong):
                // The trailing half of a row is nimo telling a terminal what
                // to type next. There is a button here instead.
                if stoppable, !label.isEmpty {
                    put(Suggest(label,
                                verb: "Stop", strong: false, name: label) { [weak self] in
                                    self?.stopThis(label)
                                })
                    break
                }
                // A page about a folder lists things in that folder, and a
                // thing in a folder is something you can open. Clicking a row
                // opens what it names, wherever Kliner has since moved it to.
                let openable = Action.all[chosen].reveal != nil && !label.isEmpty
                let said = Said(label: label, value: value, strong: strong,
                                walkable: openable)
                if openable {
                    said.onOpen = { [weak self] in self?.openThing(label) }
                }
                put(said)

            // One size for everything nimo says. Weight and colour carry the
            // difference; a second size only makes the page look assembled
            // out of two pages.
            case .good(let text):
                say(text, Words.strong, Paint.ink)

            case .warn(let text):
                say(text, Words.strong, Paint.body)

            case .note:
                // nimo's last lines tell a terminal what to type next. There
                // is nothing to type here, so they are not shown.
                break

            case .text(let text):
                say(text, Words.body, Paint.body)
            }
        }
        close()
        gap(8)

        settle()
    }

    /// A page that arrives a line at a time reads better than one swapped
    /// underneath you. Eighteen milliseconds between lines is enough to feel
    /// like settling and not enough to feel like waiting; after fourteen lines
    /// the rest come in together, because nobody wants to watch a list deal
    /// itself out.
    private func settle() {
        // The side is spent on the page it was set for. A page nobody
        // navigated to — the answer coming back after a run — falls from
        // above, which is what a result does.
        let way = came
        came = 0

        report.layoutSubtreeIfNeeded()
        let start = CACurrentMediaTime()

        for (i, view) in report.arrangedSubviews.enumerated() {
            view.wantsLayer = true

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = way == 0 ? -10 : 0   // AppKit's y grows upward
            rise.toValue = 0

            let across = CABasicAnimation(keyPath: "transform.translation.x")
            across.fromValue = 30 * way
            across.toValue = 0

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let both = CAAnimationGroup()
            both.animations = way == 0 ? [rise, fade] : [across, fade]
            both.duration = 0.34
            both.beginTime = start + Double(min(i, 14)) * 0.022
            both.fillMode = .backwards
            // Out fast, in slow: the curve a thing settling makes, rather than
            // the curve a thing being placed makes.
            both.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            view.layer?.add(both, forKey: "arriving")
        }
    }

    private func say(_ text: String) {
        draw([.text(text)])
    }

    /// While nimo is off doing the thing, the page holds its face.
    /// While Kliner is off doing the thing, the page holds his face — in the
    /// middle of it, saying what he is doing.
    ///
    /// It used to be the face alone, left-aligned at the top of an otherwise
    /// empty page. Reading a full disk takes tens of seconds, and for those
    /// seconds the first screen of the app was a small grey shape in the
    /// corner of a dark rectangle with no words on it. That is not a page
    /// loading, that is a page broken.
    private func waiting() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false

        let face = Thinking()
        holder.addSubview(face)

        let said = NSTextField(labelWithString: waitingWords())
        said.font = Words.body
        said.textColor = Paint.muted
        said.alignment = .center
        said.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(said)

        // He waits in the middle of the page. Pinned to the top of it he sat
        // in the upper quarter with two thirds of a dark rectangle under him,
        // which reads as a page that failed to draw rather than one loading.
        let above = NSLayoutGuide()
        let below = NSLayoutGuide()
        holder.addLayoutGuide(above)
        holder.addLayoutGuide(below)

        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),

            above.topAnchor.constraint(equalTo: holder.topAnchor),
            above.bottomAnchor.constraint(equalTo: face.topAnchor),
            below.topAnchor.constraint(equalTo: said.bottomAnchor),
            below.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            above.heightAnchor.constraint(equalTo: below.heightAnchor),
            above.heightAnchor.constraint(greaterThanOrEqualToConstant: Step.wide),

            face.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            said.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            said.topAnchor.constraint(equalTo: face.bottomAnchor, constant: Step.close),
            said.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor),
            said.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        ])
        line(holder)
        settle()
    }

    /// What he is actually doing, in the page's own words.
    private func waitingWords() -> String {
        guard isPage else { return "One moment." }
        let item = Action.all[chosen]
        if chosen == 0 { return "Reading your Mac. The disk takes the longest." }
        return "\(item.verb) …"
    }

    // MARK: using it

    private var isSettings: Bool { chosen == Action.all.count }
    private var isHelp: Bool { chosen == Action.all.count + 1 }
    private var isPage: Bool { chosen >= 0 && chosen < Action.all.count }

    /// Whatever page an index names, including the two that are not things
    /// nimo does.
    private func page(_ index: Int) -> Action {
        if index == Action.all.count { return Action.settings }
        if index == Action.all.count + 1 { return Action.help }
        return Action.all[index]
    }

    /// The other things in this place, under the name of the one you are on.
    /// A row of tabs said the same thing twice, once in the trail and once
    /// under it.
    private func offerSiblings() {
        guard let place = Action.place(of: chosen), place.holds.count > 1 else { return }
        let lines = place.holds.map { which in
            Sheet.Line(Action.all[which].title,
                       note: Action.all[which].counts,
                       on: which == chosen) { [weak self] in self?.show(which) }
        }
        Sheet.open(lines, under: titleLabel, wide: 280)
    }

    // MARK: finding a page, and what has been done

    /// What the search field currently matches, in the order the list has them.
    private var matches: [Int] = []

    /// Typing narrows the list down the side rather than opening a panel over
    /// it: the answer appears where you were already going to click.
    func sieve(_ words: String) {
        let want = words.trimmingCharacters(in: .whitespaces).lowercased()
        matches = []
        for (i, item) in Action.all.enumerated() {
            let hay = [item.title, item.blurb, item.verb, item.group]
                .joined(separator: " ").lowercased()
            if want.isEmpty || hay.contains(want) { matches.append(i) }
        }
        // The list is five places, not nine pages, so what is walked here is
        // the rows there are. A place stays if anything it holds matched.
        // Counting the pages and indexing the rows with that count ran off
        // the end of a seven-row list on the first letter typed, which took
        // the window with it.
        for row in rows {
            guard let place = Action.place(of: row.index) else { continue }
            // A place stays if anything it holds matched. One of the things
            // inside it stays only if it matched itself — searching for the
            // wallpaper and being shown Startup as well is the list ignoring
            // what was typed into it.
            let found = row.isUnder
                ? matches.contains(row.index)
                : place.holds.contains { matches.contains($0) }
            row.ruledOut = !(want.isEmpty || found)
        }
        // A search reaches into a shut place: what it turned up is no use
        // behind a chevron.
        if !want.isEmpty { shut = [] }
        settleList()
        // Settings and Help are under a hairline of their own and are not one
        // of the things being searched, so they stay where they are.
        for head in groupLabels { head.isHidden = !want.isEmpty }
        sideHeading.isHidden = !want.isEmpty
    }

    /// Return opens the first thing the words matched, and empties the field,
    /// because a search you have acted on is a search you are done with.
    func openFirstMatch() {
        guard let first = matches.first else { return }
        show(first)
        search.text = ""
        window.makeFirstResponder(nil)
    }

    @objc func focusSearch() {
        guard !search.isHidden else { return }
        search.focus()
    }

    /// Ask this page again. What it said last time is thrown away first, or
    /// the redraw would put the same answer back on the screen.
    @objc func refresh() {
        guard !welcoming, isPage, !busy else { return }
        kept[chosen] = nil
        seen.remove(chosen)
        show(chosen, remember: false)
    }

    /// Up and down walk the list, in the order it is drawn: the five places,
    /// then Settings, then Help. From a page inside a place it walks from the
    /// place, not from the page, because the place is what the list is
    /// showing you standing on.
    private var stops: [Int] {
        Action.places.compactMap { $0.holds.first }
            + [Action.all.count, Action.all.count + 1]
    }

    func walkList(_ way: Int) {
        guard !welcoming, !busy else { return }
        let here = Action.place(of: chosen)?.holds.first ?? chosen
        guard let at = stops.firstIndex(of: here) else { return }
        let next = at + way
        guard next >= 0, next < stops.count else { return }
        show(stops[next])
    }

    /// The introduction, from the beginning, whenever it is wanted.
    @objc func replaySetup() {
        guard !busy else { return }
        welcoming = true
        step = 0
        last = 0
        asked = false
        asking = []
        answers = []
        showing = nil
        undoing = nil
        mascot = nil
        for row in rows { row.choose(false) }
        drawWelcome()
    }

    // MARK: a sideways push

    /// During the setup, the page before. Everywhere else, the page you came
    /// from, which is what the same gesture means in every other Mac app.
    func swipedBack() {
        if welcoming {
            // Not out of the asking page: macOS is part way through a list of
            // questions and walking away from it leaves half of them unasked.
            guard step > 0, step < 3 else { return }
            step -= 1
            drawWelcome()
            return
        }
        goBack()
    }

    func swipedOn() {
        if welcoming {
            guard step < 2 else { return }
            step += 1
            drawWelcome()
            return
        }
        goForward()
    }

    /// The bell: everything Kliner has done that it could still put back,
    /// newest first, as a menu under the bell itself. Reading it is what puts
    /// the dot out.
    /// Everything that used to be spread along the row, in one list under the
    /// one thing left in that corner: what this page can do, what Kliner has
    /// done, and the keys.
    func showActivity() {
        helper.unread = false
        Sheet.open(jobs() + here() + [Sheet.Line.over("Recently"),
                                      Sheet.Line("Looking…")],
                   under: helper, wide: 340)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(["undo", "--all", "--dry-run"])
            let pieces = Report.parse(result.text)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var done: [Sheet.Line] = []
                for piece in pieces {
                    guard done.count < 5,
                          case .row(let label, let value, _, _, _) = piece,
                          !label.isEmpty else { continue }
                    done.append(Sheet.Line(label, note: value.isEmpty ? nil : value))
                }
                if done.isEmpty {
                    done = [Sheet.Line("Nothing changed yet")]
                } else {
                    done.append(Sheet.Line("Put it all back…") { [weak self] in
                        self?.openUndo()
                    })
                }
                Sheet.open(self.jobs() + self.here()
                           + [Sheet.Line.over("Recently")] + done
                           + self.keys(),
                           under: self.helper, wide: 340)
            }
        }
    }

    /// What the page you are on can do, named.
    private func here() -> [Sheet.Line] {
        guard isPage else { return [] }
        let item = Action.all[chosen]
        var lines: [Sheet.Line] = [.over(item.title)]

        if item.asks != nil || !item.looksOnly {
            lines.append(Sheet.Line(item.verb) { [weak self] in self?.go() })
        } else {
            lines.append(Sheet.Line("Ask again", note: "⌘R") { [weak self] in
                self?.refresh()
            })
        }
        if !walked.isEmpty {
            lines.append(Sheet.Line("Back out") { [weak self] in self?.walkUp() })
        } else if item.reveal != nil {
            lines.append(Sheet.Line("Look inside") { [weak self] in
                self?.walked = [item.reveal ?? ""]
                self?.walkHere()
            })
        }
        for (i, extra) in item.extras.enumerated() {
            lines.append(Sheet.Line(extra.title) { [weak self] in self?.runExtra(i) })
        }
        if item.reveal != nil {
            lines.append(Sheet.Line("Show in Finder") { [weak self] in
                self?.revealFolder()
            })
        }
        return lines
    }

    // MARK: giving Kliner something to do

    /// Everything Kliner can be told to do, in one list, with what there is of
    /// it beside each. Picking one starts it; picking the first starts all of
    /// them, in order, after one question covering the lot.
    /// What Kliner can be told to do, with what there is of each beside it.
    private func jobs() -> [Sheet.Line] {
        var lines: [Sheet.Line] = [.over("Give Kliner something to do")]
        let worth = worthDoing()

        if worth.count > 1 {
            let names = worth.map { Action.all[$0].title.lowercased() }
            lines.append(Sheet.Line("Do all of it",
                                    note: names.joined(separator: ", ")) { [weak self] in
                self?.doThemAll(worth)
            })
        }

        for which in Main.doable {
            let item = Action.all[which]
            lines.append(Sheet.Line(item.verb, note: waiting(which)) { [weak self] in
                self?.startOn(which)
            })
        }
        return lines
    }

    /// The ones Home found something to do about, in the order they are worth
    /// doing: clear the desk, sort what landed on it, then free the caches.
    private func worthDoing() -> [Int] {
        var figures: [String: String] = [:]
        for piece in kept[0] ?? [] {
            if case .row(let label, let value, _, _, _) = piece { figures[label] = value }
        }
        func some(_ key: String) -> Bool {
            guard let said = figures[key] else { return false }
            return !said.hasPrefix("0")
        }
        var out: [Int] = []
        if some("Desktop")   { out.append(1) }
        if some("Downloads") { out.append(2) }
        if some("Junk")      { out.append(6) }
        return out
    }

    /// What there is of a job, from the last reading Home took.
    private func waiting(_ which: Int) -> String? {
        var figures: [String: String] = [:]
        for piece in kept[0] ?? [] {
            if case .row(let label, let value, _, _, _) = piece { figures[label] = value }
        }
        switch which {
        case 1: return figures["Desktop"]
        case 2: return figures["Downloads"]
        case 6: return figures["Junk"]
        default: return nil
        }
    }

    /// One question for the lot, then each in turn. Kliner still writes down
    /// every move, so the whole run is one thing to reverse.
    private func doThemAll(_ jobs: [Int]) {
        guard !busy, !jobs.isEmpty else { return }
        let said = jobs.map { "· " + Action.all[$0].verb }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Do all of it?"
        alert.informativeText = """
        \(said)

        Nothing is deleted that Kliner cannot put back, and Put it all back reverses the whole run.
        """
        alert.addButton(withTitle: "Do it")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        queue = jobs
        nextInQueue()
    }

    /// A queue keeps going by itself, one page at a time, whatever else
    /// happened to the run that just ended.
    private func carryOn() {
        guard !queue.isEmpty else {
            // The run is over. Home is where it was asked for and where the
            // numbers it changed are, so that is where it ends.
            guard ran else { return }
            ran = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self = self, !self.busy else { return }
                self.kept[0] = nil
                self.show(0)
            }
            return
        }
        ran = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.nextInQueue()
        }
    }

    private func nextInQueue() {
        guard !queue.isEmpty else { return }
        let which = queue.removeFirst()
        show(which)
        once { [weak self] in
            guard let self = self, self.chosen == which else { return }
            self.kept[which] = nil
            // Already asked, once, for the whole run.
            self.run(Action.all[which], preview: false)
        }
    }

    /// The pages that do something, in the order they read down the list.
    static let doable = [1, 2, 3, 6, 8]

    /// The keys, where somebody looking for them would look.
    private func keys() -> [Sheet.Line] {
        [.over("Keys"),
         Sheet.Line("Search the list", note: "⌘F"),
         Sheet.Line("The quick menu, from anywhere", note: "⌘K"),
         Sheet.Line("Ask this page again", note: "⌘R"),
         Sheet.Line("Show the introduction", note: "⌘F"),
         Sheet.Line("Hide the list", note: "⌘B"),
         Sheet.Line("Everything, in one page", note: "Help") { [weak self] in
             self?.show(Action.all.count + 1)
         }]
    }

    @objc func openUndo() {
        show(Action.all.count - 1)
    }

    @objc func goBack() {
        guard let last = behind.popLast() else { return }
        ahead.append(chosen)
        came = -1
        show(last, remember: false)
    }

    @objc func goForward() {
        guard let next = ahead.popLast() else { return }
        behind.append(chosen)
        came = 1
        show(next, remember: false)
    }

    private func showArrows() {
        backButton.isEnabled = !behind.isEmpty
        onButton.isEnabled = !ahead.isEmpty
    }

    private func show(_ index: Int, remember: Bool = true) {
        guard index >= 0, index <= Action.all.count + 1 else { return }
        if welcoming {
            welcoming = false
            mascot = nil
            Config.set("welcomed", Main.setup)
            bare(false)
        }
        if remember, index != chosen {
            behind.append(chosen)
            ahead = []
        }
        // Nobody set a side, so the side is the way you are travelling through
        // the list: down it is forward, up it is back.
        if came == 0, index != chosen { came = index > chosen ? 1 : -1 }
        chosen = index
        walked = []
        showArrows()
        tick()

        // A row is lit when the page you are on lives in it, not only when it
        // is the page the row opens: Downloads is inside Desk, and Desk is
        // what the list should be showing you standing on.
        for row in rows {
            let here = row.index == index
            let holds = Action.place(of: row.index)?.holds ?? []
            let inHere = holds.contains(index)
            if row.isUnder {
                row.choose(here)
            } else if holds.count > 1 {
                // A place with its things listed under it is not itself a
                // page you stand on; the one you are standing on is under it.
                row.choose(false)
                row.within(inHere)
            } else {
                row.choose(here || inHere)
            }
        }

        let item = page(index)
        let name = index == 0 ? "Home" : item.title
        let place = Action.place(of: index)?.title ?? "Kliner"
        trail(place == name ? "Kliner" : place, name)
        fitButtons()

        if isSettings {
            drawSettings()
            return
        }

        if isHelp {
            drawHelp()
            return
        }

        // Already read once. Draw what it said; the button at the top asks
        // again when you want it asked again.
        if let already = kept[index] {
            draw(already)
            return
        }

        // Open a page and it fills in by itself — but only if arriving cannot
        // change anything. The ones that ask show their --dry-run; the ones
        // that act without asking, like Next, wait for you to press the button.
        if item.asks != nil {
            run(item, preview: true)
        } else if item.looksOnly {
            run(item)
        } else {
            seen.insert(index)
            let ready: [Piece] = [.text("Ready when you are.")]
            kept[index] = ready
            draw(ready)
        }
    }

    /// The big button, then whatever else this page can do. Rebuilt whenever
    /// the page changes, because what a page can do depends on where you are
    /// standing in it.
    /// The right of the row, filled in for whichever page is showing. The
    /// views are always the same views; what changes is what they say and
    /// which of them are there at all, so the row never jumps about while a
    /// page loads.
    private func fitButtons() {
        tellStrip()
        // A page that only reads has no button: opening it reads it, and Cmd-R
        // reads it again. "Look again" beside a page that had just looked was
        // a button for the sake of having one.
        guard isPage else {
            primary.isHidden = true
            return
        }
        let item = Action.all[chosen]
        let acts = item.asks != nil || !item.looksOnly
        primary.isHidden = !acts
        if acts { primary.set(item.verb, live: !busy) }
        wake()
    }

    /// What the line under the card says. Kliner's own words for what it is
    /// doing, and its version when it is doing nothing.
    private func tellStrip() {
        guard strip != nil else { return }
        if busy {
            // The page's own words for what it is doing. Lowercased and put
            // after "Kliner is" they came out as "Kliner is look again",
            // because the button says what pressing it does, not what is
            // happening. The button's own words, as they are, and a trail.
            let what = chosen == 0 ? "Reading your Mac"
                                   : (isPage ? Action.all[chosen].verb : "Working")
            strip.say("\(what) …", busy: true)
        } else {
            strip.say("Kliner \(Nimo.version) · nothing here is deleted", busy: false)
        }
    }

    /// The quiet actions follow the one button: alive when Kliner is not busy,
    /// grey while it is, and back again the moment it stops.
    private func wake() {
        for chip in offered { chip.set(chip.words, live: !busy) }
    }

    /// Everything this page can do that is not the one thing it is for, as a
    /// row of quiet words along the top of the page itself.
    ///
    /// They were in the top row, behind a button holding three buttons. They
    /// belong here: next to the thing they act on, with their names showing.
    private func others() {
        guard isPage else { return }
        let item = Action.all[chosen]

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Step.tight
        row.translatesAutoresizingMaskIntoConstraints = false

        offered = []
        func offer(_ title: String, _ act: @escaping () -> Void) {
            let chip = Chip(.quiet)
            chip.set(title, live: !busy)
            chip.onClick = act
            row.addArrangedSubview(chip)
            offered.append(chip)
        }

        if !walked.isEmpty {
            offer("Back out") { [weak self] in self?.walkUp() }
        } else if let folder = item.reveal {
            // Every page about a folder can be looked into, measured, the same
            // way What is big is: this is where that starts.
            offer("Look inside") { [weak self] in
                self?.walked = [folder]
                self?.walkHere()
            }
        }
        for (i, extra) in item.extras.enumerated() {
            offer(extra.title) { [weak self] in self?.runExtra(i) }
        }
        if item.reveal != nil {
            offer("Show in Finder") { [weak self] in self?.revealFolder() }
        }

        guard !row.arrangedSubviews.isEmpty else { return }

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            row.topAnchor.constraint(equalTo: holder.topAnchor),
            row.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -Step.close),
            row.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        ])
        line(holder)
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

    /// Open the thing a row names.
    ///
    /// Where it is depends on whether Kliner has been run yet: before, it is
    /// in the folder itself; after, it is inside Tidy, filed by what it is.
    /// So it looks in the folder, then through Tidy, and if it cannot find it
    /// at all it opens the folder rather than nothing.
    private func openThing(_ name: String) {
        guard isPage, let folder = Action.all[chosen].reveal else { return }
        let files = FileManager.default
        let base = files.homeDirectoryForCurrentUser.appendingPathComponent(folder)

        let plain = base.appendingPathComponent(name)
        var folderly: ObjCBool = false
        if files.fileExists(atPath: plain.path, isDirectory: &folderly) {
            // A folder is something to look inside, not something to hand to
            // the Finder and be done with.
            if folderly.boolValue {
                walked = [folder, name]
                walkHere()
                return
            }
            NSWorkspace.shared.open(plain)
            return
        }

        // Two levels is as deep as Tidy goes: Tidy, then what it is.
        let tidy = base.appendingPathComponent("Tidy")
        if let kinds = try? files.contentsOfDirectory(at: tidy,
                                                     includingPropertiesForKeys: nil) {
            for kind in kinds {
                let inside = kind.appendingPathComponent(name)
                if files.fileExists(atPath: inside.path) {
                    NSWorkspace.shared.open(inside)
                    return
                }
            }
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: base.path)
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
        // Stepped all the way back out of a folder page, the page itself is
        // what you wanted, not a measurement of your whole home.
        if walked.isEmpty, isPage, Action.all[chosen].reveal != nil {
            kept[chosen] = nil
            show(chosen, remember: false)
            return
        }
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

    /// Every key Kliner answers to, in the order somebody would reach for
    /// them. A window you can only work with a mouse is a window somebody
    /// has not finished.
    private func drawHelp() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        func card(_ title: String, over: String, _ keys: [(String, String)]) {
            let box = Card(title)
            box.add(Ledger(colour: nil, name: "What it does",
                           share: "", size: over, head: true))
            for (what, key) in keys {
                box.add(Ledger(colour: nil, name: what, share: "", size: key))
            }
            line(box)
            gap(Step.close)
        }

        card("Getting about", over: "Key", [
            ("The place above", "↑"),
            ("The place below", "↓"),
            ("Back where you came from", "⌘["),
            ("Forward again", "⌘]"),
            ("Hide the list", "⌘B"),
            ("Search the list", "⌘F"),
            ("The quick menu, from anywhere", "⌘K"),
        ])

        card("On the page", over: "Key", [
            ("Ask this page again", "⌘R"),
            ("Show the introduction", "⌘F"),
            ("Settings", "⌘,"),
            ("A sideways push turns the page", "two fingers"),
        ])

        // Not a list of keys, and a column headed "Key" over a column of
        // "never" is a table that has not read itself.
        card("What Kliner will not do", over: "Ever?", [
            ("Ask for an administrator", "never"),
            ("Touch the network", "never"),
            ("Read outside your home folder", "never"),
            ("Delete anything it cannot put back", "never"),
        ])

        settle()
    }

    // MARK: settings

    private func drawSettings() {
        for view in report.arrangedSubviews {
            report.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // In cards, like every other page in the window. Settings was a
        // column of loose rows with a grey word over each group, which on a
        // page made of cards reads as the one screen somebody forgot.
        let mine = Card("Kliner")

        let login = NSSwitch()
        login.state = Login.on ? .on : .off
        login.isEnabled = Login.possible
        login.target = self
        login.action = #selector(loginChanged(_:))
        mine.add(Setting("Open when I sign in", control: login))

        let days = NSPopUpButton()
        days.addItems(withTitles: ["7 days", "30 days", "90 days"])
        days.selectItem(withTitle: (Config.value("days") ?? "30") + " days")
        if days.indexOfSelectedItem < 0 { days.selectItem(withTitle: "30 days") }
        days.target = self
        days.action = #selector(daysChanged(_:))
        mine.add(Setting("Old means older than", control: days))

        mine.add(Setting("In a terminal",
                         control: quiet("Open") { [weak self] in self?.openTerminal() }))

        mine.add(Setting("The introduction",
                         control: quiet("Show it again  ⌘F") { [weak self] in
                             self?.replaySetup()
                         }))
        line(mine)
        gap(Step.close)

        // ---- what macOS will let it touch --------------------------------
        // Each row says what is true; the button does the only thing there is
        // to do about it.
        let allowed = Card("What macOS lets Kliner touch")

        // Full Disk Access first, because it is the one that ends the asking.
        // Folder by folder, macOS prompts again for every folder nimo has not
        // been in yet; with this on it never prompts at all.
        allowed.add(Setting(Access.everything ? "Full Disk Access, on"
                                              : "Full Disk Access, off",
                            control: quiet(Access.everything ? "Settings" : "Turn on") {
                                [weak self] in self?.explainFullDisk()
                            }))

        let openFolders = Access.may(Access.desktop) && Access.may(Access.downloads)
        allowed.add(Setting(openFolders ? "Your folders" : "Your folders, not yet",
                            control: quiet(openFolders ? "Check again" : "Ask") {
                                [weak self] in self?.askForFolders()
                            }))

        allowed.add(Setting("Changing your wallpaper",
                            control: quiet("Settings") {
                                Access.settings("Privacy_Automation")
                            }))
        line(allowed)
        gap(Step.close)

        words("Kliner \(Nimo.version) · MIT · kliner.app",
              Words.small, Paint.faint, top: Step.tight, bottom: Step.hair)

        settle()
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

    /// Done, and straight to the thing you said to start with. Landing on
    /// Home after answering "what should I start with" is the app not having
    /// listened.
    private func openStart() {
        let wanted = startWith
        finishWelcome()
        show(Main.page(for: wanted))
    }

    /// Whatever was typed on the page being left, before that page goes.
    /// Without this, walking back to a question showed you the default again
    /// rather than the answer you had already given it.
    private func harvest() {
        if let said = nameField?.text { callMe = said }
        if let said = tidyField?.text { tidyName = said }
        nameField = nil
        tidyField = nil
    }

    /// One of the three, and the other two let go of it.
    private func pick(_ value: String) {
        startWith = value
        for one in choices { one.choose(one.value == value) }
    }

    @objc private func loginWanted(_ sender: NSSwitch) {
        atLogin = sender.state == .on
    }

    /// What the setup was told, written where both halves of Kliner read it.
    ///
    /// ~/.nimo/config is the CLI's own file: it is read, never sourced, and
    /// every line the app does not recognise is left exactly where it was. So
    /// answering these three questions changes what `min` does as well.
    private func keep() {
        harvest()
        Config.set("name", callMe)
        Config.set("start", startWith)

        // A folder to sort into is a name, not a route, and the CLI refuses a
        // value with a separator in it. Refusing it here too means the two of
        // them never disagree about where things went.
        let folder = tidyName.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty, !folder.contains("/"), !folder.contains(".."), folder != "." {
            Config.set("tidy", folder)
        } else {
            tidyName = "Tidy"
        }

        if Login.possible, atLogin != Login.on {
            _ = Login.set(atLogin)
        }
    }

    /// The same asking, from Settings rather than from the setup. There is no
    /// page of rows to keep up with here, so it asks for the lot and then says
    /// where it got to by drawing the page again.
    private func askForFolders() {
        for gate in Main.gates {
            guard let folder = gate.2 else { continue }
            Access.may(folder)
        }
        drawSettings()
    }

    /// One permission at a time, with the page saying which one is up.
    ///
    /// macOS puts its own question on the screen and does not come back until
    /// somebody has answered it, so the row has to say it is asking *before*
    /// the ask, on a later turn of the runloop — otherwise the window never
    /// gets a chance to draw the word. That wait is also what makes this read
    /// as somebody going through them with you rather than four prompts
    /// arriving at once.
    private func askNext(_ i: Int) {
        guard welcoming, step == 3, i < asking.count else {
            if welcoming, step == 3 {
                asked = true
                drawWelcome()
            }
            return
        }

        let row = asking[i]
        let gate = Main.gates[i]
        row.say("asking macOS now…", mark: "hourglass")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self = self, self.welcoming, self.step == 3 else { return }

            func settled(_ yes: Bool) {
                let note = yes ? "allowed" : "not allowed. Settings can change it later"
                let mark = yes ? "checkmark.circle" : "circle.slash"
                if i == self.answers.count { self.answers.append((note, mark, yes)) }
                row.say(note, mark: mark, settled: yes)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
                    self?.askNext(i + 1)
                }
            }

            guard let folder = gate.2 else {
                Word.ask { yes in settled(yes) }
                return
            }
            settled(Access.may(folder))
        }
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

        // Read, never change. The dialog is skipped because there is nothing
        // to agree to: the same command runs with --preview and nothing on
        // the disk moves.
        if previewOnly {
            run(item, preview: true)
            return
        }

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

    /// `quietly` is for the reading Home takes of itself: it runs the same
    /// command, but it does not blank the page and put the waiting face up,
    /// because nobody asked for it and a page that goes blank on its own is a
    /// page that flickers.
    private func run(_ item: Action, preview: Bool = false, quietly: Bool = false) {
        guard !busy else {
            // Something else is still running — Home reads itself every half
            // minute, so this is not rare. The page that has just been opened
            // has nothing of its own to show yet, and it must not go on
            // showing the last page's answer under its own name. It puts the
            // face up and asks again the moment the machine is free.
            //
            // This was silent: open Desktop while Home was refreshing and you
            // got Desktop's title, Desktop's button and Home's page.
            guard !quietly else { return }
            wanted = chosen
            waited = true
            waiting()
            return
        }
        wanted = nil
        // Home in two halves. Everything on it but one figure is a handful of
        // reads and is instant; the junk figure walks every cache on the disk
        // and takes tens of seconds. Asking for the lot meant the first screen
        // of the app was a face on an empty page for all of them. So it asks
        // for the instant half, draws that, and asks again for the rest.
        if !preview, item.arguments.first == "doctor", kept[chosen] == nil {
            filling = true
        }
        busy = true
        seen.insert(chosen)
        fitButtons()
        // He flies to the corner from wherever the waiting was, so he only
        // flies when there was one. Home reading itself every half minute is
        // not something to watch him arrive from.
        waited = !quietly
        if !quietly { waiting() }

        // Only after somebody has said yes does --yes go anywhere near nimo,
        // and a preview cannot be given it at all.
        var arguments: [String]
        if preview {
            arguments = item.arguments + ["--dry-run"]
        } else {
            arguments = item.asks == nil ? item.arguments : item.arguments + ["--yes"]
        }
        if filling { arguments += ["--fast"] }
        spin(arguments)
    }

    /// True while the instant half of Home is in flight, so what comes back is
    /// drawn and then asked again in full.
    private var filling = false

    /// A page that was opened while something else was still running, and is
    /// owed a reading of its own the moment there is one to be had.
    private var wanted: Int?

    /// Ask for that page, the same way opening it would have.
    private func askFor(_ index: Int) {
        guard index == chosen, isPage, !busy, kept[index] == nil else { return }
        let item = Action.all[index]
        if item.asks != nil {
            run(item, preview: true)
        } else if item.looksOnly {
            run(item)
        } else {
            let ready: [Piece] = [.text("Ready when you are.")]
            kept[index] = ready
            draw(ready)
        }
    }

    /// Whether there was a page owed and it has now been asked for.
    private func serveWanted() -> Bool {
        guard let again = wanted else { return false }
        wanted = nil
        guard again == chosen, isPage, kept[again] == nil, !busy else { return false }
        askFor(again)
        return true
    }

    /// The rest of Home, once the instant half is on the screen. Quietly: the
    /// page is already drawn and nobody is waiting on a face.
    private func fillIn() {
        guard chosen == 0, isPage, !busy, !welcoming else { return }
        busy = true
        waited = false
        fitButtons()
        spin(Action.all[0].arguments)
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
                    self.waited = false
                    self.fitButtons()
                    // Somebody is standing on another page with nothing on
                    // it, waiting for exactly this moment.
                    if self.serveWanted() { return }
                    self.carryOn()
                    return
                }
                let pieces = Report.parse(result.text)
                if pieces.isEmpty {
                    self.say("Kliner said nothing at all.")
                } else {
                    // Only the page itself is worth keeping. A step inside a
                    // folder is somewhere else, and putting it under the page
                    // would show it again when you came back to the page.
                    if self.walked.isEmpty { self.kept[asked] = pieces }
                    self.draw(pieces)
                }

                // Only for the ones that changed something, and only the line
                // nimo already wrote — no second opinion invented here.
                if !arguments.contains("--dry-run"), arguments.contains("--yes") {
                    for piece in pieces {
                        if case .good(let done) = piece {
                            Word.say(Action.all[asked].title, done)
                            self.helper.unread = true
                            break
                        }
                    }
                }
                self.busy = false
                self.fitButtons()
                self.settleHelper()

                // The instant half of Home is on the screen; now ask for the
                // rest of it. The page stays where it is while that runs.
                if self.filling {
                    self.filling = false
                    if self.chosen == 0, !pieces.isEmpty {
                        self.kept[asked] = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            [weak self] in self?.fillIn()
                        }
                        return
                    }
                }
                if self.serveWanted() { return }
                self.carryOn()
            }
        }
    }

    /// Open or shut one place in the list. Thirteen rows is thirteen rows
    /// whether you want them or not, so each of them can be put away.
    private func foldPlace(_ first: Int) {
        if shut.contains(first) { shut.remove(first) } else { shut.insert(first) }
        settleList()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            self.listScroll.contentView.layoutSubtreeIfNeeded()
        }
    }

    /// Which rows are on the screen: what a search left, what a shut place is
    /// hiding, and whether the whole list is folded down to a rail. Three
    /// answers that used to be given in three places and disagreed.
    private func settleList() {
        for row in rows {
            let place = Action.place(of: row.index)
            let first = place?.holds.first ?? -1
            row.shutAway = shut.contains(first)
            if place != nil, (place?.holds.count ?? 0) > 1, !row.isUnder {
                row.folds(!shut.contains(first))
            }
            row.settle(narrow)
        }
    }

    /// The list folds down to its pictures and back. Everything stays where
    /// it was — same rows, same order, same fills — only the words go, and
    /// each row keeps its name as a tooltip so nothing is lost.
    @objc func foldSide() {
        fold(!narrow, animated: true)
        // Remembered, because a window that opens the wrong shape every
        // morning is a window you fold every morning.
        Config.set("rail", narrow ? "icons" : "list")
    }

    /// The shape the window opens in, and the shape ⌘B toggles it to.
    func fold(_ yes: Bool, animated: Bool) {
        guard narrow != yes else { return }
        narrow = yes

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            for head in self.groupLabels { head.animator().alphaValue = self.narrow ? 0 : 1 }
        }
        for row in rows { row.narrow(narrow) }
        for head in groupLabels { head.isHidden = narrow }
        // Folded to a rail there is no room for a word over the list either,
        // nor for the things inside a place: the place itself is still there.
        sideHeading.isHidden = narrow
        settleList()
        // A search field 38 points wide is a search field nobody can type in.
        search.isHidden = narrow

        wordmark.fold(narrow)
        markWidth.constant = narrow ? 38 : 190
        stackWidth.constant = narrow ? 38 : 214
        listWidth.constant = narrow ? 38 : 214
        railWidth.constant = narrow ? 70 : 246
        chromeLeading.constant = narrow ? 90 : 76
        foldButton.toolTip = narrow ? "Show the list  ⌘B" : "Hide the list  ⌘B"

        guard animated else {
            window.contentView?.layoutSubtreeIfNeeded()
            return
        }
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

    /// One question for the places that only move things, then each of them
    /// in turn. Not `min tidy`: that one also sets your wallpaper and walks
    /// you through setup, and neither of those belongs behind a button
    /// somebody pressed to clear their desktop.
    private func askTidy(_ pages: [Int]) {
        let names = pages.map { Action.all[$0].title.lowercased() }
        let said = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            : (names.first ?? "")

        if previewOnly {
            // The mode says the buttons change nothing, so this one does not
            // either. It reads both pages instead.
            queueTidy(pages, change: false)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Tidy " + said + "?"
        alert.informativeText = "Everything loose in them moves into one dated "
            + "folder each, sorted by what it is. Nothing is deleted, nothing is "
            + "renamed, and nothing outside those two folders is touched.\n\n"
            + "\"Put it all back\" reverses every one of these moves."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Do it")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        queueTidy(pages, change: true)
    }

    /// One at a time, each waiting for the one before it. Two of these at once
    /// is two processes walking the same folder.
    private func queueTidy(_ pages: [Int], change: Bool) {
        guard let page = pages.first else { return }
        let rest = Array(pages.dropFirst())
        // Two minutes, because a desktop with three thousand things on it is
        // not quick, and giving up halfway is worse than waiting.
        once({ [weak self] in
            guard let self = self else { return }
            self.show(page)
            self.run(Action.all[page], preview: !change)
            self.queueTidy(rest, change: change)
        }, tries: 1200)
    }

    /// Turn "read, never change" on or off.
    private func flipPreview() {
        previewOnly.toggle()
        modePill.lit(previewOnly)
        Config.set("preview", previewOnly ? "on" : "off")
        primary.set(previewOnly ? "Look only" : Action.all[min(chosen, Action.all.count - 1)].verb)
    }

    /// "scanned 12s ago", and the same sentence a minute later.
    private func sayAge() {
        guard let read = lastRead else { agePill.isHidden = true; return }
        let gone = Int(Date().timeIntervalSince(read))
        agePill.isHidden = false
        if gone < 5        { agePill.set("scanned just now") }
        else if gone < 90  { agePill.set("scanned \(gone)s ago") }
        else if gone < 5400 { agePill.set("scanned \(gone / 60)m ago") }
        else               { agePill.set("scanned \(gone / 3600)h ago") }
    }

    /// The menu behind ⌘K hands a page over. It never runs anything itself:
    /// the page says what it is about to do, and waits to be told yes.
    func openPage(_ index: Int) {
        show(index)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

/// Whether a figure nimo printed carries a unit.
///
/// `2.1 GB` is a size. `142` is a hundred and forty-two things. `bytes` is
/// deliberately forgiving and reads a bare number as bytes, which is right
/// when you already know you are holding a size and wrong when you are asking
/// whether you are — and that is how a desktop with 142 things on it came to
/// be reported as 284 B, in a column headed Size.
func hasUnit(_ text: String) -> Bool {
    let tail = text.trimmingCharacters(in: .whitespaces)
        .drop { $0.isNumber || $0 == "." || $0 == "," }
        .trimmingCharacters(in: .whitespaces)
        .uppercased()
    return ["B", "KB", "MB", "GB", "TB"].contains(tail)
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
        now.font = Words.small
        now.textColor = Paint.muted
        now.translatesAutoresizingMaskIntoConstraints = false
        addSubview(now)

        let after = NSTextField(labelWithString: freeAfter)
        after.font = Words.small
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
    private let icon = NSImageView()
    private let under: Wrapping

    /// The line underneath, said again. The setup asks macOS one folder at a
    /// time and each row has to keep up, so a row is written once and then
    /// told what has happened to it.
    func say(_ note: String, mark: String? = nil, settled: Bool = false) {
        under.stringValue = note
        under.textColor = settled ? Paint.body : Paint.faint
        guard let mark = mark,
              let picture = NSImage(systemSymbolName: mark, accessibilityDescription: nil)
        else { return }
        picture.isTemplate = true
        icon.image = picture
        icon.contentTintColor = settled ? Paint.ink : Paint.faint
    }

    init(_ symbol: String, _ name: String, _ note: String) {
        under = Wrapping(labelWithString: note)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        if let picture = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            picture.isTemplate = true
            icon.image = picture
        }
        icon.contentTintColor = Paint.muted
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: name)
        title.font = Words.strong
        title.textColor = Paint.ink
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        under.font = Words.small
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

/// Kliner walks the five places and each one lights up as he reaches it.
///
/// This page was eight rows of prose, then five marks that appeared. Both of
/// those are a page being shown to you. Somebody walking along a row and
/// stopping at each thing is somebody showing you round, and that is the
/// difference between reading an introduction and being given one.
///
/// Everything in here is placed by frame rather than by constraint: it is a
/// figure walking past some marks, and Auto Layout has nothing to say about
/// that.
final class Walk: NSView {
    private let face = NSImageView()
    private var marks: [NSView] = []
    private var names: [NSTextField] = []
    private var pending: [DispatchWorkItem] = []

    private static let side: CGFloat = 54
    private static let gap: CGFloat = 16
    private static let him: CGFloat = 44
    /// How long a step between two marks takes, and how long he stands at one.
    private static let leg = 0.52
    private static let hold = 0.42

    init(_ places: [Action.Place]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        for place in places {
            let mark = NSView()
            mark.wantsLayer = true
            mark.layer?.cornerRadius = 13
            addSubview(mark)

            let glyph = NSImageView()
            if let picture = NSImage(systemSymbolName: place.symbol,
                                     accessibilityDescription: nil) {
                picture.isTemplate = true
                glyph.image = picture
            }
            glyph.contentTintColor = Paint.muted
            mark.addSubview(glyph)

            let name = NSTextField(labelWithString: place.title)
            name.font = Words.tiny
            name.textColor = Paint.faint
            name.alignment = .center
            addSubview(name)

            marks.append(mark)
            names.append(name)
        }

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        face.imageScaling = .scaleProportionallyUpOrDown
        face.wantsLayer = true
        addSubview(face)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 124),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    deinit { stop() }

    private func stop() {
        for item in pending { item.cancel() }
        pending = []
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        face.contentTintColor = Paint.ink
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for mark in self.marks {
                mark.layer?.backgroundColor = Paint.track.cgColor
            }
        }
    }

    /// Where the row of marks begins, so the walk and the layout agree.
    private var start: CGFloat {
        let side = Walk.side, gap = Walk.gap
        let all = CGFloat(marks.count) * side + CGFloat(max(0, marks.count - 1)) * gap
        return (bounds.width - all) / 2
    }

    override func layout() {
        super.layout()
        let side = Walk.side, gap = Walk.gap
        let left = start
        for (i, mark) in marks.enumerated() {
            let x = left + CGFloat(i) * (side + gap)
            // AppKit's y grows up, so the marks sit above and he walks under.
            mark.frame = CGRect(x: x, y: 54, width: side, height: side)
            names[i].frame = CGRect(x: x - 10, y: 36, width: side + 20, height: 15)
        }
        face.frame = CGRect(x: left - 66, y: 0, width: Walk.him, height: Walk.him)
    }

    /// He sets off, stops at each mark in turn, and turns to face you at the
    /// end of the row.
    func play(after wait: Double) {
        stop()
        layoutSubtreeIfNeeded()
        guard !marks.isEmpty else { return }

        let leg = Walk.leg, hold = Walk.hold
        let total = Double(marks.count) * (leg + hold)
        let home = face.frame.origin.x
        var stops: [CGFloat] = [0]
        var times: [Double] = [0]
        var clock = 0.0

        for i in 0..<marks.count {
            let x = start + CGFloat(i) * (Walk.side + Walk.gap)
                  + (Walk.side - Walk.him) / 2 - home
            clock += leg
            stops.append(x); times.append(clock / total)
            clock += hold
            stops.append(x); times.append(clock / total)
        }

        let across = CAKeyframeAnimation(keyPath: "transform.translation.x")
        across.values = stops
        across.keyTimes = times.map { NSNumber(value: $0) }
        across.duration = total
        across.beginTime = CACurrentMediaTime() + wait
        across.fillMode = .both
        across.isRemovedOnCompletion = false
        // Eased at every stop, not only at the ends, so each leg is a walk to
        // somewhere rather than one long slide with pauses cut into it.
        across.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut),
            count: max(1, stops.count - 1))
        face.layer?.add(across, forKey: "walking")

        // Up and down while the feet are moving. Without it he hovers across
        // the page, which is a picture being dragged, not somebody walking.
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = 0
        bob.toValue = 5
        bob.duration = 0.17
        bob.autoreverses = true
        bob.repeatCount = Float(total / 0.34)
        bob.beginTime = CACurrentMediaTime() + wait
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(bob, forKey: "bobbing")

        for i in 0..<marks.count {
            // He looks the way he is going, and faces you when he stops.
            at(wait + Double(i) * (leg + hold)) { [weak self] in
                self?.wear("mascot-right")
            }
            at(wait + Double(i) * (leg + hold) + leg) { [weak self] in
                self?.wear("mascot")
                self?.light(i)
            }
        }
    }

    private func at(_ when: Double, _ then: @escaping () -> Void) {
        let item = DispatchWorkItem(block: then)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + when, execute: item)
    }

    private func wear(_ named: String) {
        let picture = NSImage(named: named)
        picture?.isTemplate = true
        face.image = picture
    }

    /// The mark he has arrived at takes the ink, and gives a little under him.
    private func light(_ i: Int) {
        guard i < marks.count else { return }
        let mark = marks[i]
        mark.effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(mark.layer, to: Paint.picked)
        }
        if let glyph = mark.subviews.first as? NSImageView {
            glyph.contentTintColor = Paint.ink
        }
        names[i].textColor = Paint.body

        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [1, 1.14, 0.97, 1]
        swell.keyTimes = [0, 0.42, 0.74, 1]
        swell.duration = 0.42
        swell.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.1, 0.3, 1)
        mark.layer?.add(swell, forKey: "arrived")
    }

    /// The glyph is centred by hand for the same reason everything else here
    /// is: this is a drawing, not a form.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for mark in marks {
            guard let glyph = mark.subviews.first else { continue }
            glyph.frame = CGRect(x: (Walk.side - 22) / 2, y: (Walk.side - 22) / 2,
                                 width: 22, height: 22)
        }
        if window == nil { stop() }
    }
}

/// Kliner takes three things away and brings them back to where they were.
///
/// This is the one promise the whole app rests on, and it was four rows of
/// prose saying so. Then it was three squares moving on their own, which is a
/// diagram. Him walking over, taking them, putting them in the folder, and
/// walking them back out to exactly where they started is the promise being
/// kept in front of you, on a loop, and it needs no sentence at all.
final class Undoing: NSView {
    private let face = NSImageView()
    private var things: [NSView] = []
    private let folder = NSView()
    private let caption = NSTextField(labelWithString: "")
    private var pending: [DispatchWorkItem] = []
    private var running = false

    private static let him: CGFloat = 40
    private static let box: CGFloat = 20

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        folder.wantsLayer = true
        folder.layer?.cornerRadius = 7
        folder.layer?.borderWidth = 1.5
        addSubview(folder)

        for _ in 0..<3 {
            let thing = NSView()
            thing.wantsLayer = true
            thing.layer?.cornerRadius = 4
            addSubview(thing)
            things.append(thing)
        }

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        face.imageScaling = .scaleProportionallyUpOrDown
        face.wantsLayer = true
        addSubview(face)

        caption.font = Words.tiny
        caption.textColor = Paint.faint
        caption.alignment = .center
        addSubview(caption)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 104),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    deinit { stop() }

    private func stop() {
        for item in pending { item.cancel() }
        pending = []
        running = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    private func paint() {
        face.contentTintColor = Paint.ink
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.folder.layer?.borderColor = Paint.faint.cgColor
            for thing in self.things { thing.layer?.backgroundColor = Paint.ink.cgColor }
        }
    }

    /// Frames, because this is a figure and some boxes, not a form.
    private var pile: CGFloat { (bounds.width - 250) / 2 }
    private var away: CGFloat { pile + 190 }

    override func layout() {
        super.layout()
        let box = Undoing.box
        for (i, thing) in things.enumerated() {
            thing.frame = CGRect(x: pile + CGFloat(i) * (box + 8), y: 40,
                                 width: box, height: box)
        }
        folder.frame = CGRect(x: away, y: 32, width: 60, height: 36)
        face.frame = CGRect(x: pile - 58, y: 32, width: Undoing.him, height: Undoing.him)
        caption.frame = CGRect(x: 0, y: 8, width: bounds.width, height: 16)
    }

    /// One round: over to the pile, the three of them into the folder, back
    /// out again, and everything exactly where it started. Then again.
    func play(after wait: Double) {
        stop()
        layoutSubtreeIfNeeded()
        guard bounds.width > 0 else { return }
        running = true
        at(wait) { [weak self] in self?.round() }
    }

    private func round() {
        guard running, window != nil else { return }
        let carry = away - pile + 6

        // Every leg says where it starts as well as where it ends. A layer
        // animation with only a toValue begins at the model value, which never
        // moves, so each new leg would snap him back to the beginning first.
        say("he takes them")
        step(face, from: 0, to: 40, in: 0.5, facing: "mascot-right")
        for (i, thing) in things.enumerated() {
            slide(thing, from: 0, to: carry - CGFloat(i) * (Undoing.box + 8),
                  at: 0.46 + Double(i) * 0.1, over: 0.54, small: true)
        }
        at(0.5) { [weak self] in
            self?.step(self?.face, from: 40, to: carry - 8, in: 0.62, facing: "mascot-right")
        }

        at(1.6) { [weak self] in self?.say("and puts them back where they were") }
        for (i, thing) in things.enumerated() {
            slide(thing, from: carry - CGFloat(i) * (Undoing.box + 8), to: 0,
                  at: 1.78 + Double(i) * 0.1, over: 0.58, small: false)
        }
        at(1.7) { [weak self] in
            self?.step(self?.face, from: carry - 8, to: 40, in: 0.62, facing: "mascot-left")
        }
        at(2.6) { [weak self] in
            self?.step(self?.face, from: 40, to: 0, in: 0.5, facing: "mascot-left")
        }
        at(3.2) { [weak self] in self?.wear("mascot") }

        at(4.6) { [weak self] in self?.round() }
    }

    private func say(_ text: String) {
        caption.stringValue = text
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0
        show.toValue = 1
        show.duration = 0.3
        caption.wantsLayer = true
        caption.layer?.add(show, forKey: "saying")
    }

    private func step(_ who: NSView?, from: CGFloat, to x: CGFloat,
                      in time: Double, facing: String) {
        guard let who = who else { return }
        wear(facing)
        let across = CABasicAnimation(keyPath: "transform.translation.x")
        across.fromValue = from
        across.toValue = x
        across.duration = time
        across.fillMode = .both
        across.isRemovedOnCompletion = false
        across.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        who.layer?.add(across, forKey: "walking")

        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = 0
        bob.toValue = 4
        bob.duration = 0.17
        bob.autoreverses = true
        bob.repeatCount = Float(time / 0.34)
        who.layer?.add(bob, forKey: "bobbing")
    }

    private func slide(_ thing: NSView, from: CGFloat, to x: CGFloat, at when: Double,
                       over time: Double, small: Bool) {
        at(when) {
            let across = CABasicAnimation(keyPath: "transform.translation.x")
            across.fromValue = from
            across.toValue = x
            across.duration = time
            across.fillMode = .both
            across.isRemovedOnCompletion = false
            across.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            thing.layer?.add(across, forKey: "carried")

            let size = CABasicAnimation(keyPath: "transform.scale")
            size.fromValue = small ? 1 : 0.55
            size.toValue = small ? 0.55 : 1
            size.duration = time
            size.fillMode = .both
            size.isRemovedOnCompletion = false
            thing.layer?.add(size, forKey: "shrinking")
        }
    }

    private func wear(_ named: String) {
        let picture = NSImage(named: named)
        picture?.isTemplate = true
        face.image = picture
    }

    private func at(_ when: Double, _ then: @escaping () -> Void) {
        let item = DispatchWorkItem(block: then)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + when, execute: item)
    }
}

/// How far in you are, said rather than drawn: a ring that fills as you go
/// and the words beside it.
///
/// Four dots at the bottom of the page were a decoration you had to count.
/// Every one of the three flows this was taken from puts the step at the top
/// of the working pane and writes it out, because "Step 2 of 4" is read in one
/// glance and four dots are not.
final class Marker: NSView {
    private let ring = CAShapeLayer()
    private let done = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")
    private let many: Int

    init(of count: Int) {
        many = max(1, count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        for arc in [ring, done] {
            arc.fillColor = NSColor.clear.cgColor
            arc.lineWidth = 1.6
            arc.lineCap = .round
            layer?.addSublayer(arc)
        }

        label.font = Words.small
        label.textColor = Paint.faint
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.ring.strokeColor = Paint.line.cgColor
            self.done.strokeColor = Paint.ink.cgColor
        }
    }

    override func layout() {
        super.layout()
        // Drawn as an arc that begins at the top and goes round clockwise,
        // rather than a circle turned a quarter afterwards: rotating the layer
        // turns it about the middle of this whole view, not about the ring.
        let middle = CGPoint(x: 8, y: bounds.height / 2)
        let round = CGMutablePath()
        round.addArc(center: middle, radius: 7,
                     startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2, clockwise: true)
        ring.frame = bounds
        done.frame = bounds
        ring.path = round
        done.path = round
    }

    func say(_ step: Int) {
        label.stringValue = "Step \(min(step + 1, many)) of \(many)"
        done.strokeEnd = CGFloat(min(step + 1, many)) / CGFloat(many)
    }
}

// MARK: - the face, drifting

/// The face on the welcome page: Kliner's own mark, on the page itself with
/// nothing drawn behind it. A disc under it made it a logo on a slide; loose
/// on the paper it reads as somebody standing there.
final class Floating: NSView {
    private let face = NSImageView()

    /// How wide the mark is drawn.
    init(size: CGFloat = 74) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        face.imageScaling = .scaleProportionallyUpOrDown
        face.wantsLayer = true
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: size + 28),
            face.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: size),
            face.heightAnchor.constraint(equalToConstant: size),
        ])

        paint()
        drift()
        blinkLater()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    private var pending: Timer?
    private var asking = false
    deinit { pending?.invalidate() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        face.contentTintColor = Paint.ink
    }

    // MARK: moving

    /// Said to the face when the page under it changes. It leans over, looks
    /// at what is now written there, and settles back — the reason the setup
    /// reads as somebody showing you round rather than four pages of text.
    func nod() {
        let lean = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        lean.values = [0, -0.26, 0.10, -0.04, 0]
        lean.keyTimes = [0, 0.30, 0.62, 0.84, 1]
        lean.duration = 0.74
        lean.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(lean, forKey: "nodding")

        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 11, -4, 1, 0]
        hop.keyTimes = [0, 0.30, 0.62, 0.84, 1]
        hop.duration = 0.74
        hop.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(hop, forKey: "hopping")

        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [1, 1.09, 0.97, 1]
        swell.keyTimes = [0, 0.30, 0.66, 1]
        swell.duration = 0.74
        swell.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(swell, forKey: "swelling")

        // It blinks on arrival, because a thing that moves and does not blink
        // is a picture being dragged about.
        guard !asking else { return }
        pending?.invalidate()
        step(["mascot-half", "mascot-blink", "mascot-half", "mascot"], 0)
    }

    /// The page changed under him, so the head goes with it, and only the
    /// head. Going back is going left, so the head is thrown to the right and
    /// springs home; forward throws it the other way. Moving the head and the
    /// words together is the whole page lurching, which is what it was doing.
    ///
    /// No rotation in here on purpose: drift is already turning him on that
    /// key, and two animations on one key fight rather than add. This squashes
    /// instead, which is what a thing being pulled about actually does.
    func lean(_ way: CGFloat) {
        guard way != 0, !asking else { return }
        let side = -way * 30

        let across = CAKeyframeAnimation(keyPath: "transform.translation.x")
        across.values = [side, side * 0.30, -side * 0.09, side * 0.02, 0]
        across.keyTimes = [0, 0.40, 0.68, 0.86, 1]
        across.duration = 0.60
        across.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        face.layer?.add(across, forKey: "leaning")

        let wide = CAKeyframeAnimation(keyPath: "transform.scale.x")
        wide.values = [1.13, 0.96, 1.02, 1]
        wide.keyTimes = [0, 0.44, 0.74, 1]
        wide.duration = 0.60
        wide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        face.layer?.add(wide, forKey: "stretching")

        let tall = CAKeyframeAnimation(keyPath: "transform.scale.y")
        tall.values = [0.88, 1.04, 0.99, 1]
        tall.keyTimes = [0, 0.44, 0.74, 1]
        tall.duration = 0.60
        tall.timingFunction = CAMediaTimingFunction(name: .easeOut)
        face.layer?.add(tall, forKey: "squashing")

        pending?.invalidate()
        step(["mascot-half", "mascot-blink", "mascot-half", "mascot"], 0)
    }

    /// The first time anybody sees him: up out of nothing, overshooting, and
    /// then the words. Every page after this one he is already here, so this
    /// happens once.
    func arrive() {
        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [0.35, 1.14, 0.97, 1]
        swell.keyTimes = [0, 0.62, 0.85, 1]
        swell.duration = 0.72
        swell.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.1, 0.3, 1)
        face.layer?.add(swell, forKey: "arriving")

        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0
        show.toValue = 1
        show.duration = 0.42
        face.layer?.add(show, forKey: "showing")

        pending?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, !self.asking else { return }
            self.step(["mascot-half", "mascot-blink", "mascot-half", "mascot"], 0)
        }
    }

    /// The last page, where there is one thing left to do. The face stops
    /// drifting and starts asking: a bigger bob on a quicker clock, and its
    /// eyes go round and stay round. A button that throbs on a page this
    /// quiet is shouting; a face that looks up at you is not.
    func beckon() {
        face.layer?.removeAnimation(forKey: "drifting")
        face.layer?.removeAnimation(forKey: "tilting")
        pending?.invalidate()
        face.image = NSImage(named: "mascot-round")
        face.image?.isTemplate = true
        asking = true

        let hop = CABasicAnimation(keyPath: "transform.translation.y")
        hop.fromValue = -3
        hop.toValue = 7
        hop.duration = 0.62
        hop.autoreverses = true
        hop.repeatCount = .infinity
        hop.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(hop, forKey: "asking")

        let tip = CABasicAnimation(keyPath: "transform.rotation.z")
        tip.fromValue = -0.09
        tip.toValue = 0.09
        tip.duration = 0.95
        tip.autoreverses = true
        tip.repeatCount = .infinity
        tip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(tip, forKey: "tipping")
    }

    /// Back off the last page, so he stops asking. Without this he kept the
    /// round eyes and the bigger bob on a page that was not asking for
    /// anything, and would not lean when the page changed either, because
    /// leaning steps aside for asking.
    func relax() {
        guard asking else { return }
        asking = false
        face.layer?.removeAnimation(forKey: "asking")
        face.layer?.removeAnimation(forKey: "tipping")
        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        drift()
        blinkLater()
    }

    /// Never still: up and down on one clock, leaning on another that does not
    /// divide into it, so the two never line up and it never looks like a loop.
    private func drift() {
        let up = CABasicAnimation(keyPath: "transform.translation.y")
        up.fromValue = -6
        up.toValue = 6
        up.duration = 2.4
        up.autoreverses = true
        up.repeatCount = .infinity
        up.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer?.add(up, forKey: "drifting")

        let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = -0.055
        tilt.toValue = 0.055
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
            guard let self = self, self.window != nil, !self.asking else { return }
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


/// The scrolling half of the window, which also listens for a sideways push.
///
/// Two fingers on a trackpad, or a sideways wheel on a mouse, is how a Mac
/// says "the one before" and "the one after". The setup is four pages and the
/// app is a list of them, so both of those are somewhere to go.
final class Pages: NSScrollView {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    /// Enough sideways to be meant. Below this it is a hand resting on the
    /// trackpad while reading.
    private static let enough: CGFloat = 55

    private var sideways: CGFloat = 0
    private var spent = false

    override func scrollWheel(with event: NSEvent) {
        // A wheel with no phase is a mouse wheel, and a mouse wheel that goes
        // sideways is a sideways push in one event rather than a gesture.
        guard event.phase != [] || event.momentumPhase != [] else {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 2,
               abs(event.scrollingDeltaX) > 6 {
                answer(event.scrollingDeltaX)
                return
            }
            super.scrollWheel(with: event)
            return
        }

        if event.phase.contains(.began) {
            sideways = 0
            spent = false
        }

        // Only a push that is mostly sideways. Reading down a long page with a
        // thumb drifting left is not a request to leave it.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            sideways += event.scrollingDeltaX
        }

        if !spent, abs(sideways) > Pages.enough {
            spent = true
            answer(sideways)
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            sideways = 0
        }

        super.scrollWheel(with: event)
    }

    /// A trackpad pushed left moves the page left, which is the next one; the
    /// scrolling delta is positive going the other way, so this reads the way
    /// round a Mac does.
    private func answer(_ delta: CGFloat) {
        if delta > 0 { onBack?() } else { onForward?() }
    }
}

// MARK: - lists that open inside the window

/// One line of a list that has opened: a tick where the current one is, what
/// it is, and a quiet word about it underneath if there is one.
final class Pick: NSView {
    var onClick: (() -> Void)?

    private var hovering = false

    init(_ title: String, note: String?, on: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        let tick = NSImageView()
        if on, let picture = NSImage(systemSymbolName: "checkmark",
                                     accessibilityDescription: nil) {
            picture.isTemplate = true
            tick.image = picture
        }
        tick.contentTintColor = Paint.ink
        tick.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tick)

        let name = NSTextField(labelWithString: title)
        name.font = on ? Words.strong : Words.body
        name.textColor = Paint.ink
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        NSLayoutConstraint.activate([
            tick.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Step.tight),
            tick.widthAnchor.constraint(equalToConstant: 11),
            tick.heightAnchor.constraint(equalToConstant: 11),
            name.leadingAnchor.constraint(equalTo: tick.trailingAnchor, constant: Step.tight),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                           constant: -Step.close),
        ])

        guard let said = note, !said.isEmpty else {
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 28),
                tick.centerYAnchor.constraint(equalTo: centerYAnchor),
                name.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            repaint()
            return
        }

        let under = NSTextField(labelWithString: said)
        under.font = Words.small
        under.textColor = Paint.muted
        under.lineBreakMode = .byTruncatingTail
        under.translatesAutoresizingMaskIntoConstraints = false
        addSubview(under)

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: topAnchor, constant: Step.tight),
            tick.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            under.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            under.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            under.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                            constant: -Step.close),
            under.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Step.tight),
        ])
        repaint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { onClick?() }
    override func resetCursorRects() {
        if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: self.hovering ? Paint.hover : NSColor.clear)
        }
    }
}

/// A list that opens under the thing it belongs to, drawn by Kliner rather
/// than handed to the menu server: the same rows, hairlines and fills as
/// everything else in the window, instead of a system menu that belongs to a
/// different application.
enum Sheet {
    struct Line {
        let title: String
        let note: String?
        let on: Bool
        let head: Bool
        let pick: (() -> Void)?

        init(_ title: String, note: String? = nil, on: Bool = false,
             head: Bool = false, pick: (() -> Void)? = nil) {
            self.title = title
            self.note = note
            self.on = on
            self.head = head
            self.pick = pick
        }

        /// A word over a group of lines, so one list can hold three things.
        static func over(_ title: String) -> Line { Line(title, head: true) }
    }

    /// The one that is open, so opening another closes it.
    private static var showing: NSPopover?

    static func hide() {
        showing?.performClose(nil)
        showing = nil
    }

    /// `under` is what it belongs to, not where it goes. A list belonging to
    /// something at the bottom of a window has to open upwards, or it opens
    /// off the window and over the desktop, which is what it did.
    static func open(_ lines: [Line], under view: NSView, wide: CGFloat = 240) {
        hide()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: Step.tight, left: Step.tight,
                                        bottom: Step.tight, right: Step.tight)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (i, line) in lines.enumerated() {
            if line.head {
                let over = NSTextField(labelWithString: line.title)
                over.font = Words.small
                over.textColor = Paint.faint
                over.translatesAutoresizingMaskIntoConstraints = false
                let holder = NSView()
                holder.translatesAutoresizingMaskIntoConstraints = false
                holder.addSubview(over)
                NSLayoutConstraint.activate([
                    over.leadingAnchor.constraint(equalTo: holder.leadingAnchor,
                                                  constant: Step.tight),
                    over.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
                    over.topAnchor.constraint(equalTo: holder.topAnchor,
                                              constant: i == 0 ? 2 : Step.close),
                    over.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -2),
                ])
                stack.addArrangedSubview(holder)
                holder.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                              constant: -Step.air).isActive = true
                continue
            }

            let row = Pick(line.title, note: line.note, on: line.on)
            if let chosen = line.pick {
                row.onClick = {
                    hide()
                    chosen()
                }
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                       constant: -Step.air).isActive = true
        }

        stack.widthAnchor.constraint(equalToConstant: wide).isActive = true

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false

        // How tall it is allowed to be: what the window can hold, less the
        // room its own edges want. Everything Kliner can do, everything this
        // page can do, everything he has done and the keys is a long list, and
        // a long list with no ceiling opened past the top of the window and
        // out over the desktop. Past the ceiling it scrolls instead.
        let ceiling = max(260, (view.window?.contentView?.bounds.height ?? 620) - Step.edge * 3)
        let wants = stack.fittingSize.height

        if wants > ceiling {
            let scroller = NSScrollView()
            scroller.hasVerticalScroller = true
            scroller.autohidesScrollers = true
            scroller.borderType = .noBorder
            scroller.drawsBackground = false
            scroller.contentView = TopClip()
            scroller.translatesAutoresizingMaskIntoConstraints = false
            scroller.documentView = stack
            holder.addSubview(scroller)
            NSLayoutConstraint.activate([
                holder.widthAnchor.constraint(equalToConstant: wide),
                holder.heightAnchor.constraint(equalToConstant: ceiling),
                scroller.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                scroller.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                scroller.topAnchor.constraint(equalTo: holder.topAnchor),
                scroller.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor),
                stack.topAnchor.constraint(equalTo: scroller.contentView.topAnchor),
            ])
        } else {
            holder.addSubview(stack)
            NSLayoutConstraint.activate([
                holder.widthAnchor.constraint(equalToConstant: wide),
                stack.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                stack.topAnchor.constraint(equalTo: holder.topAnchor),
                stack.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
        }

        let inside = NSViewController()
        inside.view = holder

        let sheet = NSPopover()
        sheet.contentViewController = inside
        sheet.behavior = .transient
        sheet.animates = true
        showing = sheet

        // AppKit's y grows upward, so .minY is below the thing and .maxY is
        // above it. Below, unless the thing is in the bottom third of the
        // window it is in.
        var side = NSRectEdge.minY
        if let room = view.window?.contentView {
            let mine = view.convert(view.bounds, to: room)
            if mine.midY < room.bounds.height / 3 { side = .maxY }
        }
        sheet.show(relativeTo: view.bounds, of: view, preferredEdge: side)

        // The list arrives the way the page does: each line a moment after the
        // one before it, from the side the list opened on. A panel that simply
        // appears whole is the thing that reads as a menu dropped on the
        // window rather than something Kliner is handing you.
        stack.layoutSubtreeIfNeeded()
        let start = CACurrentMediaTime() + 0.03
        for (i, row) in stack.arrangedSubviews.enumerated() {
            row.wantsLayer = true
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = side == .maxY ? -8 : 8
            rise.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let both = CAAnimationGroup()
            both.animations = [rise, fade]
            both.duration = 0.26
            both.beginTime = start + Double(min(i, 12)) * 0.018
            both.fillMode = .backwards
            both.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            row.layer?.add(both, forKey: "arriving")
        }
    }
}

// MARK: - the top bar

/// The search field along the top: a magnifier, a line to type on, and the
/// keystroke that gets you there written on the right, so nobody has to be
/// told it exists.
final class Seek: NSView, NSTextFieldDelegate {
    var onType: ((String) -> Void)?
    var onGo: (() -> Void)?

    private let field = NSTextField()
    private let glass = NSImageView()
    private let badge = NSTextField(labelWithString: "⌘F")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1

        if let picture = NSImage(systemSymbolName: "magnifyingglass",
                                 accessibilityDescription: nil) {
            picture.isTemplate = true
            glass.image = picture
        }
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Words.body
        field.placeholderString = "Search"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        let key = badge
        key.font = Words.tiny
        key.textColor = Paint.faint
        key.alignment = .center
        key.wantsLayer = true
        key.layer?.cornerRadius = 5
        key.translatesAutoresizingMaskIntoConstraints = false
        addSubview(key)

        NSLayoutConstraint.activate([
            // Room for the text that is in it. Twenty-six was right when the
            // running text was thirteen points; at fourteen it is a field
            // holding its own line too tightly.
            heightAnchor.constraint(equalToConstant: 30),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            glass.centerYAnchor.constraint(equalTo: centerYAnchor),
            glass.widthAnchor.constraint(equalToConstant: 12),
            glass.heightAnchor.constraint(equalToConstant: 12),

            field.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.trailingAnchor.constraint(equalTo: key.leadingAnchor, constant: -6),

            key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            key.centerYAnchor.constraint(equalTo: centerYAnchor),
            key.widthAnchor.constraint(equalToConstant: 27),
            key.heightAnchor.constraint(equalToConstant: 16),
        ])

        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue; onType?(newValue) }
    }

    /// ⌘K, and clicking anywhere on the field, both land here.
    func focus() {
        window?.makeFirstResponder(field)
    }

    override func mouseDown(with event: NSEvent) { focus() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }

    func controlTextDidChange(_ obj: Notification) {
        onType?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onGo?()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            field.stringValue = ""
            onType?("")
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        glass.contentTintColor = Paint.faint
        field.textColor = Paint.ink
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Enough fill to read as a field. At a third of the hover colour
            // it was a word with a key floating beside it.
            self.layer?.backgroundColor = Paint.track.cgColor
            self.layer?.borderColor = Paint.line.cgColor
            self.badge.layer?.backgroundColor = Paint.picked.cgColor
        }
    }
}

// MARK: - cards, and the breakdowns inside them

/// Where you are, along the top: the place it belongs to, quietly, then the
/// page itself. When the place holds more than one page it is also the way to
/// the others, which is why there is no second row of tabs under it: the name
/// of the thing you are looking at is the obvious place to change it.
final class Trail: NSView {
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let arrow = NSImageView()
    private let mark = NSImageView()
    private var trailing: NSLayoutConstraint!
    private var more = false
    private var hovering = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        // Round at the top, square at the bottom, because the bottom is not
        // an edge: it is where the tab meets the page it names.
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        // A tab, not a caption. The page you are on is a thing hanging off
        // the row along the top onto the left edge of the page it names —
        // floating in the middle of the bar it read as a window title, which
        // is what the title bar already is.
        mark.contentTintColor = Paint.muted
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        if let picture = NSImage(systemSymbolName: "chevron.down",
                                 accessibilityDescription: nil) {
            picture.isTemplate = true
            arrow.image = picture
        }
        arrow.contentTintColor = Paint.faint
        arrow.isHidden = true
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        trailing = arrow.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                   constant: -Step.close)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 13),
            mark.heightAnchor.constraint(equalToConstant: 13),
            label.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 9),
            arrow.heightAnchor.constraint(equalToConstant: 9),
            trailing,
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    func set(_ line: NSAttributedString, more others: Bool) {
        label.attributedStringValue = line
        more = others
        arrow.isHidden = !others
        trailing.constant = others ? -Step.tight : -5
        repaint()
    }

    /// The picture on the tab: whichever place this page lives in.
    func wear(_ symbol: String) {
        guard let picture = NSImage(systemSymbolName: symbol,
                                    accessibilityDescription: nil) else { return }
        picture.isTemplate = true
        mark.image = picture
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard more else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { if more { onClick?() } }
    override func resetCursorRects() {
        if more { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.mark.contentTintColor = Paint.muted
            ease(self.layer, to: self.hovering && self.more ? Paint.track : Paint.picked)
        }
    }
}

/// The line under the card, on the glass: a dot that lights while Kliner is
/// reading, what it is doing in a few words, and the way to ask again.
///
/// Every window like this has one. It is the difference between an app that
/// is quietly doing something and an app that has stopped.
final class Strip: NSView {
    var onAgain: (() -> Void)?

    private let dot = NSView()
    private let said = NSTextField(labelWithString: "")
    private let again = Ghost("arrow.clockwise")
    private var lit = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        said.font = Words.tiny
        said.textColor = Paint.faint
        said.translatesAutoresizingMaskIntoConstraints = false
        addSubview(said)

        again.toolTip = "Read this again  ⌘R"
        again.onClick = { [weak self] in self?.onAgain?() }
        addSubview(again)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Step.page),

            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -78),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            said.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: Step.tight),
            said.centerYAnchor.constraint(equalTo: centerYAnchor),

            again.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Step.hair),
            again.centerYAnchor.constraint(equalTo: centerYAnchor),
            again.leadingAnchor.constraint(greaterThanOrEqualTo: said.trailingAnchor,
                                           constant: Step.close),
        ])
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    /// What it says, and whether the dot is lit.
    func say(_ words: String, busy: Bool) {
        said.stringValue = words
        lit = busy
        paint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.said.textColor = Paint.faint
            self.dot.layer?.backgroundColor =
                (self.lit ? Paint.ink : Paint.faint).withAlphaComponent(self.lit ? 0.9 : 0.4).cgColor
        }
        beat()
    }

    /// While it is reading the dot breathes, so a long read does not look
    /// like a stopped one.
    private func beat() {
        guard lit else {
            dot.layer?.removeAnimation(forKey: "beating")
            return
        }
        guard dot.layer?.animation(forKey: "beating") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "beating")
    }
}

/// The one thing the setup teaches that is not written anywhere else: two
/// fingers turn the page. A line of words nobody reads, with a chevron that
/// keeps setting off to the left and giving up, which is what the gesture
/// looks like.
final class Nudge: NSView {
    private let arrow = NSImageView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let said = NSTextField(labelWithString: "Swipe with two fingers, or press Next")
        said.font = Words.small
        said.textColor = Paint.faint
        said.translatesAutoresizingMaskIntoConstraints = false
        addSubview(said)

        if let picture = NSImage(systemSymbolName: "chevron.right",
                                 accessibilityDescription: nil) {
            picture.isTemplate = true
            arrow.image = picture
        }
        arrow.contentTintColor = Paint.faint
        arrow.wantsLayer = true
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            said.leadingAnchor.constraint(equalTo: leadingAnchor),
            said.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.leadingAnchor.constraint(equalTo: said.trailingAnchor, constant: Step.close),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 10),
            arrow.heightAnchor.constraint(equalToConstant: 10),
            arrow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, arrow.layer?.animation(forKey: "nudging") == nil else { return }

        // Toward the page it is taking you, not away from it.
        let go = CAKeyframeAnimation(keyPath: "transform.translation.x")
        go.values = [0, 7, 0, 0, 0]
        go.keyTimes = [0, 0.24, 0.44, 0.8, 1]
        go.duration = 2.1
        go.repeatCount = .infinity
        go.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arrow.layer?.add(go, forKey: "nudging")

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.45, 1, 0.45, 0.45, 0.45]
        fade.keyTimes = [0, 0.24, 0.44, 0.8, 1]
        fade.duration = 2.1
        fade.repeatCount = .infinity
        arrow.layer?.add(fade, forKey: "showing")
    }
}

/// Kliner, sitting in the corner of the page, waiting to be given something
/// to do.
///
/// It is where he lands when a job finishes: he does the waiting in the
/// middle of the page and then goes and sits down there, so the thing that
/// was working and the thing you hand work to are plainly the same thing.
final class Helper: NSView {
    /// How wide he sits in the corner. Big enough to be somebody standing
    /// there rather than a badge on the glass, and everything else in here is
    /// worked out from it rather than written down twice.
    static let across: CGFloat = 58

    var onClick: (() -> Void)?

    /// The dot is not decoration: it goes on when Kliner has done something
    /// since you last looked at him, and off the moment you have.
    var unread = false {
        didSet { dot.isHidden = !unread }
    }

    private let face = NSImageView()
    private let disc = NSView()
    private let dot = NSView()
    private var pending: Timer?
    private var hovering = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        disc.wantsLayer = true
        disc.layer?.cornerRadius = Helper.across / 2
        disc.layer?.borderWidth = 1
        disc.translatesAutoresizingMaskIntoConstraints = false
        addSubview(disc)

        let picture = NSImage(named: "mascot")
        picture?.isTemplate = true
        face.image = picture
        face.imageScaling = .scaleProportionallyUpOrDown
        face.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(face)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4.5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Helper.across),
            heightAnchor.constraint(equalToConstant: Helper.across),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
            disc.leadingAnchor.constraint(equalTo: leadingAnchor),
            disc.trailingAnchor.constraint(equalTo: trailingAnchor),
            disc.topAnchor.constraint(equalTo: topAnchor),
            disc.bottomAnchor.constraint(equalTo: bottomAnchor),
            face.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            face.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: Helper.across * 0.58),
            face.heightAnchor.constraint(equalToConstant: Helper.across * 0.58),
        ])

        toolTip = "Give Kliner something to do"
        paint()
        breathe()
        blinkLater()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    deinit { pending?.invalidate() }

    /// He comes across from wherever the waiting was and sits down. The
    /// distance is worked out when it runs, so it is right whatever size the
    /// window is.
    func land(from middle: CGPoint) {
        let mine = CGPoint(x: frame.midX, y: frame.midY)
        let across = CAKeyframeAnimation(keyPath: "transform")
        let start = CATransform3DMakeTranslation(middle.x - mine.x, middle.y - mine.y, 0)
        let over = CATransform3DConcat(CATransform3DMakeScale(2.6, 2.6, 1), start)
        across.values = [
            NSValue(caTransform3D: over),
            NSValue(caTransform3D: CATransform3DMakeScale(1.15, 1.15, 1)),
            NSValue(caTransform3D: CATransform3DIdentity),
        ]
        across.keyTimes = [0, 0.78, 1]
        across.duration = 0.66
        across.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer?.add(across, forKey: "landing")

        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 0.35
        show.toValue = 1
        show.duration = 0.4
        layer?.add(show, forKey: "arriving")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        paint()
        wear(["mascot-half", "mascot-blink", "mascot-half", "mascot-round"], 0)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        paint()
        wear(["mascot"], 0)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects()             { addCursorRect(bounds, cursor: .pointingHand) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        // He is the one thing you can hand work to, and in the corner of a
        // dark window at a fifth of the label colour on a barely-there disc he
        // read as a smudge on the glass rather than as somebody standing
        // there. Ink at rest, and a disc you can actually see the edge of.
        face.contentTintColor = Paint.ink
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.disc.layer?.borderColor = Paint.line.cgColor
            ease(self.disc.layer,
                 to: self.hovering ? Paint.picked : Paint.hover)
            self.disc.layer?.shadowColor = NSColor.black.cgColor
            self.disc.layer?.shadowOpacity = 0.22
            self.disc.layer?.shadowRadius = 10
            self.disc.layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
    }

    /// Barely: enough that the corner is alive, not enough to be movement in
    /// the corner of your eye while you are reading.
    private func breathe() {
        let up = CABasicAnimation(keyPath: "transform.translation.y")
        up.fromValue = -1.5
        up.toValue = 1.5
        up.duration = 2.8
        up.autoreverses = true
        up.repeatCount = .infinity
        up.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        disc.layer?.add(up, forKey: "breathing")
    }

    /// Blinking on its own is a thing twitching. Every so often he looks off
    /// to one side and back instead, which is what somebody waiting to be
    /// given something to do actually does.
    private static let idle: [[String]] = [
        ["mascot-half", "mascot-blink", "mascot-half", "mascot"],
        ["mascot-half", "mascot-blink", "mascot-half", "mascot"],
        ["mascot-left", "mascot-left", "mascot", "mascot"],
        ["mascot-right", "mascot-right", "mascot-half", "mascot"],
        ["mascot-round", "mascot-round", "mascot-half", "mascot"],
    ]

    private func blinkLater() {
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.5...8),
                                       repeats: false) { [weak self] _ in
            guard let self = self, self.window != nil, !self.hovering else { return }
            self.wear(Helper.idle.randomElement() ?? Helper.idle[0], 0)
        }
    }

    private func wear(_ faces: [String], _ i: Int) {
        guard i < faces.count else { blinkLater(); return }
        let picture = NSImage(named: faces[i])
        picture?.isTemplate = true
        face.image = picture
        // A blink is two frames of nothing; a look to the side is held. Same
        // list, told apart by whether the frame repeats itself.
        let held = i + 1 < faces.count && faces[i + 1] == faces[i]
        DispatchQueue.main.asyncAfter(deadline: .now() + (held ? 0.34 : 0.07)) {
            [weak self] in
            self?.wear(faces, i + 1)
        }
    }
}

/// One thing worth doing, as a line you can act on: a mark saying whether it
/// still wants doing, what it is, how much of it there is, and the one button
/// that does it.
///
/// A page of figures says how things are. A list of these says what to do
/// about it, which is the thing somebody opening a tidying app came for.
final class Job: NSView {
    var onDo: (() -> Void)?
    var onOpen: (() -> Void)?

    private let mark = NSImageView()
    private let tile = NSView()
    private let done: Bool
    private var hovering = false

    init(_ title: String, note: String, done: Bool, verb: String?,
         symbol: String = "circle", lead: Bool = false, spark: Spark.Kind? = nil) {
        self.done = done
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9

        // A hollow ring beside a line of text is a radio button, and three of
        // them in a column is a form asking you to pick one. These are jobs,
        // not choices: each one gets the mark of the place it is about, and a
        // tick once it is done.
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tile)

        // The weight is put on the image rather than on the image view: the
        // view's own symbolConfiguration wants a newer macOS than Kliner asks
        // for, and this one is the same picture.
        let shape = NSImage.SymbolConfiguration(pointSize: 13,
                                                weight: done ? .bold : .medium)
        if let picture = NSImage(systemSymbolName: done ? "checkmark" : symbol,
                                 accessibilityDescription: nil) {
            let drawn = picture.withSymbolConfiguration(shape) ?? picture
            drawn.isTemplate = true
            mark.image = drawn
        }
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        let name = NSTextField(labelWithString: title)
        name.font = Words.strong
        name.textColor = done ? Paint.muted : Paint.ink
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        let much = NSTextField(labelWithString: note)
        much.font = Words.small
        much.textColor = Paint.muted
        much.alignment = .right
        much.lineBreakMode = .byTruncatingTail
        much.translatesAutoresizingMaskIntoConstraints = false
        addSubview(much)

        // The row's own numbers, drawn. Which line is the big one becomes a
        // shape rather than two figures to compare.
        var picture: Spark?
        if let kind = spark {
            let drawn = Spark(kind, dim: done)
            addSubview(drawn)
            picture = drawn
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),

            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Step.tight),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 28),
            tile.heightAnchor.constraint(equalToConstant: 28),

            mark.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: tile.centerYAnchor),

            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: Step.close),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let word = verb {
            // One filled button on the page, on the first thing still to do.
            // Three of them in a column is three things shouting at once.
            let go = Chip(lead ? .strong : .quiet)
            go.set(word)
            go.onClick = { [weak self] in self?.onDo?() }
            go.translatesAutoresizingMaskIntoConstraints = false
            addSubview(go)
            NSLayoutConstraint.activate([
                go.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Step.tight),
                go.centerYAnchor.constraint(equalTo: centerYAnchor),
                much.trailingAnchor.constraint(equalTo: go.leadingAnchor, constant: -Step.close),
            ])
        } else {
            much.trailingAnchor.constraint(equalTo: trailingAnchor,
                                           constant: -Step.close).isActive = true
        }

        NSLayoutConstraint.activate([
            much.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let drawn = picture {
            // The picture keeps its place; the name gives way first, because a
            // truncated name is still readable and half a chart is not.
            NSLayoutConstraint.activate([
                drawn.centerYAnchor.constraint(equalTo: centerYAnchor),
                drawn.trailingAnchor.constraint(equalTo: much.leadingAnchor,
                                                constant: -Step.close),
                drawn.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor,
                                               constant: Step.close),
            ])
        } else {
            much.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor,
                                          constant: Step.close).isActive = true
        }

        repaint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// The row is the button, except where the button on the row is. The
    /// picture and the words inside it are controls, and a control eats the
    /// click it is handed.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for view in subviews where view is Chip {
            if view.frame.contains(local) { return view.hitTest(local) }
        }
        return self
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { onOpen?() }
    override func resetCursorRects() {
        if onOpen != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: self.hovering ? Paint.hover : NSColor.clear)
            // A job still to do is lifted off the card. A job already done
            // goes quiet, so what is left stands out on its own.
            self.tile.layer?.backgroundColor = self.done
                ? Paint.track.cgColor : Paint.wash.cgColor
            self.mark.contentTintColor = self.done ? Paint.muted : Paint.accent
        }
    }
}

/// Text with room between its lines. macOS sets a label tight, which is right
/// for a control and wrong for a paragraph: the difference between a window
/// somebody reads and a window somebody scans.
func leaded(_ text: String, _ font: NSFont, _ colour: NSColor) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    // Twenty-seven points on fourteen is what the picture sets its running
    // text at, and a paragraph set tighter than that is a paragraph people
    // skim rather than read.
    style.lineHeightMultiple = 1.55
    style.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: colour,
        .paragraphStyle: style,
    ])
}

/// Every panel in the window is the same panel: the same corner, the same
/// hairline, the same fill, the same air inside it. A window where one box is
/// rounded a little more than the next is a window somebody assembled rather
/// than drew.
enum Panel {
    static let round: CGFloat = 22
    static let pad: CGFloat = 22

    static func dress(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = round
        view.layer?.borderWidth = 1
        // A card is a thing standing on the page, so it is lit like one: an
        // opaque face and a shadow so faint it reads as an edge rather than
        // as a drop. It used to be a 40% tint of the hover colour, which on
        // most desktops was indistinguishable from the page under it.
        view.layer?.shadowOpacity = 1
        view.layer?.shadowRadius = 8
        view.layer?.shadowOffset = CGSize(width: 0, height: -1)
        view.layer?.masksToBounds = false
        paint(view)
    }

    /// A section of a page, drawn the way the site draws it: no box.
    ///
    /// A filled, rounded, shadowed slab makes a page read as a stack of
    /// containers. The same content under one hairline, with a small capital
    /// label over it, reads as one page that has parts — which is what it is.
    /// The frame was doing the work the label and the spacing should do.
    static func flat(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.borderWidth = 0
        view.layer?.shadowOpacity = 0
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// A card: a soft rounded rectangle a shade lighter than the page, no
    /// hairline round it and no shadow to speak of. The corner does the work
    /// an outline used to do.
    static func soft(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = round
        view.layer?.borderWidth = 0
        view.layer?.masksToBounds = false
        view.layer?.shadowOpacity = 1
        view.layer?.shadowRadius = 10
        view.layer?.shadowOffset = CGSize(width: 0, height: -1)
        colour(view)
    }

    static func colour(_ view: NSView) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = Paint.card.cgColor
            view.layer?.shadowColor = NSColor.black
                .withAlphaComponent(dark(view) ? 0.28 : 0.05).cgColor
        }
    }

    static func paint(_ view: NSView) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = Paint.panel.cgColor
            view.layer?.borderColor = Paint.line.cgColor
            view.layer?.shadowColor = NSColor.black
                .withAlphaComponent(dark(view) ? 0.34 : 0.07).cgColor
        }
    }

    /// Whether the Mac is in dark mode, asked of the view that is about to be
    /// painted. A shadow that works on white is invisible on slate.
    static func dark(_ view: NSView) -> Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The line over a card or a group: small, spaced, and in capitals, so it
    /// reads as a label on the thing rather than as the first sentence of it.
    static func label(_ words: String) -> NSTextField {
        let name = NSTextField(labelWithString: "")
        name.attributedStringValue = NSAttributedString(
            string: words,
            attributes: [.font: Words.body,
                         .foregroundColor: Paint.muted])
        name.translatesAutoresizingMaskIntoConstraints = false
        return name
    }
}

/// The breakdown as a row of bars, tallest first: the picture a dashboard is
/// built round, and here it is the same numbers the table under it lists.
///
/// It lays itself out rather than stacking constrained views, because a bar
/// chart is heights in proportion and proportions and gaps cannot both be
/// constraints without one of them being broken.
final class Bars: NSView {
    private let parts: [(name: String, size: Double)]
    private let asBytes: Bool
    private var poles: [NSView] = []
    private var names: [NSTextField] = []
    private var grown = false

    init(_ parts: [(name: String, size: Double)], bytes asBytes: Bool = true) {
        self.parts = Array(parts.prefix(12))
        self.asBytes = asBytes
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        for (i, part) in self.parts.enumerated() {
            let pole = NSView()
            pole.wantsLayer = true
            // Round like a lozenge, not like a brick with the corners taken
            // off: a bar chart where the bars are soft reads as a picture of
            // quantities rather than as a table stood on end.
            pole.layer?.cornerRadius = 11
            pole.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner,
                                         .layerMinXMinYCorner, .layerMaxXMinYCorner]
            pole.layer?.backgroundColor = Paint.band(min(i, 6)).cgColor
            pole.toolTip = asBytes ? "\(part.name)  \(size(part.size))"
                                   : "\(part.name)  \(Int(part.size.rounded()))"
            addSubview(pole)
            poles.append(pole)

            // The name under its own bar, cut to what fits rather than turned
            // on its side: a chart you have to tilt your head at is a chart.
            // Cut by the label, which stops at a width and marks it; cutting
            // the string itself at nine letters gave "Screensho".
            let under = NSTextField(labelWithString: part.name)
            under.font = Words.small
            under.textColor = Paint.faint
            under.alignment = .center
            under.lineBreakMode = .byTruncatingTail
            addSubview(under)
            names.append(under)
        }

        heightAnchor.constraint(equalToConstant: 168).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (i, pole) in self.poles.enumerated() {
                pole.layer?.backgroundColor = Paint.band(min(i, 6)).cgColor
            }
        }
    }

    override func layout() {
        super.layout()
        guard !poles.isEmpty else { return }
        let words: CGFloat = 18
        let air: CGFloat = 10
        let room = bounds.height - words
        let wide = (bounds.width - air * CGFloat(poles.count - 1)) / CGFloat(poles.count)
        let tallest = max(0.0001, parts.map { $0.size }.max() ?? 1)

        for (i, pole) in poles.enumerated() {
            let x = CGFloat(i) * (wide + air)
            // Nothing shorter than its own corner, or a small share draws as
            // a smudge on the floor rather than as a short bar.
            let tall = max(6, room * CGFloat(parts[i].size / tallest))
            pole.frame = NSRect(x: x, y: words, width: wide, height: tall)
            names[i].frame = NSRect(x: x - air / 2, y: 0,
                                    width: wide + air, height: 14)
        }
        grow()
    }

    /// The bars come up out of the floor, one after another. Twenty-five
    /// milliseconds apart is enough to read as a sweep and not enough to be a
    /// thing you wait for.
    private func grow() {
        guard !grown, window != nil else { return }
        grown = true
        for (i, pole) in poles.enumerated() {
            let up = CABasicAnimation(keyPath: "transform.scale.y")
            up.fromValue = 0
            up.toValue = 1
            up.duration = 0.42
            up.beginTime = CACurrentMediaTime() + Double(i) * 0.025
            up.fillMode = .backwards
            up.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            pole.layer?.anchorPoint = CGPoint(x: 0.5, y: 0)
            pole.layer?.position = CGPoint(x: pole.frame.midX, y: pole.frame.minY)
            pole.layer?.add(up, forKey: "growing")
        }
    }
}

/// A meter drawn as ticks rather than as one bar. It reads at a glance like a
/// bar and it counts like a number, which is what a figure with a ceiling
/// wants: you can see it is about two thirds without being told.
final class Meter: NSView {
    private let part: Double
    private let track = CALayer()
    private let bar = CALayer()
    private var filling = false

    init(_ part: Double) {
        self.part = min(1, max(0, part))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // It was thirty little ticks, which from a step back read as a
        // barcode rather than as an amount. One bar filling one way is the
        // shape everybody already knows how to read.
        //
        // Layers, not views: a sublayer keeps the anchor it is given, and the
        // bar has to grow from its left edge rather than from its middle.
        track.cornerRadius = 3
        bar.cornerRadius = 3
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(track)
        layer?.addSublayer(bar)

        heightAnchor.constraint(equalToConstant: 6).isActive = true
        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.track.backgroundColor = Paint.track.cgColor
            self.bar.backgroundColor = Paint.accent.cgColor
        }
    }

    /// The bar runs out to its number once, when the page arrives. A bar that
    /// is simply there is a picture of a bar; one that fills is a reading
    /// being taken.
    private func run() {
        guard !filling else { return }
        filling = true
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0
        grow.toValue = 1
        grow.duration = 0.62
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bar.add(grow, forKey: "filling")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { run() }
    }

    override func layout() {
        super.layout()
        // A sublayer is not laid out by AppKit, so it is placed here, and
        // without the implicit animation every frame change would otherwise
        // slide it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        let room = max(0, bounds.width)
        bar.bounds = CGRect(x: 0, y: 0,
                            width: max(3, room * CGFloat(part)), height: bounds.height)
        bar.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }
}

/// One figure with its name over it and its ceiling beside it: the box a
/// dashboard is built out of. Four of them across the top of a page say how
/// things stand before a single row of anything is read.
final class Metric: NSView {
    init(_ name: String, note: String, big: String,
         of whole: String? = nil, part: Double? = nil, pill: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Panel.flat(self)

        // No padding: these stand on the page rather than in a card, and a
        // figure inset from nothing is a figure that does not line up with
        // the heading above it.
        let edge: CGFloat = 0

        // The name of the figure, and under it the figure. The line of prose
        // that used to sit between them ("Space in use" under "Disk") said
        // what the name already said, and pushed the number it was explaining
        // down the card.
        let title = Panel.label(name)
        addSubview(title)

        let number = NSTextField(labelWithString: big)
        number.font = Words.figure
        number.textColor = Paint.ink
        number.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: edge),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                            constant: -Step.tight),
            title.topAnchor.constraint(equalTo: topAnchor, constant: edge),

            number.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            number.topAnchor.constraint(equalTo: title.bottomAnchor, constant: Step.tight),
        ])

        if let ceiling = whole {
            let ofIt = NSTextField(labelWithString: "of \(ceiling)")
            ofIt.font = Words.small
            ofIt.textColor = Paint.faint
            ofIt.translatesAutoresizingMaskIntoConstraints = false
            addSubview(ofIt)
            NSLayoutConstraint.activate([
                ofIt.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 5),
                ofIt.lastBaselineAnchor.constraint(equalTo: number.lastBaselineAnchor),
                ofIt.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                               constant: -Step.tight),
            ])
        } else {
            number.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                             constant: -edge).isActive = true
        }

        // A fact that belongs to the figure but is not the figure, set beside
        // it rather than under it.
        if let said = pill {
            let badge = Pill(said)
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 10),
                badge.centerYAnchor.constraint(equalTo: number.centerYAnchor),
                badge.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            ])
        }

        // The word under the number is the one that is worth reading: what
        // this figure is telling you. On the cards that are only a count it
        // is the whole explanation, so it stays.
        let under = NSTextField(labelWithString: note)
        under.font = Words.small
        under.textColor = Paint.muted
        under.lineBreakMode = .byTruncatingTail
        under.translatesAutoresizingMaskIntoConstraints = false
        addSubview(under)
        NSLayoutConstraint.activate([
            under.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            under.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                            constant: -Step.tight),
            under.topAnchor.constraint(equalTo: number.bottomAnchor, constant: Step.tight),
        ])

        if let share = part {
            let meter = Meter(share)
            addSubview(meter)
            NSLayoutConstraint.activate([
                meter.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                meter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Panel.pad),
                meter.topAnchor.constraint(equalTo: under.bottomAnchor, constant: Step.close),
                meter.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Panel.pad),
            ])
        } else {
            under.bottomAnchor.constraint(equalTo: bottomAnchor,
                                          constant: -Panel.pad - 5).isActive = true
        }

        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        Panel.flat(self)
    }
}

/// A section: a quiet title along the top, a hairline under it, the content
/// below, and room for a control opposite the title. Everything on a page
/// that is one subject goes in one of these, which is what makes a page read
/// as a few things rather than forty lines.
///
/// It used to be a rounded, filled, shadowed card. Four of those down a page
/// read as four containers somebody stacked; a label over a rule reads as one
/// page with parts in it.
final class Card: NSView {
    /// What goes inside, under the title.
    let body = NSStackView()

    init(_ title: String, trailing: NSView? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        Panel.soft(self)

        // A card's name is a name: sentence case, big enough to be the first
        // thing read on the card.
        let name = NSTextField(labelWithString: title)
        name.font = Words.cardName
        name.textColor = Paint.ink
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Panel.pad),
            name.topAnchor.constraint(equalTo: topAnchor, constant: Panel.pad),

            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Panel.pad),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Panel.pad),
            body.topAnchor.constraint(equalTo: name.bottomAnchor, constant: Step.close),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Panel.pad),
        ])

        if let control = trailing {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([
                control.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                  constant: -Panel.pad),
                control.centerYAnchor.constraint(equalTo: name.centerYAnchor),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor,
                                                 constant: 12),
            ])
        }

        paint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    /// One thing inside the card, as wide as the card allows.
    func add(_ view: NSView, gap: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        if gap > 0, body.arrangedSubviews.count > 1 {
            let above = body.arrangedSubviews[body.arrangedSubviews.count - 2]
            body.setCustomSpacing(gap, after: above)
        }
    }

    /// The line along the bottom of the card that takes you somewhere: a
    /// hairline, then words and an arrow, the whole width of it.
    func foot(_ words: String, _ action: @escaping () -> Void) {
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = Paint.line
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        add(rule, gap: 16)

        let way = Onward(words)
        way.onClick = action
        add(way, gap: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    private func paint() {
        Panel.colour(self)
    }
}

/// The way out of a card: words on the left, an arrow on the right, the whole
/// row live.
final class Onward: NSView {
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let arrow = NSImageView()
    private var hovering = false

    init(_ words: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        label.stringValue = words
        label.font = Words.strong
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        if let picture = NSImage(systemSymbolName: "arrow.right",
                                 accessibilityDescription: nil) {
            picture.isTemplate = true
            arrow.image = picture
        }
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 14),
            arrow.heightAnchor.constraint(equalToConstant: 14),
        ])

        repaint()
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { onClick?() }
    override func resetCursorRects()                { addCursorRect(bounds, cursor: .pointingHand) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        label.textColor = hovering ? Paint.ink : Paint.body
        arrow.contentTintColor = hovering ? Paint.ink : Paint.faint
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: hovering ? Paint.hover : NSColor.clear)
        }
    }
}

/// The number a card is about: large, with what it is under it and how it has
/// moved beside it.
final class Figure: NSView {
    /// `move` is the change, already worded; `good` decides its colour, and
    /// nil leaves it grey — nimo does not pretend to know whether every
    /// number moving is good news.
    init(_ big: String, caption: String, move: String? = nil, good: Bool? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let number = NSTextField(labelWithString: big)
        number.font = Words.figure
        number.textColor = Paint.ink
        number.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number)

        let under = NSTextField(labelWithString: caption)
        under.font = Words.small
        under.textColor = Paint.muted
        under.translatesAutoresizingMaskIntoConstraints = false
        addSubview(under)

        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor),
            number.topAnchor.constraint(equalTo: topAnchor),
            under.leadingAnchor.constraint(equalTo: leadingAnchor),
            under.topAnchor.constraint(equalTo: number.bottomAnchor, constant: 2),
            under.bottomAnchor.constraint(equalTo: bottomAnchor),
            under.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        guard let words = move else { return }

        let pill = NSTextField(labelWithString: words)
        pill.font = Words.tiny
        pill.textColor = good == nil ? Paint.muted : (good! ? Paint.muted : Paint.ink)
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 10),
            pill.lastBaselineAnchor.constraint(equalTo: number.lastBaselineAnchor),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

/// One bar cut into pieces by size, with what each piece is written under it.
/// The picture of a breakdown, above the table of the same thing.
///
/// The pieces are laid out by hand rather than by a stack view: proportional
/// widths and a gap between them cannot both be constraints without one of
/// them being broken, and a bar that is nearly in proportion is not a
/// breakdown of anything.
final class Split: NSView {
    private let parts: [(name: String, share: Double, colour: NSColor, note: String)]
    private var pieces: [NSView] = []

    init(_ parts: [(name: String, share: Double, colour: NSColor, note: String)]) {
        self.parts = parts.filter { $0.share > 0 }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let keys = NSStackView()
        keys.orientation = .horizontal
        keys.spacing = Step.wide
        keys.alignment = .top
        keys.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keys)

        for part in self.parts {
            let piece = NSView()
            piece.wantsLayer = true
            piece.layer?.cornerRadius = 12
            piece.layer?.backgroundColor = part.colour.cgColor
            addSubview(piece)
            pieces.append(piece)
            keys.addArrangedSubview(Key(part.name, part.colour, part.note))
        }

        // The slack goes at the end, so the entries stand together at the
        // left rather than being pushed to the corners of the card.
        let slack = NSView()
        slack.translatesAutoresizingMaskIntoConstraints = false
        slack.setContentHuggingPriority(.init(1), for: .horizontal)
        keys.addArrangedSubview(slack)

        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: leadingAnchor),
            keys.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            keys.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            keys.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func layout() {
        super.layout()
        let air: CGFloat = 3
        let whole = max(0.0001, parts.reduce(0) { $0 + $1.share })
        let room = max(0, bounds.width - air * CGFloat(max(0, pieces.count - 1)))
        var x: CGFloat = 0
        for (i, piece) in pieces.enumerated() {
            // Nothing narrower than its own corner radius, or a sliver of a
            // percent draws as a dot rather than as a piece of the bar.
            let wide = max(6, room * CGFloat(parts[i].share / whole))
            piece.frame = NSRect(x: x, y: bounds.height - 6, width: wide, height: 6)
            x += wide + air
        }
    }
}

/// A dot, a word and the figure it stands for: one entry of a legend, which
/// with the figure on it is the whole reading and not half of one.
final class Key: NSView {
    init(_ name: String, _ colour: NSColor, _ note: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = colour.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        let word = NSTextField(labelWithString: name)
        word.font = Words.small
        word.textColor = Paint.muted
        word.translatesAutoresizingMaskIntoConstraints = false
        addSubview(word)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.topAnchor.constraint(equalTo: word.topAnchor, constant: 5),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            word.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            word.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            word.topAnchor.constraint(equalTo: topAnchor),
        ])

        guard let figure = note else {
            NSLayoutConstraint.activate([
                word.trailingAnchor.constraint(equalTo: trailingAnchor),
                word.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            return
        }

        // Nothing was pulling the right-hand edge in, so three entries in a
        // row spread themselves across the whole card instead of standing
        // next to each other. This asks to be as wide as the wider of its two
        // lines, and gives way if the row has to be narrower than that.
        let hug = word.trailingAnchor.constraint(equalTo: trailingAnchor)
        hug.priority = .defaultLow

        let much = NSTextField(labelWithString: figure)
        much.font = Words.strong
        much.textColor = Paint.ink
        much.translatesAutoresizingMaskIntoConstraints = false
        addSubview(much)
        let hugToo = much.trailingAnchor.constraint(equalTo: trailingAnchor)
        hugToo.priority = .defaultLow
        NSLayoutConstraint.activate([
            much.leadingAnchor.constraint(equalTo: word.leadingAnchor),
            much.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            much.topAnchor.constraint(equalTo: word.bottomAnchor, constant: 1),
            much.bottomAnchor.constraint(equalTo: bottomAnchor),
            hug,
            hugToo,
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

/// One line of a breakdown: a colour, what it is, what share of the whole it
/// is, and how big it is. The three columns line up down the card, which is
/// the whole reason for reading it as a table rather than as sentences.
final class Ledger: NSView {
    var onOpen: (() -> Void)?

    private var hovering = false
    private let walkable: Bool

    init(colour: NSColor?, name: String, share: String, size: String,
         walkable: Bool = false, head: Bool = false) {
        self.walkable = walkable
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        let ink = head ? Paint.faint : Paint.body

        var left: NSLayoutXAxisAnchor = leadingAnchor
        var pad: CGFloat = 8
        if let shade = colour {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.backgroundColor = shade.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            addSubview(dot)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                dot.centerYAnchor.constraint(equalTo: centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
            ])
            left = dot.trailingAnchor
            pad = 10
        }

        let what = NSTextField(labelWithString: name)
        what.font = head ? Words.small : Words.strong
        what.textColor = head ? Paint.faint : Paint.ink
        what.lineBreakMode = .byTruncatingMiddle
        what.translatesAutoresizingMaskIntoConstraints = false
        addSubview(what)

        let part = NSTextField(labelWithString: share)
        part.font = head ? Words.small : Words.column
        part.textColor = ink
        part.alignment = .right
        part.translatesAutoresizingMaskIntoConstraints = false
        addSubview(part)

        let much = NSTextField(labelWithString: size)
        much.font = head ? Words.small : Words.column
        much.textColor = head ? Paint.faint : Paint.ink
        much.alignment = .right
        much.translatesAutoresizingMaskIntoConstraints = false
        addSubview(much)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: head ? 26 : 32),
            what.leadingAnchor.constraint(equalTo: left, constant: pad),
            what.centerYAnchor.constraint(equalTo: centerYAnchor),
            what.trailingAnchor.constraint(lessThanOrEqualTo: part.leadingAnchor, constant: -12),

            much.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            much.centerYAnchor.constraint(equalTo: centerYAnchor),
            much.widthAnchor.constraint(equalToConstant: 90),

            part.trailingAnchor.constraint(equalTo: much.leadingAnchor, constant: -16),
            part.centerYAnchor.constraint(equalTo: centerYAnchor),
            part.widthAnchor.constraint(equalToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard walkable else { return }
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard walkable else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { hovering = true;  repaint() }
    override func mouseExited(with event: NSEvent)  { hovering = false; repaint() }
    override func mouseDown(with event: NSEvent)    { if walkable { onOpen?() } }
    override func resetCursorRects() {
        if walkable { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        repaint()
    }

    private func repaint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ease(self.layer, to: self.hovering ? Paint.hover : NSColor.clear)
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
        big.font = Words.figure
        big.textColor = Paint.ink
        big.lineBreakMode = .byTruncatingTail
        big.translatesAutoresizingMaskIntoConstraints = false
        addSubview(big)

        let small = NSTextField(labelWithString: caption)
        small.font = Words.small
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

    /// And it draws nothing of its own.
    ///
    /// This is the brown. A scroll view told `drawsBackground = false` still
    /// has a clip view inside it that draws, and what it draws is
    /// `controlBackgroundColor` — a system colour, which macOS tints with the
    /// desktop wallpaper when "Allow wallpaper tinting in windows" is on. So
    /// the list down the side came out the colour of whatever photograph was
    /// behind the window, on a window with no glass left in it, over a slate
    /// painted specifically to stop exactly this. Every fix aimed at the
    /// window was aimed at the wrong view.
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
    }

    required init?(coder: NSCoder) { fatalError("Kliner has no nib") }
}

// MARK: - thinking

/// nimo, breathing, while it works. A spinner says a machine is busy; a face
/// that blinks says somebody is looking at the thing you asked about.
final class Thinking: NSView {
    /// Kliner's own outline, walked off the drawing of it: a hundred and
    /// eighty points around the edge, in fractions of the shape's own width,
    /// with y going up the way AppKit's does.
    ///
    /// Not a radius per angle, which cannot hold the notch at the bottom, and
    /// not a circle, which is not the shape. tools/outline.py writes these and
    /// the suite checks them against the drawing, so the ring and the face
    /// cannot drift apart.
    static let outline: [(CGFloat, CGFloat)] = [
        (-0.0457, 0.4714), (-0.0277, 0.4723), (-0.0094, 0.4724),
        (0.0087, 0.4718), (0.0266, 0.4706), (0.0441, 0.4685),
        (0.0611, 0.4651), (0.0775, 0.4604), (0.0935, 0.4547),
        (0.1091, 0.4480), (0.1241, 0.4400), (0.1387, 0.4308),
        (0.1527, 0.4204), (0.1659, 0.4088), (0.1780, 0.3961),
        (0.1891, 0.3824), (0.1991, 0.3682), (0.2081, 0.3535),
        (0.2162, 0.3385), (0.2236, 0.3232), (0.2309, 0.3078),
        (0.2392, 0.2929), (0.2492, 0.2788), (0.2609, 0.2658),
        (0.2740, 0.2543), (0.2883, 0.2444), (0.3031, 0.2360),
        (0.3183, 0.2283), (0.3337, 0.2211), (0.3492, 0.2140),
        (0.3646, 0.2069), (0.3800, 0.1997), (0.3952, 0.1922),
        (0.4101, 0.1836), (0.4245, 0.1741), (0.4386, 0.1637),
        (0.4519, 0.1519), (0.4642, 0.1388), (0.4749, 0.1249),
        (0.4836, 0.1101), (0.4906, 0.0946), (0.4958, 0.0784),
        (0.4988, 0.0613), (0.5000, 0.0434), (0.5000, 0.0252),
        (0.4990, 0.0072), (0.4967, -0.0102), (0.4930, -0.0271),
        (0.4882, -0.0435), (0.4827, -0.0596), (0.4766, -0.0754),
        (0.4697, -0.0909), (0.4623, -0.1062), (0.4540, -0.1212),
        (0.4450, -0.1358), (0.4359, -0.1504), (0.4264, -0.1649),
        (0.4164, -0.1791), (0.4065, -0.1934), (0.3977, -0.2081),
        (0.3902, -0.2234), (0.3838, -0.2391), (0.3781, -0.2551),
        (0.3730, -0.2714), (0.3680, -0.2877), (0.3631, -0.3040),
        (0.3581, -0.3204), (0.3527, -0.3365), (0.3466, -0.3523),
        (0.3398, -0.3679), (0.3323, -0.3832), (0.3238, -0.3980),
        (0.3136, -0.4122), (0.3015, -0.4254), (0.2882, -0.4373),
        (0.2740, -0.4473), (0.2591, -0.4557), (0.2436, -0.4626),
        (0.2274, -0.4680), (0.2104, -0.4713), (0.1927, -0.4724),
        (0.1748, -0.4716), (0.1574, -0.4692), (0.1407, -0.4653),
        (0.1245, -0.4601), (0.1087, -0.4537), (0.0933, -0.4465),
        (0.0783, -0.4384), (0.0635, -0.4298), (0.0489, -0.4208),
        (0.0343, -0.4116), (0.0198, -0.4030), (0.0053, -0.3978),
        (-0.0092, -0.3991), (-0.0238, -0.4060), (-0.0382, -0.4150),
        (-0.0528, -0.4242), (-0.0675, -0.4330), (-0.0824, -0.4416),
        (-0.0975, -0.4495), (-0.1130, -0.4564), (-0.1290, -0.4620),
        (-0.1456, -0.4663), (-0.1627, -0.4695), (-0.1801, -0.4715),
        (-0.1977, -0.4715), (-0.2150, -0.4694), (-0.2318, -0.4655),
        (-0.2480, -0.4602), (-0.2635, -0.4532), (-0.2782, -0.4445),
        (-0.2921, -0.4338), (-0.3048, -0.4215), (-0.3161, -0.4080),
        (-0.3260, -0.3937), (-0.3345, -0.3788), (-0.3418, -0.3635),
        (-0.3481, -0.3477), (-0.3537, -0.3316), (-0.3589, -0.3154),
        (-0.3639, -0.2991), (-0.3689, -0.2828), (-0.3742, -0.2666),
        (-0.3798, -0.2505), (-0.3858, -0.2347), (-0.3925, -0.2191),
        (-0.4004, -0.2040), (-0.4097, -0.1894), (-0.4196, -0.1751),
        (-0.4293, -0.1608), (-0.4387, -0.1463), (-0.4479, -0.1317),
        (-0.4563, -0.1168), (-0.4641, -0.1017), (-0.4715, -0.0864),
        (-0.4784, -0.0709), (-0.4843, -0.0550), (-0.4894, -0.0387),
        (-0.4936, -0.0221), (-0.4970, -0.0051), (-0.4992, 0.0124),
        (-0.5000, 0.0303), (-0.4992, 0.0482), (-0.4969, 0.0656),
        (-0.4931, 0.0824), (-0.4877, 0.0985), (-0.4808, 0.1141),
        (-0.4724, 0.1290), (-0.4623, 0.1432), (-0.4506, 0.1565),
        (-0.4375, 0.1688), (-0.4236, 0.1795), (-0.4089, 0.1886),
        (-0.3938, 0.1965), (-0.3786, 0.2041), (-0.3631, 0.2112),
        (-0.3475, 0.2178), (-0.3320, 0.2247), (-0.3166, 0.2320),
        (-0.3014, 0.2397), (-0.2865, 0.2479), (-0.2721, 0.2573),
        (-0.2589, 0.2684), (-0.2472, 0.2813), (-0.2370, 0.2953),
        (-0.2284, 0.3101), (-0.2212, 0.3255), (-0.2145, 0.3411),
        (-0.2073, 0.3565), (-0.1991, 0.3715), (-0.1901, 0.3862),
        (-0.1800, 0.4003), (-0.1684, 0.4138), (-0.1556, 0.4262),
        (-0.1418, 0.4373), (-0.1273, 0.4467), (-0.1121, 0.4543),
        (-0.0962, 0.4603), (-0.0799, 0.4653), (-0.0631, 0.4691),
    ]

    private let face = NSImageView()
    /// The whole outline, faint, so there is something for the bright part to
    /// travel along. One short arc on its own reads as a scratch on the page.
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    /// A longer, fainter piece going round the other way. Two arcs crossing
    /// on a shape is something turning over; one arc going round is a spinner
    /// wearing a costume.
    private let trail = CAShapeLayer()
    private var pending: Timer?

    /// How wide the face is drawn. The ring is worked out from this and the
    /// artwork, never guessed.
    static let across: CGFloat = 88

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let awake = NSImage(named: "mascot")
        awake?.isTemplate = true
        face.image = awake
        // Quiet. What moves is the light going round the edge of him; the
        // shape itself is only there to be gone round, and painted any
        // stronger it is a grey mass in the middle of an empty page.
        face.contentTintColor = Paint.faint
        face.imageScaling = .scaleProportionallyUpOrDown
        face.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.centerYAnchor.constraint(equalTo: centerYAnchor),
            face.widthAnchor.constraint(equalToConstant: Thinking.across),
            face.heightAnchor.constraint(equalToConstant: Thinking.across),
        ])

        layer?.addSublayer(track)
        layer?.addSublayer(trail)
        layer?.addSublayer(ring)
        breathe()
    }

    /// The blinking starts when the face is in a window, not when it is made.
    /// It is made as the argument to the call that puts it on the page, so at
    /// that moment it has no window, and asking for one there stopped the
    /// whole sequence before its first turn.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { blinkLater() } else { pending?.invalidate() }
    }

    required init?(coder: NSCoder) { fatalError("nimo has no nib") }

    deinit { pending?.invalidate() }

    /// The shape, as a path, at whatever size it is asked for. At `size` equal
    /// to the width the face is drawn at, the path lies on the face.
    static func path(around middle: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (i, point) in outline.enumerated() {
            let at = CGPoint(x: middle.x + point.0 * size,
                             y: middle.y + point.1 * size)
            if i == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        path.closeSubpath()
        return path
    }

    override func layout() {
        super.layout()
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        // One to one with the face: the same shape, at the same size, in the
        // same place. Not a ring round it, the edge of it.
        let shape = Thinking.path(around: middle, size: Thinking.across)

        for layer in [track, trail, ring] {
            layer.frame = bounds
            layer.path = shape
            layer.fillColor = nil
            layer.lineWidth = 2
            layer.lineCap = .round
            layer.lineJoin = .round
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.track.strokeColor = Paint.line.cgColor
            self.trail.strokeColor = Paint.accent.withAlphaComponent(0.35).cgColor
            self.ring.strokeColor = Paint.accent.cgColor
        }
        travel()
    }

    /// A short bright piece travelling along the faint whole. Sixteen per cent
    /// of the way round is long enough to read as movement and short enough
    /// not to read as a border.
    private func travel() {
        guard ring.animation(forKey: "travelling") == nil else { return }

        // The bright piece, going round. Sixteen per cent is long enough to
        // read as movement and short enough not to read as a border.
        send(ring, length: 0.16, seconds: 2.2, backwards: false)
        // And a longer, fainter one going the other way, half as fast, so the
        // two pass each other somewhere new every time.
        send(trail, length: 0.34, seconds: 3.7, backwards: true)
    }

    private func send(_ layer: CAShapeLayer, length: CGFloat,
                      seconds: Double, backwards: Bool) {
        layer.strokeStart = 0
        layer.strokeEnd = length

        let head = CABasicAnimation(keyPath: "strokeEnd")
        head.fromValue = backwards ? 1 : length
        head.toValue = backwards ? -length : 1 + length

        let tail = CABasicAnimation(keyPath: "strokeStart")
        tail.fromValue = backwards ? 1 - length : 0
        tail.toValue = backwards ? -2 * length : 1

        let both = CAAnimationGroup()
        both.animations = [head, tail]
        both.duration = seconds
        both.repeatCount = .infinity
        both.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(both, forKey: "travelling")
    }

    /// Slower than a spinner on purpose: Kliner is thinking, not straining.
    ///
    /// A fade and nothing else. Scaling the face was the obvious thing to do
    /// and the wrong one: the outline is drawn at the size the face is drawn,
    /// so a face that shrinks is a face that leaves its own outline behind.
    /// It blinks instead, which is the thing that says it is still there.
    private func breathe() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.62
        fade.duration = 1.45
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.wantsLayer = true
        face.layer?.add(fade, forKey: "fading")
    }

    /// The same movement the wordmark makes, in the same steps. Every step
    /// holds for as long as it says, including the last, so the bar always
    /// takes the same time to play.
    private func close(_ steps: [(String, Double)], then: @escaping () -> Void) {
        guard let (name, wait) = steps.first else { then(); return }
        let picture = NSImage(named: name)
        picture?.isTemplate = true
        face.image = picture
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self = self else { return }
            if steps.count == 1 { then(); return }
            self.close(Array(steps.dropFirst()), then: then)
        }
    }

    /// One bar, played over and over at the same tempo.
    ///
    /// It used to wait an unpredictable number of seconds and then play an
    /// unpredictable sequence, which reads as a thing twitching. A face that
    /// is thinking keeps time: shut, open, round, dashes, shut, and a rest,
    /// always the same length, so it becomes a rhythm you stop noticing and
    /// start being reassured by.
    private static let turn: [(String, Double)] = [
        ("mascot-half", 0.06), ("mascot-blink", 0.08), ("mascot-half", 0.06),
        ("mascot", 0.70),
        ("mascot-round", 0.50),
        ("mascot-dash", 0.50),
        ("mascot-half", 0.06), ("mascot-blink", 0.08), ("mascot-half", 0.06),
        ("mascot", 0.90),
    ]

    private func blinkLater() {
        pending?.invalidate()
        guard window != nil else { return }
        close(Thinking.turn) { [weak self] in
            guard let self = self, self.window != nil else { return }
            self.blinkLater()
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
        top.font = Words.body
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
        left.font = strong ? Words.strong : Words.body
        left.textColor = Paint.muted
        left.lineBreakMode = .byTruncatingTail
        left.translatesAutoresizingMaskIntoConstraints = false
        addSubview(left)

        let right = Wrapping(labelWithString: value)
        right.font = strong ? Words.head : Words.body
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

    /// The picture and the words are controls of their own, and a control eats
    /// the click it is given. This view is the button; nothing inside it is.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

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

        // On the screen before it has anything to say, so that what it has to
        // say is watched rather than missed. It fades up rather than being
        // there, which is the difference between an app arriving and an app
        // having been dropped on the desktop.
        let window = main.window
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        main.open()

        // The other half of the app: a mark in the menu bar, and ⌘K from
        // anywhere. The window is a place you go; this is a place you reach.
        Quick.shared.onOpenPage = { [weak self] index in self?.main.openPage(index) }
        Quick.shared.start()
    }

    /// Closing the window leaves the menu bar item behind, so ⌘K still
    /// works. Quit is what puts nimo away.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

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

        // ⌘K belongs to the quick menu now, everywhere, so searching inside
        // the window takes the key every other Mac app uses for finding.
        let find = NSMenuItem(title: "Search",
                              action: #selector(Main.focusSearch), keyEquivalent: "f")
        find.target = main
        look.addItem(find)

        // The same menu the key opens, for anybody who goes looking for it in
        // the menus instead of learning a shortcut.
        let quick = NSMenuItem(title: "Quick menu",
                               action: #selector(openQuick), keyEquivalent: "k")
        quick.target = self
        look.addItem(quick)

        // Ask this page again, rather than being shown what it said last time.
        let again = NSMenuItem(title: "Ask again",
                               action: #selector(Main.refresh), keyEquivalent: "r")
        again.target = main
        look.addItem(again)

        // The introduction, whenever you want to look at it.
        let intro = NSMenuItem(title: "Show the introduction",
                               action: #selector(Main.replaySetup), keyEquivalent: "")
        intro.target = main
        look.addItem(intro)
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

    @objc private func openQuick() { Quick.shared.toggle() }

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

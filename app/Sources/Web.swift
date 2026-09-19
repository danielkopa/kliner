//
//  app/Sources/Web.swift — the window, drawn by a page
//
//  Kliner's window is drawn by one page of HTML carried inside the app, in
//  Resources/web. The page draws; it never decides what runs. Everything it
//  asks for names a page by its number, and this file looks the command up
//  in `Action.all`, asks you with a real macOS dialog before anything
//  changes, and only then hands nimo `--yes`.
//
//  What the page cannot do, by construction:
//
//    - hand nimo an argument. It sends a page number; the arguments are
//      written in this app and nowhere else.
//    - skip the question. `--yes` is added here, after the dialog, never
//      because the page said so.
//    - reach the network. The page loads from the app's own folder, every
//      other address is refused before it is fetched, and nothing is stored.
//    - open a file. A thing it shows you is shown in the Finder, not run.
//    - read one. For Desktop and Downloads it is told names, sizes and
//      dates, and handed small pictures of the pictures there, drawn on
//      this side by the Mac's own image reader. Nothing else leaves a file.
//
//  The older window, drawn in AppKit, is still in main.swift. `ui = native`
//  in ~/.nimo/config brings it back.
//

import AppKit
import Foundation
import ImageIO
import WebKit

// MARK: - the surface the page is drawn on

/// A web view that knows which strip of it is a title bar.
///
/// The page runs right up under the three lights, the way every modern Mac
/// window does, so the top of it has to move the window like a title bar
/// would. The page says where its buttons are; everywhere else in the top
/// strip drags. Double-click does what the Mac is set to do.
final class Canvas: WKWebView {
    /// How tall the strip is, and the rectangles in it that are buttons.
    /// Both in the page's own points, measured from the top.
    var bar: CGFloat = 52
    var holes: [NSRect] = []

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let down = isFlipped ? point.y : bounds.height - point.y
        let spot = NSPoint(x: point.x, y: down)

        if down >= 0, down < bar, !holes.contains(where: { $0.contains(spot) }) {
            if event.clickCount == 2 {
                let wanted = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if wanted == "Minimize" {
                    window?.performMiniaturize(nil)
                } else if wanted != "None" {
                    window?.performZoom(nil)
                }
            } else {
                window?.performDrag(with: event)
            }
            return
        }
        super.mouseDown(with: event)
    }

    /// The first click on the window, while another app is in front, is a
    /// click and not only a way of bringing it forward. Nothing a single
    /// click reaches changes anything without the question after it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// No Reload, no Inspect Element: the page is the app, not a web page.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}

/// Holds the window weakly. The page's messages are handed to whoever is
/// listening, and a listener the page holds on to could never go away.
private final class Relay: NSObject, WKScriptMessageHandler {
    weak var to: WKScriptMessageHandler?

    init(_ to: WKScriptMessageHandler) {
        self.to = to
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        to?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - the window

final class Web: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let window: NSWindow
    private let view: Canvas

    /// Contents/Resources, and the page's own folder inside it.
    private let resources: URL
    private let folder: URL

    /// Whether the page has finished loading and can be spoken to.
    private var loaded = false
    /// A page asked for from ⌘K before the window had finished loading.
    private var owed: Int?
    /// One change at a time. Two runs of nimo moving files at once is two
    /// processes walking the same folder.
    private var changing = false

    /// The window's ground, the page's own: so there is no white flash
    /// while it loads, and no light edge on a dark window.
    private static let ground = NSColor(name: nil) { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.039, green: 0.039, blue: 0.039, alpha: 1)
            : NSColor(srgbRed: 0.980, green: 0.980, blue: 0.980, alpha: 1)
    }

    /// What macOS decides about, in the order the introduction asks.
    private static var gates: [(symbol: String, title: String, folder: URL?)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("menubar.dock.rectangle", "Your desktop", home.appendingPathComponent("Desktop")),
            ("arrow.down.circle", "Your downloads", home.appendingPathComponent("Downloads")),
            ("photo", "Your pictures", home.appendingPathComponent("Pictures")),
            ("doc.text", "Your documents", home.appendingPathComponent("Documents")),
            ("bell", "Notifications", nil),
        ]
    }

    override init() {
        let inside = Bundle.main.resourceURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
        resources = inside
        folder = inside.appendingPathComponent("web", isDirectory: true)

        let setup = WKWebViewConfiguration()
        // Nothing the page does is kept on disk: no cookies, no cache, no
        // storage. What Kliner remembers, it writes to ~/.nimo/config.
        setup.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        view = Canvas(frame: NSRect(x: 0, y: 0, width: 1240, height: 820), configuration: setup)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                      .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        super.init()

        window.title = "Kliner"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = Web.ground
        window.minSize = NSSize(width: 820, height: 560)
        window.delegate = self
        window.contentView = view

        // Where it was last time, or the middle of the screen the first time.
        if !window.setFrameUsingName("kliner.window") {
            window.center()
        }
        _ = window.setFrameAutosaveName("kliner.window")

        view.navigationDelegate = self
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        // Hidden until the page has drawn itself, so what appears is the
        // window and not an empty frame on its way to being one.
        view.isHidden = true
        view.configuration.userContentController.add(Relay(self), name: "kliner")

        let page = folder.appendingPathComponent("index.html")
        _ = view.loadFileURL(page, allowingReadAccessTo: resources)
    }

    /// The page asks for everything it needs when it has loaded.
    func open() {
        window.makeFirstResponder(view)
    }

    /// The menu behind ⌘K hands a page over. It never runs anything itself:
    /// the page says what it is about to do, and waits to be told yes.
    func openPage(_ index: Int) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard loaded else {
            owed = index
            return
        }
        command("open", index)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }

    // MARK: the menu along the top of the screen

    @objc func openSettings() { command("settings") }
    @objc func foldSide() { command("fold") }
    @objc func focusSearch() { Quick.shared.show() }
    @objc func refresh() { command("refresh") }
    @objc func replaySetup() { command("setup") }
    @objc func goBack() { command("back") }
    @objc func goForward() { command("forward") }
    @objc func goByNumber(_ sender: NSMenuItem) { command("open", sender.tag) }

    // MARK: loading

    /// The page, from the app's own folder, and nothing else — not a link it
    /// was given, not an address typed into it.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, isOurs(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        view.isHidden = false
        window.makeFirstResponder(view)
        if let page = owed {
            owed = nil
            command("open", page)
        }
    }

    /// If the page's process dies, draw it again rather than leave a blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        _ = webView.reload()
    }

    private func isOurs(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let inside = folder.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(inside + "/")
    }

    // MARK: talking to the page

    /// A value as a JavaScript literal. JSON is one, once the two line
    /// separators that JSON allows and older JavaScript does not are escaped.
    private func literal(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let text = String(data: data, encoding: .utf8),
              text.count >= 2 else { return "null" }
        let inner = String(text.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                    .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func reply(_ id: Int, _ payload: [String: Any]) {
        guard id > 0 else { return }
        view.evaluateJavaScript("window.kliner && window.kliner.reply(\(id), \(literal(payload)));",
                                completionHandler: nil)
    }

    private func command(_ name: String, _ argument: Any? = nil) {
        guard loaded else { return }
        let arg = argument.map { literal($0) } ?? "null"
        view.evaluateJavaScript("window.kliner && window.kliner.command(\(literal(name)), \(arg));",
                                completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // Only the window's own page may ask, from its own folder.
        guard message.frameInfo.isMainFrame,
              let from = message.frameInfo.request.url, isOurs(from),
              let body = message.body as? [String: Any],
              let op = body["op"] as? String else { return }
        let id = number(body, "id") ?? 0

        switch op {
        case "boot":        reply(id, boot())
        case "look":        look(body, id)
        case "go":          go(body, id)
        case "extra":       extra(body, id)
        case "tidy":        tidy(body, id)
        case "walls":       read(["wallpaper", "--list"], id)
        case "walk":        walk(body, id)
        case "show":        show(body)
        case "reveal":      reveal(body)
        case "list":        list(body, id)
        case "thumbs":      thumbs(body, id)
        case "picture":     picture(body, id)
        case "copies":      copies(body, id)
        case "stop":        stop(body, id)
        case "setConfig":   remember(body)
        case "settings":    reply(id, settings())
        case "setLogin":    login(body, id)
        case "fullDisk":    fullDisk(id)
        case "askFolders":  askFolders(id)
        case "automation":  Access.settings("Privacy_Automation")
        case "terminal":    terminal()
        case "quick":       Quick.shared.toggle()
        case "gate":        gate(body, id)
        case "finishSetup": finish(body, id)
        case "figures":     figures(body)
        case "chrome":      chrome(body)
        default:            reply(id, [:])
        }
    }

    // MARK: reading what the page sent

    private func number(_ body: [String: Any], _ key: String) -> Int? {
        (body[key] as? NSNumber)?.intValue
    }

    private func flag(_ body: [String: Any], _ key: String) -> Bool {
        (body[key] as? NSNumber)?.boolValue ?? false
    }

    private func words(_ body: [String: Any], _ key: String) -> String? {
        body[key] as? String
    }

    private func page(_ body: [String: Any]) -> Action? {
        guard let index = number(body, "page"), Action.all.indices.contains(index) else { return nil }
        return Action.all[index]
    }

    /// One name inside a folder: no separators, no way up, nothing that
    /// could be read as a switch, nothing that breaks a line.
    private static func plain(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\u{0}") && !name.hasPrefix("-")
            && name.rangeOfCharacter(from: .newlines) == nil
    }

    /// Text somebody typed, without anything that could start a new line in
    /// ~/.nimo/config, and not longer than it needs to be.
    private static func clean(_ text: String, limit: Int) -> String {
        var out = ""
        for scalar in text.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            out.unicodeScalars.append(scalar)
        }
        out = out.trimmingCharacters(in: .whitespaces)
        return String(out.prefix(limit))
    }

    // MARK: what there is

    private func boot() -> [String: Any] {
        var pages: [[String: Any]] = []
        for item in Action.all {
            var one: [String: Any] = [:]
            one["title"] = item.title
            one["blurb"] = item.blurb
            one["verb"] = item.verb
            one["kind"] = item.arguments.first ?? ""
            one["command"] = item.arguments.isEmpty ? "" : "min " + item.arguments.joined(separator: " ")
            one["asks"] = item.asks != nil
            one["group"] = item.group
            one["symbol"] = item.symbol
            one["does"] = item.does
            one["counts"] = item.counts
            one["reveal"] = item.reveal ?? ""
            one["walks"] = item.walks
            one["looksOnly"] = item.looksOnly
            var extras: [[String: Any]] = []
            for extra in item.extras {
                var ex: [String: Any] = [:]
                ex["title"] = extra.title
                ex["symbol"] = extra.symbol ?? ""
                ex["asks"] = extra.asks != nil
                extras.append(ex)
            }
            one["extras"] = extras
            pages.append(one)
        }

        var places: [[String: Any]] = []
        for place in Action.places {
            var one: [String: Any] = [:]
            one["title"] = place.title
            one["symbol"] = place.symbol
            one["holds"] = place.holds
            places.append(one)
        }

        var starts: [[String: Any]] = []
        for (value, title, note) in Main.starts {
            starts.append(["value": value, "title": title, "note": note])
        }

        var gates: [[String: Any]] = []
        for gate in Web.gates {
            gates.append(["symbol": gate.symbol, "title": gate.title])
        }

        var config: [String: Any] = [:]
        for key in ["name", "start", "tidy", "days", "rail", "preview"] {
            config[key] = Config.value(key) ?? ""
        }

        var out: [String: Any] = [:]
        out["version"] = Nimo.version
        out["setup"] = Main.setup
        out["welcomed"] = Config.value("welcomed") == Main.setup
        out["user"] = NSFullUserName()
        out["login"] = ["possible": Login.possible, "on": Login.on]
        out["config"] = config
        out["pages"] = pages
        out["places"] = places
        out["starts"] = starts
        out["gates"] = gates
        return out
    }

    private func settings() -> [String: Any] {
        var out: [String: Any] = [:]
        out["login"] = ["possible": Login.possible, "on": Login.on]
        out["fullDisk"] = Access.everything
        out["folders"] = Access.may(Access.desktop) && Access.may(Access.downloads)
        out["version"] = Nimo.version
        return out
    }

    // MARK: running nimo

    /// Runs `min` off the main thread and hands back what it said.
    private func run(_ arguments: [String], _ id: Int, with extra: [String: Any] = [:],
                     then: ((Outcome) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                var payload = extra
                payload["ok"] = result.ok
                payload["text"] = result.text
                then?(result)
                self.reply(id, payload)
            }
        }
    }

    /// A reading: nothing changes, so nothing is asked.
    private func read(_ arguments: [String], _ id: Int) {
        run(arguments, id)
    }

    /// A change, one at a time, told to macOS's notifications when it lands.
    private func change(_ arguments: [String], _ id: Int, title: String) {
        guard !changing else {
            reply(id, ["cancelled": true, "busy": true])
            return
        }
        changing = true
        run(arguments, id, with: ["changed": true]) { result in
            self.changing = false
            // Only the line nimo already wrote — no second opinion.
            if let done = Web.firstGood(result.text) {
                Word.say(title, done)
            }
        }
    }

    private static func firstGood(_ text: String) -> String? {
        for piece in Report.parse(text) {
            if case .good(let done) = piece { return done }
        }
        return nil
    }

    /// A real macOS question, as a sheet on the window. The page waits.
    private func confirm(_ title: String, _ question: String, button: String = "Do it",
                         cancel: String = "Cancel", then: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = question
        alert.alertStyle = .informational
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: cancel)
        if window.isVisible {
            alert.beginSheetModal(for: window) { answer in
                then(answer == .alertFirstButtonReturn)
            }
        } else {
            then(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    /// Opening a page. Reading, never changing: a page that asks a question
    /// is read with --dry-run, and one that changes things the moment it
    /// runs (Next, on Wallpaper) is not run at all.
    private func look(_ body: [String: Any], _ id: Int) {
        guard let item = page(body) else {
            reply(id, ["ok": false, "text": ""])
            return
        }
        var arguments: [String]
        if item.asks != nil {
            arguments = item.arguments + ["--dry-run"]
        } else if item.looksOnly {
            arguments = item.arguments
            // Home in two halves: the instant readings first, then the one
            // that walks every cache on the disk.
            if flag(body, "fast"), item.arguments.first == "doctor" { arguments.append("--fast") }
        } else {
            reply(id, ["ready": true])
            return
        }
        var extra: [String: Any] = [:]
        if number(body, "page") == 0 {
            extra["sighted"] = Access.may(Access.desktop) && Access.may(Access.downloads)
        }
        run(arguments, id, with: extra)
    }

    /// The big button on a page.
    private func go(_ body: [String: Any], _ id: Int) {
        guard let item = page(body) else {
            reply(id, ["cancelled": true])
            return
        }
        // "Only look" is on: the same command, with --dry-run, and no
        // question, because there is nothing to agree to.
        if flag(body, "preview") {
            run(item.arguments + ["--dry-run"], id, with: ["preview": true])
            return
        }
        guard let question = item.asks else {
            if item.looksOnly {
                read(item.arguments, id)           // Look again, Measure, Check
            } else {
                change(item.arguments, id, title: item.title)   // Next
            }
            return
        }
        confirm(item.verb, question) { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            // Only after somebody has said yes does --yes go near nimo.
            self.change(item.arguments + ["--yes"], id, title: item.title)
        }
    }

    /// The smaller buttons beside the big one.
    private func extra(_ body: [String: Any], _ id: Int) {
        guard let item = page(body), let which = number(body, "index"),
              item.extras.indices.contains(which) else {
            reply(id, ["cancelled": true])
            return
        }
        let one = item.extras[which]
        if flag(body, "preview") {
            run(one.arguments + ["--dry-run"], id, with: ["preview": true])
            return
        }
        guard let question = one.asks else {
            // Only look, Previous, The one I had: nothing to agree to. The
            // two that change a wallpaper are changes all the same.
            if item.looksOnly {
                read(one.arguments, id)
            } else {
                change(one.arguments, id, title: item.title)
            }
            return
        }
        confirm(one.title, question) { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.change(one.arguments + ["--yes"], id, title: item.title)
        }
    }

    /// Desktop and Downloads, behind one question, one after the other.
    /// Not `min tidy`: that one also sets your wallpaper and walks you
    /// through setup, and neither belongs behind a button that clears a desk.
    private func tidy(_ body: [String: Any], _ id: Int) {
        let asked = (body["pages"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        var pages: [Int] = []
        for index in asked where Action.all.indices.contains(index) && !pages.contains(index) {
            let first = Action.all[index].arguments.first ?? ""
            if first == "desktop" || first == "downloads" { pages.append(index) }
        }
        guard !pages.isEmpty else {
            reply(id, ["cancelled": true])
            return
        }

        let preview = flag(body, "preview")
        let names = pages.map { Action.all[$0].title.lowercased() }
        let said = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            : (names.first ?? "")

        func work(_ really: Bool) {
            if really {
                guard !changing else {
                    reply(id, ["cancelled": true, "busy": true])
                    return
                }
                changing = true
            }
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [[String: Any]] = []
                for index in pages {
                    let item = Action.all[index]
                    let result = Nimo.run(item.arguments + [really ? "--yes" : "--dry-run"])
                    var one: [String: Any] = [:]
                    one["page"] = index
                    one["ok"] = result.ok
                    one["text"] = result.text
                    one["changed"] = really
                    one["preview"] = !really
                    results.append(one)
                    if really, let done = Web.firstGood(result.text) {
                        DispatchQueue.main.async { Word.say(item.title, done) }
                    }
                }
                DispatchQueue.main.async {
                    if really { self.changing = false }
                    self.reply(id, ["results": results])
                }
            }
        }

        if preview {
            work(false)
            return
        }
        confirm("Tidy " + said + "?",
                "Everything loose in them moves into one folder each, sorted by what it is. "
                + "Nothing is deleted, nothing is renamed, and nothing outside those folders is touched.\n\n"
                + "\"Put it all back\" reverses every one of these moves.") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            work(true)
        }
    }

    /// Measuring a folder inside your home. The names come from what nimo
    /// printed; each is checked to be one plain name, and nimo itself will
    /// not measure anything outside your home.
    private func walk(_ body: [String: Any], _ id: Int) {
        let path = (body["path"] as? [Any] ?? []).compactMap { $0 as? String }
        guard !path.isEmpty, path.count <= 24, path.allSatisfy({ Web.plain($0) }) else {
            reply(id, ["ok": false, "text": "! That is not a folder Kliner can measure."])
            return
        }
        read(["top", path.joined(separator: "/")], id)
    }

    /// A thing inside your home, shown in the Finder. Shown, never opened:
    /// a cleaner that can launch things is not one anybody should trust.
    private func show(_ body: [String: Any]) {
        let path = (body["path"] as? [Any] ?? []).compactMap { $0 as? String }
        guard !path.isEmpty, path.count <= 24, path.allSatisfy({ Web.plain($0) }) else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var url = home
        for part in path { url.appendPathComponent(part) }
        // Resolved, then checked: a link in your home that points out of it
        // is not followed out of it.
        let real = url.resolvingSymlinksInPath()
        let base = home.resolvingSymlinksInPath().path
        guard real.path.hasPrefix(base + "/"),
              FileManager.default.fileExists(atPath: real.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([real])
    }

    /// The folder a page is about, in the Finder.
    private func reveal(_ body: [String: Any]) {
        guard let item = page(body), let name = item.reveal else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        _ = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    // MARK: what is in a folder

    /// The folder a page is about, inside your home — Desktop or Downloads —
    /// or nothing at all.
    private func folder(of body: [String: Any]) -> URL? {
        guard let item = page(body), let name = item.reveal, Web.plain(name) else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name, isDirectory: true)
    }

    /// Everything one level inside that folder, by name, size and date, so
    /// the page can open one kind of thing the way nimo counted it. Names
    /// that start with a dot are not sent: nimo never touches those either.
    /// Nothing here opens, moves or reads what is inside a file.
    private func list(_ body: [String: Any], _ id: Int) {
        guard let folder = folder(of: body) else {
            reply(id, ["items": [Any]()])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let manager = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            let found = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                           options: [])) ?? []
            var items: [[String: Any]] = []
            for url in found {
                let name = url.lastPathComponent
                if name.hasPrefix(".") { continue }
                // nimo asks [ -e ] and [ -d ], and both follow a link: a link
                // to a folder is a folder, and a link to nothing is nothing.
                var directory: ObjCBool = false
                guard manager.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
                var one: [String: Any] = ["name": name, "dir": directory.boolValue]
                let values = try? url.resourceValues(forKeys: Set(keys))
                if !directory.boolValue, let bytes = values?.fileSize { one["size"] = bytes }
                if let date = values?.contentModificationDate {
                    one["modified"] = Int(date.timeIntervalSince1970 * 1000)
                }
                items.append(one)
                if items.count >= 20_000 { break }
            }
            DispatchQueue.main.async { self?.reply(id, ["items": items]) }
        }
    }

    /// `min duplicates` in that folder. nimo sets files side by side by size
    /// first and reads only the ones that match, to see which really are the
    /// same file. It deletes none of them, and neither does anything here.
    private func copies(_ body: [String: Any], _ id: Int) {
        guard let item = page(body), let name = item.reveal, Web.plain(name) else {
            reply(id, ["ok": false, "text": ""])
            return
        }
        read(["duplicates", name], id)
    }

    /// A picture in that folder the page may see drawn: one plain name, a
    /// real file once links are followed, still inside your home, and not so
    /// big that drawing it would stall the Mac. The file is only ever read.
    private static func drawable(_ name: String, in folder: URL, home base: String) -> URL? {
        guard Web.plain(name) else { return nil }
        let real = folder.appendingPathComponent(name).resolvingSymlinksInPath()
        guard real.path.hasPrefix(base + "/"),
              let values = try? real.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let bytes = values.fileSize, bytes > 0, bytes <= 64 << 20 else { return nil }
        return real
    }

    /// Small pictures of the screenshots and images in that folder, drawn by
    /// the Mac's own image reader, a dozen or so at a time.
    private func thumbs(_ body: [String: Any], _ id: Int) {
        let names = (body["names"] as? [Any] ?? []).compactMap { $0 as? String }
        guard let folder = folder(of: body), !names.isEmpty, names.count <= 24 else {
            reply(id, ["thumbs": [String: String]()])
            return
        }
        let base = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var out: [String: String] = [:]
            for name in names {
                guard let url = Web.drawable(name, in: folder, home: base),
                      let jpeg = Web.thumbnail(of: url, side: 360, quality: 0.72) else { continue }
                out[name] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
            }
            DispatchQueue.main.async { self?.reply(id, ["thumbs": out]) }
        }
    }

    /// One of them, big enough to look at in Kliner's own viewer. It is
    /// drawn here and shown there; nothing is opened in another app.
    private func picture(_ body: [String: Any], _ id: Int) {
        guard let name = words(body, "name"), let folder = folder(of: body) else {
            reply(id, [:])
            return
        }
        let base = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var payload: [String: Any] = [:]
            if let url = Web.drawable(name, in: folder, home: base),
               let jpeg = Web.thumbnail(of: url, side: 1800, quality: 0.84) {
                payload["picture"] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
            }
            DispatchQueue.main.async { self?.reply(id, payload) }
        }
    }

    /// One picture, at most `side` pixels along its longer edge, as JPEG.
    /// What is see-through — the shadow round a window screenshot — is laid
    /// on light grey first, because JPEG has nowhere to keep it.
    private static func thumbnail(of url: URL, side: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            break
        default:
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(red: 0.91, green: 0.93, blue: 0.94, alpha: 1)
            context.fill(whole)
            context.draw(image, in: whole)
            guard let flat = context.makeImage() else { return nil }
            image = flat
        }
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString,
                                                            1, nil) else { return nil }
        CGImageDestinationAddImage(target, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { return nil }
        return data as Data
    }

    /// Stopping one thing from starting at sign-in, by the name nimo listed.
    private func stop(_ body: [String: Any], _ id: Int) {
        guard let name = words(body, "name"), !name.isEmpty, name.count <= 200,
              !name.hasPrefix("-"), !name.contains("\u{0}"),
              name.rangeOfCharacter(from: .newlines) == nil else {
            reply(id, ["cancelled": true])
            return
        }
        confirm("Stop \(name) from starting?",
                "It is not uninstalled. It stops launching itself when you sign in, "
                + "and Put it all back reverses that.",
                button: "Stop it") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.change(["startup", "--only", name, "--yes"], id, title: "Startup")
        }
    }

    // MARK: settings

    /// The few things the page may write down, each checked against the
    /// only values it could sensibly be. Anything else is ignored.
    private func remember(_ body: [String: Any]) {
        guard let key = words(body, "key"), let value = words(body, "value") else { return }
        switch key {
        case "rail" where ["list", "icons"].contains(value):
            Config.set("rail", value)
        case "preview" where ["on", "off"].contains(value):
            Config.set("preview", value)
        case "days" where ["7", "30", "90"].contains(value):
            Config.set("days", value)
        default:
            break
        }
    }

    private func login(_ body: [String: Any], _ id: Int) {
        if let trouble = Login.set(flag(body, "on")) {
            let alert = NSAlert()
            alert.messageText = "Kliner could not change that"
            alert.informativeText = trouble
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
        // What macOS says it is now, not what was hoped for.
        reply(id, ["on": Login.on])
    }

    /// macOS will not let an app switch this on, or point at itself in the
    /// list. What it can do is say which switch, and open the page it is on.
    private func fullDisk(_ id: Int) {
        if Access.everything {
            Access.settings("Privacy_AllFiles")
            reply(id, [:])
            return
        }
        confirm("Turn on Full Disk Access for Kliner",
                "Settings will open on the right page. Switch Kliner on in the list, then come "
                + "back — it will stop asking about folders one at a time.\n\n"
                + "Nothing else changes: Kliner still only reads inside your home folder.",
                button: "Open Settings", cancel: "Not now") { yes in
            if yes { Access.settings("Privacy_AllFiles") }
            self.reply(id, [:])
        }
    }

    /// Reading a folder is what raises macOS's question, so asking and
    /// checking are the same act.
    private func askFolders(_ id: Int) {
        for gate in Web.gates {
            if let folder = gate.folder { Access.may(folder) }
        }
        reply(id, ["folders": Access.may(Access.desktop) && Access.may(Access.downloads)])
    }

    /// One of the introduction's questions to macOS, and what it answered.
    private func gate(_ body: [String: Any], _ id: Int) {
        let all = Web.gates
        guard let index = number(body, "index"), all.indices.contains(index) else {
            reply(id, ["yes": false])
            return
        }
        guard let folder = all[index].folder else {
            Word.ask { yes in self.reply(id, ["yes": yes]) }
            return
        }
        // A turn of the runloop first, so the page has drawn "asking macOS
        // now" before macOS puts its own question on top of it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.reply(id, ["yes": Access.may(folder)])
        }
    }

    /// What the introduction was told, written where both halves of Kliner
    /// read it. ~/.nimo/config is the CLI's own file: read, never sourced.
    private func finish(_ body: [String: Any], _ id: Int) {
        let name = Web.clean(words(body, "name") ?? "", limit: 60)
        Config.set("name", name)

        let start = words(body, "start") ?? ""
        if Main.starts.contains(where: { $0.0 == start }) {
            Config.set("start", start)
        }

        // A folder to sort into is a name, not a route; the CLI refuses one
        // with a separator in it, and so does this.
        let into = Web.clean(words(body, "tidy") ?? "", limit: 60)
        if !into.isEmpty, !into.contains("/"), !into.contains(".."), into != ".", !into.hasPrefix("-") {
            Config.set("tidy", into)
        }

        if Login.possible {
            let wanted = flag(body, "login")
            if wanted != Login.on { _ = Login.set(wanted) }
        }
        Config.set("welcomed", Main.setup)
        reply(id, ["page": Main.page(for: Config.value("start") ?? "desktop")])
    }

    /// Home's readings, handed to the menu behind ⌘K so pressing it anywhere
    /// answers "how bad is it" without opening this window.
    private func figures(_ body: [String: Any]) {
        let headline = Web.clean(words(body, "headline") ?? "", limit: 60)
        Quick.shared.headline = headline.isEmpty ? nil : headline
        var said: [Int: String] = [:]
        if let given = body["figures"] as? [String: Any] {
            for (key, value) in given {
                guard let index = Int(key), Action.all.indices.contains(index),
                      let text = value as? String else { continue }
                said[index] = Web.clean(text, limit: 40)
            }
        }
        Quick.shared.figures = said
    }

    /// Where the page's title strip is, and which parts of it are buttons.
    private func chrome(_ body: [String: Any]) {
        if let height = body["height"] as? NSNumber {
            view.bar = CGFloat(min(max(height.doubleValue, 0), 120))
        }
        var holes: [NSRect] = []
        for one in body["holes"] as? [Any] ?? [] {
            guard let four = one as? [Any], four.count == 4 else { continue }
            let n = four.compactMap { value -> CGFloat? in
                guard let number = value as? NSNumber else { return nil }
                return CGFloat(number.doubleValue)
            }
            guard n.count == 4 else { continue }
            holes.append(NSRect(x: n[0], y: n[1], width: n[2], height: n[3]))
        }
        view.holes = holes
    }

    private func terminal() {
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
}

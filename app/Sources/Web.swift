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

    // MARK: a file dropped on the window

    /// A file dragged onto the window is a file to send. The page is told
    /// while one is held over it (true) and when it goes (false), and given
    /// the files let go of. Only files from the Finder count: anything else
    /// dragged here is the web view's own business, handed on untouched.
    var dragging: ((Bool) -> Void)?
    var dropped: (([URL]) -> Void)?
    /// Whether the drag over the window now is one of ours, and whether the
    /// one that just ended was, so its end is not handed on either.
    private var holding = false
    private var took = false

    private func files(_ info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        holding = dropped != nil && !files(sender).isEmpty
        guard holding else { return super.draggingEntered(sender) }
        dragging?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard holding else { return super.draggingUpdated(sender) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard holding else {
            super.draggingExited(sender)
            return
        }
        holding = false
        dragging?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard holding else { return super.prepareForDragOperation(sender) }
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard holding, let dropped = dropped else { return super.performDragOperation(sender) }
        holding = false
        took = true
        dragging?(false)
        dropped(files(sender))
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if took {
            took = false
            return
        }
        super.concludeDragOperation(sender)
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
    /// The processor's counters at the last look, so the next look can say
    /// how busy it was in between, and the apps' pictures, drawn once each.
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var icons: [String: String] = [:]

    /// How many wallpapers the page is shown, and so the highest number a
    /// click can ask for. One number, used in the three places that count.
    static let wallLimit = 80
    /// The wallpapers nimo last listed, by the number the page knows them
    /// by. Kept on the main thread, so the pictures can come a dozen at a
    /// time without nimo listing them all again for every dozen.
    private static var wallPaths: [String] = []

    /// The window's ground, the page's own: so there is no white flash
    /// while it loads, and no light edge on a dark window.
    /// What the window is behind the page, so the frame it is drawn in is
    /// never a different colour from the page for a moment. The same two
    /// grounds the page's own tokens use.
    private static let ground = NSColor(name: nil) { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255, alpha: 1)
            : NSColor(srgbRed: 0xfa / 255, green: 0xf9 / 255, blue: 0xf5 / 255, alpha: 1)
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
        // Glass. The window is clear and an NSVisualEffectView fills it, so
        // whatever is behind the window shows through wherever the page
        // paints nothing — which is the rail, and only the rail: the page
        // paints its content side over this. The web view is told not to
        // draw its own background, or it would cover the effect with one
        // flat colour. `drawsBackground` is not in WKWebView's public
        // interface and is set by name; it has been there since 10.12, and
        // if a future macOS drops it the window simply stays opaque.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = NSSize(width: 820, height: 560)
        window.delegate = self
        let behind = NSVisualEffectView(frame: view.bounds)
        behind.material = .sidebar
        behind.blendingMode = .behindWindow
        behind.state = .followsWindowActiveState
        behind.autoresizingMask = [.width, .height]
        let shell = NSView(frame: view.bounds)
        shell.autoresizingMask = [.width, .height]
        view.frame = shell.bounds
        view.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        shell.addSubview(behind)
        shell.addSubview(view)
        window.contentView = shell

        // Where it was last time, or the middle of the screen the first time.
        if !window.setFrameUsingName("kliner.window") {
            window.center()
        }
        _ = window.setFrameAutosaveName("kliner.window")

        view.navigationDelegate = self
        // ⌘K while you are looking at the window is the window's own search.
        Quick.shared.onFindInWindow = { [weak self] in
            guard let self = self, self.loaded, NSApp.isActive else { return false }
            // While Kliner is asking something, a sheet on the window or an
            // alert of its own, ⌘K waits: the question is the thing in front.
            if NSApp.modalWindow != nil || self.window.attachedSheet != nil { return true }
            guard self.window.isKeyWindow else { return false }
            self.command("find", 0)
            return true
        }
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        // Hidden until the page has drawn itself, so what appears is the
        // window and not an empty frame on its way to being one.
        view.isHidden = true
        view.configuration.userContentController.add(Relay(self), name: "kliner")

        let page = folder.appendingPathComponent("index.html")
        _ = view.loadFileURL(page, allowingReadAccessTo: resources)

        // Sending to an @username: every step of it is told to the page, and
        // a file on its way here brings the window forward to ask.
        Nearby.shared.tell = { [weak self] event in self?.command("send", event) }
        // A file dropped anywhere on the window is a file to send, held the
        // same way as one picked with the Mac's own chooser: the page gets
        // its name, size and picture, and a token that stands for it.
        view.dragging = { [weak self] over in self?.command("send", ["kind": "drag", "over": over]) }
        view.dropped = { [weak self] urls in
            guard let self = self, let first = urls.first else { return }
            var held = Nearby.shared.hold(first)
            held["many"] = urls.count
            self.command("send", ["kind": "dropped", "file": held])
        }
        Nearby.shared.wake = { [weak self] in
            guard let self = self else { return }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Nearby.shared.start()

        // Sending through kliner.app, to a name that is not nearby: told to
        // the page the same way, and a file waiting there brings the window
        // forward to ask.
        Cloud.shared.tell = { [weak self] event in self?.command("send", event) }
        Cloud.shared.wake = { [weak self] in
            guard let self = self else { return }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Cloud.shared.start()
        // kliner.app is asked every twenty seconds while Kliner is in front,
        // every two minutes while it is behind, and at once when it comes forward
        Cloud.shared.quiet = !NSApp.isActive
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Cloud.shared.quiet = false
            Cloud.shared.lookNow()
        }
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            Cloud.shared.quiet = true
        }
        // A name claimed on this Mac while kliner.app could not be reached is
        // claimed there too, the first time it can be. Taken there by then:
        // the page says so and asks for another.
        if Cloud.shared.user.isEmpty, !Nearby.shared.user.isEmpty {
            let mine = Nearby.shared.user
            Cloud.shared.claim(mine) { [weak self] answer in
                if answer["taken"] as? Bool == true { self?.command("send", ["kind": "cloudClash", "user": mine]) }
            }
        }
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
    /// View › Search: the window's own search, the same one ⌘K opens in it.
    @objc func focusSearch() {
        if loaded { command("find", 0) } else { Quick.shared.show() }
    }
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

    /// macOS jettisons a page's process when the app has sat idle for long
    /// enough. Drawing it again is not enough on its own: it would come back
    /// on Home, which reads as the window having forgotten where you were.
    /// The page tells this file its number on every draw, so it comes back
    /// where you left it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        if showing > 0 { owed = showing }
        _ = webView.reload()
    }

    /// The page the window is on, as the page last reported it.
    private var showing = 0

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
        case "walls":       read(["wallpaper", "--list", "--limit", String(Web.wallLimit)], id)
        case "walk":        walk(body, id)
        case "show":        show(body)
        case "reveal":      reveal(body)
        case "list":        list(body, id)
        case "thumbs":      thumbs(body, id)
        case "picture":     picture(body, id)
        case "copies":      copies(body, id)
        case "activity":    activity(id)
        case "monitor":     openActivityMonitor()
        case "unpin":       unpin(body, id)
        case "closeApps":   closeApps(id)
        case "wallFolder":  wallFolder(id)
        case "wallPictures": wallPictures(body, id)
        case "wallBig":     wallBig(body, id)
        case "dockApps":    dockApps(id)
        case "dockMore":    dockMore(id)
        case "setWall":     setWall(body, id)
        case "zen":         zen(body, id)
        case "rename":      rename(body, id)
        case "userCheck":   Nearby.shared.check(words(body, "name") ?? "") { [weak self] answer in self?.reply(id, answer) }
        case "userClaim":   Nearby.shared.claim(words(body, "name") ?? "") { [weak self] answer in self?.reply(id, answer) }
        case "nearby":
            Nearby.shared.watch(flag(body, "on"))
            reply(id, ["ok": true])
        case "sendPick":    Nearby.shared.pick { [weak self] answer in self?.reply(id, answer) }
        case "sendItem":    sendItem(body, id)
        // A name a Mac in sight answers to goes straight across; any other
        // goes through kliner.app, once this Mac has a name there. Stopping
        // and answering go to whichever of the two the file belongs to.
        case "send":
            let token = words(body, "token") ?? ""
            let to = words(body, "to") ?? ""
            if Nearby.shared.sees(to) || Cloud.shared.user.isEmpty {
                reply(id, Nearby.shared.send(token: token, to: to))
            } else if let url = Nearby.shared.held(token) {
                reply(id, Cloud.shared.send(url, to: to))
            } else {
                reply(id, ["ok": false, "text": "Pick the file again."])
            }
        case "sendCancel":
            let job = words(body, "job") ?? ""
            if Cloud.shared.owns(job) { Cloud.shared.cancel(job) } else { Nearby.shared.cancel(job) }
        case "receive":
            let job = words(body, "job") ?? ""
            if Cloud.shared.owns(job) {
                Cloud.shared.answer(job, yes: flag(body, "yes"))
            } else {
                Nearby.shared.answer(job, yes: flag(body, "yes"))
            }
        case "cloudCheck":   Cloud.shared.check(words(body, "name") ?? "") { [weak self] answer in self?.reply(id, answer) }
        case "cloudClaim":
            Cloud.shared.claim(words(body, "name") ?? "", code: words(body, "code") ?? "") { [weak self] answer in
                // Nearby reads the name back from the config: both announce the same one
                if answer["ok"] as? Bool == true { Nearby.shared.start() }
                self?.reply(id, answer)
            }
        case "cloudRename":
            Cloud.shared.rename(words(body, "name") ?? "", code: words(body, "code") ?? "") { [weak self] answer in
                if answer["ok"] as? Bool == true { Nearby.shared.start() }
                self?.reply(id, answer)
            }
        case "profileGet":   Cloud.shared.profile { [weak self] answer in self?.reply(id, answer) }
        case "profilePut":   Cloud.shared.publish(body["profile"] as? [String: Any] ?? [:]) { [weak self] answer in self?.reply(id, answer) }
        case "machine":      machine(id)
        // a public profile, in the browser: only kliner.app's own pages
        case "openProfile":
            if let raw = words(body, "url"), let url = URL(string: raw), url.scheme == "https",
               let host = url.host, host == "kliner.app" || host.hasSuffix(".kliner.app") || host.hasSuffix(".workers.dev") {
                _ = NSWorkspace.shared.open(url)
            }
        case "accountDelete":
            Cloud.shared.deleteAccount { [weak self] answer in
                if answer["ok"] as? Bool == true { Nearby.shared.start() }
                self?.reply(id, answer)
            }
        case "receiving":
            Nearby.shared.setReceiving(flag(body, "on"))
            reply(id, ["on": Nearby.shared.receiving])
        case "showReceived": Nearby.reveal(words(body, "path") ?? "")
        case "dockFast":    dockFast(body, id)
        case "dockKeep":    dockKeep(body, id)
        case "stop":        stop(body, id)
        case "setConfig":   remember(body)
        case "pickPicture": pickPicture(id)
        case "accountPicture": accountPicture(id)
        case "settings":    reply(id, settings())
        case "setLogin":    login(body, id)
        case "fullDisk":    fullDisk(id)
        case "askFolders":  askFolders(id)
        case "automation":  Access.settings("Privacy_Automation")
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

    /// The last thing Home read, kept beside the config so the window opens
    /// with figures on it instead of a spinner. It is only ever a copy of
    /// what nimo printed, and it is replaced by the next real reading.
    private static var lastLook: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nimo", isDirectory: true)
            .appendingPathComponent("last-look")
    }

    private static func remember(look text: String) {
        guard text.count < 200_000 else { return }
        let folder = lastLook.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.data(using: .utf8)?.write(to: lastLook, options: .atomic)
    }

    private static func lastLookBack() -> [String: Any]? {
        guard let text = try? String(contentsOf: lastLook, encoding: .utf8), !text.isEmpty,
              let when = (try? lastLook.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        // A week old is not a reading any more, it is a guess.
        guard Date().timeIntervalSince(when) < 7 * 24 * 3600 else { return nil }
        return ["text": text, "at": Int(when.timeIntervalSince1970 * 1000)]
    }

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
        for key in ["name", "start", "tidy", "days", "rail", "sidebar", "frame", "preview", "tour", "profile", "sent",
                    "userWas", "userWasUntil"] {
            config[key] = Config.value(key) ?? ""
        }
        // the @username, as it was claimed, and whether Macs nearby may send here
        config["user"] = Nearby.shared.user
        config["receive"] = Nearby.shared.receiving ? "on" : "off"
        // the name as kliner.app knows it ("" while it is only claimed on this Mac)
        config["cloudUser"] = Cloud.shared.user

        var out: [String: Any] = [:]
        out["version"] = Nimo.version
        out["setup"] = Main.setup
        out["welcomed"] = Config.value("welcomed") == Main.setup
        out["user"] = NSFullUserName()
        out["account"] = NSUserName()
        out["email"] = Config.value("email") ?? ""
        if let face = Web.portrait() { out["portrait"] = face }
        out["customPicture"] = (Config.value("picture") ?? "").hasPrefix("/")
        out["desktopHidden"] = Web.desktopHidden()
        out["login"] = ["possible": Login.possible, "on": Login.on]
        out["config"] = config
        out["pages"] = pages
        out["places"] = places
        out["starts"] = starts
        out["gates"] = gates
        // Only once the starter is done. Reading the folders is what makes
        // macOS ask about them, and before then the starter's own step is
        // the moment it should, not the second the window opens.
        if Config.value("welcomed") == Main.setup { out["seeing"] = Web.seeing() }
        if let last = Web.lastLookBack() { out["lastLook"] = last }
        // a file can be dropped on the window to send it
        out["drop"] = true
        // The page only goes see-through when the window behind it is.
        out["glass"] = true
        return out
    }

    /// Which of the folders Kliner sorts macOS is letting it look at. The
    /// read is the question: the first one raises macOS's own prompt, and
    /// after that it just answers. A page that finds nothing in a folder
    /// says which of the two it is instead of guessing.
    private static func seeing() -> [String: Bool] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var out: [String: Bool] = [:]
        out["desktop"] = Access.may(home.appendingPathComponent("Desktop"))
        out["downloads"] = Access.may(home.appendingPathComponent("Downloads"))
        out["documents"] = Access.may(home.appendingPathComponent("Documents"))
        return out
    }

    /// Whether the icons on the desktop are away. Desk reads the screen when
    /// the screen can say, and the settings when it cannot.
    static func desktopHidden() -> Bool { Desk.hidden() }

    /// Which press of \ is the newest, so a check still waiting from an
    /// older one does nothing.
    private static var zenTurn = 0



    private func settings() -> [String: Any] {
        var out: [String: Any] = [:]
        out["login"] = ["possible": Login.possible, "on": Login.on]
        out["fullDisk"] = Access.everything
        // every folder the pages read, Documents too
        out["folders"] = !Web.seeing().values.contains(false)
        out["desktopHidden"] = Web.desktopHidden()
        out["version"] = Nimo.version
        return out
    }

    // MARK: running nimo

    /// Runs `min` off the main thread and hands back what it said.
    private func run(_ arguments: [String], _ id: Int, with extra: [String: Any] = [:],
                     changes: Bool = false, then: ((Outcome) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Nimo.run(arguments)
            DispatchQueue.main.async {
                var payload = extra
                payload["ok"] = result.ok
                payload["text"] = result.text
                // A change is only a change once it has happened: a run that
                // failed offers no Undo and throws no reading away.
                if changes { payload["changed"] = result.ok }
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
        run(arguments, id, changes: true) { result in
            self.changing = false
            // Only the line nimo already wrote — no second opinion.
            if let done = Web.firstGood(result.text) {
                Word.say(title, done.replacingOccurrences(of: " — ", with: ": "))
            }
        }
    }

    /// A question as a Mac asks it: the first line bold, the rest under it.
    private static func head(of question: String) -> String {
        question.components(separatedBy: "\n\n").first ?? question
    }

    private static func rest(of question: String) -> String {
        question.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
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
    private func keepIfHome(_ body: [String: Any], _ text: String) {
        guard number(body, "page") == 0, !flag(body, "fast") else { return }
        Web.remember(look: text)
    }

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
        run(arguments, id, with: extra) { [weak self] result in
            if result.ok { self?.keepIfHome(body, result.text) }
        }
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
        confirm(Web.head(of: question), Web.rest(of: question), button: item.verb) { yes in
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
        confirm(Web.head(of: question), Web.rest(of: question), button: one.title) { yes in
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
            // the three folders Kliner sorts, and the caches it clears
            if ["desktop", "downloads", "documents", "clean"].contains(first) { pages.append(index) }
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
                    one["changed"] = really && result.ok
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
        let clears = pages.contains { (Action.all[$0].arguments.first ?? "") == "clean" }
        confirm("Clean " + said + "?",
                (clears
                    ? "Files move into a Tidy folder in each, sorted by type, and the caches your apps can rebuild are deleted. Your own files are never deleted.\n\n"
                    : "Files move into a Tidy folder in each, sorted by type. Nothing is deleted or renamed.\n\n")
                + "You can undo every move at any time.", button: "Clean") { yes in
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
            let found: [URL]
            do {
                found = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
            } catch {
                // A folder that is there but cannot be read is not an empty
                // one: macOS has not let Kliner look. The page says which.
                let there = manager.fileExists(atPath: folder.path)
                DispatchQueue.main.async { self?.reply(id, ["items": [Any](), "shut": there]) }
                return
            }
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
        // The whole path: nimo checks a relative one against your home and
        // refuses it, and the page would have said "no duplicates".
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name).path
        read(["duplicates", folder], id)
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
        // `icons`: what is not a picture comes back as the icon Finder draws
        // for it, so the starter can show your desktop the way Finder does
        let icons = flag(body, "icons")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var out: [String: String] = [:]
            for name in names {
                if let url = Web.drawable(name, in: folder, home: base),
                   let jpeg = Web.thumbnail(of: url, side: 360, quality: 0.72) {
                    out[name] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
                } else if icons, let url = Web.present(name, in: folder, home: base),
                          let png = Web.png(NSWorkspace.shared.icon(forFile: url.path), side: 96) {
                    out[name] = png
                }
            }
            DispatchQueue.main.async { self?.reply(id, ["thumbs": out]) }
        }
    }

    /// Anything in that folder by one plain name, still inside your home once
    /// links are followed. Only its icon is ever asked for.
    private static func present(_ name: String, in folder: URL, home base: String) -> URL? {
        guard Web.plain(name) else { return nil }
        let real = folder.appendingPathComponent(name).resolvingSymlinksInPath()
        guard real.path.hasPrefix(base + "/"), FileManager.default.fileExists(atPath: real.path) else { return nil }
        return real
    }

    /// A picture as a PNG the page can draw, `side` pixels square.
    private static func png(_ image: NSImage, side: Int) -> String? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
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

    /// An address, near enough: one @, something on each side of it, a dot
    /// after it, no spaces. Kliner only writes it down; nothing sends it.
    private static func looksLikeEmail(_ text: String) -> Bool {
        let one = text.trimmingCharacters(in: .whitespaces)
        guard one.count >= 6, one.count <= 120, !one.contains(" ") else { return false }
        let halves = one.components(separatedBy: "@")
        guard halves.count == 2, !halves[0].isEmpty else { return false }
        let host = halves[1]
        guard host.count >= 3, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        return true
    }

    /// A picture of your own instead of the account one. macOS does not let
    /// an app change the account picture, so Kliner keeps its own: the one
    /// you choose is drawn small and kept in ~/.nimo, so it stays when the
    /// file it came from moves, and what ~/.nimo/config remembers is a path
    /// Kliner made rather than one a file name chose.
    private func pickPicture(_ id: Int) {
        let panel = NSOpenPanel()
        panel.title = "Choose a picture"
        panel.prompt = "Use Picture"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]
        panel.begin { answer in
            guard answer == .OK, let url = panel.url else {
                self.reply(id, ["cancelled": true])
                return
            }
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".nimo", isDirectory: true)
            let kept = folder.appendingPathComponent("picture.jpg")
            guard let jpeg = Web.thumbnail(of: url, side: 512, quality: 0.86) else {
                self.reply(id, ["bad": true])
                return
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? jpeg.write(to: kept, options: .atomic)) != nil else {
                self.reply(id, ["bad": true])
                return
            }
            Config.set("picture", kept.path)
            Web.portraitKept = nil
            self.reply(id, ["portrait": Web.portrait() ?? ""])
        }
    }

    /// Back to the picture macOS has for your account.
    private func accountPicture(_ id: Int) {
        Config.set("picture", "")
        Web.portraitKept = nil
        reply(id, ["portrait": Web.portrait() ?? ""])
    }

    /// The picture on your account, the one macOS shows at the login window
    /// and in System Settings. Read from the local directory, for this
    /// account only: nothing is looked up on the network, no other account is
    /// touched, and nothing is written. Read once and kept.
    private static func portrait() -> String? {
        if let kept = portraitKept { return kept.isEmpty ? nil : kept }
        var out = ""
        defer { portraitKept = out }
        var data: Data? = nil
        // One you pointed Kliner at yourself wins over the account's own.
        if let mine = Config.value("picture"), mine.hasPrefix("/"),
           FileManager.default.fileExists(atPath: mine) {
            data = try? Data(contentsOf: URL(fileURLWithPath: mine))
        }
        // A stock picture is a path; one you chose yourself is kept in the
        // record itself, as hex. Try the path first, it is the cheap one.
        if data == nil, let said = Web.dscl("Picture") {
            let path = said.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
                data = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        if data == nil, let hex = Web.dscl("JPEGPhoto") {
            data = Web.bytes(fromHex: hex)
        }
        guard let found = data, found.count > 64, found.count < 12 << 20 else { return nil }
        // Drawn small here rather than in the page: a login picture can be
        // several hundred kilobytes and the window wants 128 points of it.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("kliner-face")
        try? found.write(to: scratch)
        if let small = Web.thumbnail(of: scratch, side: 256, quality: 0.82) {
            out = "data:image/jpeg;base64," + small.base64EncodedString()
        }
        try? FileManager.default.removeItem(at: scratch)
        return out.isEmpty ? nil : out
    }

    /// One attribute of this account's own directory record.
    private static func dscl(_ attribute: String) -> String? {
        let tool = URL(fileURLWithPath: "/usr/bin/dscl")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        let job = Process()
        job.executableURL = tool
        job.arguments = [".", "-read", "/Users/" + NSUserName(), attribute]
        let pipe = Pipe()
        job.standardOutput = pipe
        job.standardError = FileHandle.nullDevice
        do { try job.run() } catch { return nil }
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        job.waitUntilExit()
        guard job.terminationStatus == 0, let said = String(data: raw, encoding: .utf8) else { return nil }
        // "Attribute:\n value" — everything after the first colon.
        guard let colon = said.firstIndex(of: ":") else { return nil }
        return String(said[said.index(after: colon)...])
    }

    /// dscl prints a picture as groups of hex. Anything that is not a hex
    /// digit is spacing, and an odd digit left over means it is not a picture.
    private static func bytes(fromHex text: String) -> Data? {
        var out = Data()
        var half: UInt8? = nil
        for letter in text {
            guard let digit = letter.hexDigitValue, digit >= 0, digit <= 15 else { continue }
            if let first = half {
                out.append(first << 4 | UInt8(digit))
                half = nil
            } else {
                half = UInt8(digit)
            }
        }
        guard half == nil, !out.isEmpty else { return nil }
        return out
    }

    fileprivate static var portraitKept: String? = nil

    /// A file nimo listed as a wallpaper, looked over before it is read:
    /// an absolute path, no tricks in it, in one of the places wallpapers
    /// live, a real file, and small enough to draw. It is only ever read.
    private static func wallpaperFile(_ path: String) -> URL? {
        guard path.hasPrefix("/"), path.count <= 4096, !path.contains("\u{0}") else { return nil }
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        var inside = false
        for root in ["/System/Library/Desktop Pictures/", "/Library/Desktop Pictures/",
                     "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture/", home + "/"] {
            if real.path.hasPrefix(root) { inside = true }
        }
        guard inside else { return nil }
        guard let values = try? real.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }
        guard let bytes = values.fileSize, bytes > 0, bytes <= 200 << 20 else { return nil }
        return real
    }

    /// The wallpapers as nimo lists them: file paths, one to a line.
    private static func readWallPaths() -> [String] {
        let result = Nimo.run(["wallpaper", "--list", "--paths", "--limit", String(Web.wallLimit)])
        guard result.ok else { return [] }
        var paths: [String] = []
        for line in result.text.components(separatedBy: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            if path.isEmpty { continue }
            paths.append(path)
            if paths.count >= Web.wallLimit { break }
        }
        return paths
    }

    /// Previews of the wallpapers, in the order the page lists them, a
    /// dozen or so at a time: `from` is the first one's number, `count` how
    /// many. The page names no file: nimo prints the paths it has already
    /// found, and only those are opened, only to be drawn. The first batch
    /// asks nimo for the list; the rest use the list it gave.
    private func wallPictures(_ body: [String: Any], _ id: Int) {
        let from = max(1, number(body, "from") ?? 1)
        let count = max(1, min(Web.wallLimit, number(body, "count") ?? Web.wallLimit))
        let known: [String] = from == 1 ? [] : Web.wallPaths
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let paths = known.isEmpty ? Web.readWallPaths() : known
            // How many at the top of the list are yours: nimo lists your own
            // folder first, and the page draws a line where the Mac's begin.
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var mine = 0
            for path in paths {
                guard path.hasPrefix(home + "/"), !path.hasPrefix(home + "/Library/") else { break }
                mine += 1
            }
            // A dozen at once, on every core there is, and each one kept in
            // Caches the first time it is drawn: opening the page again is
            // reading small files, not decoding forty 4K pictures again.
            // Past the end of the list is no rows, not a range that runs
            // backwards, which Swift stops the whole app for.
            let end = min(from + count, paths.count + 1)
            let rows = from < end ? Array(from..<end) : []
            var found = [String?](repeating: nil, count: rows.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: rows.count) { k in
                guard let url = Web.wallpaperFile(paths[rows[k] - 1]),
                      let jpeg = Web.cachedThumbnail(of: url, side: 440) else { return }
                let uri = "data:image/jpeg;base64," + jpeg.base64EncodedString()
                lock.lock()
                found[k] = uri
                lock.unlock()
            }
            var out: [String: String] = [:]
            for (k, row) in rows.enumerated() {
                if let uri = found[k] { out[String(row)] = uri }
            }
            // Which shelf each one sits on, with the first dozen: the Kliner
            // folder, your own, the Mac's, and the Mac's plain colours.
            var payload: [String: Any] = ["pictures": out, "mine": mine, "total": paths.count]
            if from == 1 {
                payload["kinds"] = paths.map { path -> String in
                    if path.hasPrefix(home + "/") { return path.contains("/Kliner Wallpapers/") ? "kliner" : "yours" }
                    if path.contains("/Solid Colors/") { return "colors" }
                    return "mac"
                }
            }
            DispatchQueue.main.async {
                Web.wallPaths = paths
                self?.reply(id, payload)
            }
        }
    }

    /// One wallpaper big enough to fill the picture of your screen in the
    /// starter: row `at` of nimo's list, or with no `at`, the one on your
    /// screen now, as the Mac itself says. Read only, only to be drawn.
    private func wallBig(_ body: [String: Any], _ id: Int) {
        let at = number(body, "at") ?? 0
        guard at >= 0, at <= Web.wallLimit else {
            reply(id, [:])
            return
        }
        let known = Web.wallPaths
        let screen = NSScreen.main ?? NSScreen.screens.first
        let now: String? = at == 0 ? screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path } : nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var path = now
            if at > 0 {
                let paths = known.count >= at ? known : Web.readWallPaths()
                path = at <= paths.count ? paths[at - 1] : nil
            }
            var payload: [String: Any] = [:]
            if let path = path, let url = Web.wallpaperFile(path),
               let jpeg = Web.thumbnail(of: url, side: 1400, quality: 0.8) {
                payload["picture"] = "data:image/jpeg;base64," + jpeg.base64EncodedString()
            }
            DispatchQueue.main.async { self?.reply(id, payload) }
        }
    }

    /// Your Dock, with each app's own icon. nimo lists every app in it by the
    /// name `--only` answers to and where the app is; only those apps are
    /// looked at, and only to draw their icons. Finder and the Trash sit at
    /// the two ends of every Dock and are drawn from the Mac's own pictures.
    private func dockApps(_ id: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Nimo.run(["dock", "--list", "--paths"])
            var apps: [[String: Any]] = []
            if result.ok {
                for line in result.text.components(separatedBy: "\n") {
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count == 2 else { continue }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, name.count <= 200 else { continue }
                    var one: [String: Any] = ["name": name]
                    if let app = Web.appBundle(parts[1]),
                       let png = Web.png(NSWorkspace.shared.icon(forFile: app.path), side: 128) {
                        one["icon"] = png
                    }
                    apps.append(one)
                    if apps.count >= 60 { break }
                }
            }
            DispatchQueue.main.async {
                var payload: [String: Any] = ["apps": apps, "ok": result.ok]
                if let finder = Web.png(NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"), side: 128) {
                    payload["finder"] = finder
                }
                if let bin = NSImage(named: NSImage.trashEmptyName), let png = Web.png(bin, side: 128) {
                    payload["trash"] = png
                }
                self?.reply(id, payload)
            }
        }
    }

    /// An app nimo named in your Dock: a whole path, nothing hidden in it,
    /// ending in .app, and a folder that is there.
    private static func appBundle(_ path: String) -> URL? {
        guard path.hasPrefix("/"), path.count <= 4096, !path.contains("\u{0}"), path.hasSuffix(".app") else { return nil }
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &folder), folder.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// A wallpaper's small picture, from Caches when it has been drawn
    /// before and the file has not changed since; drawn and kept otherwise.
    /// The name is the path, the size and the date, so a changed file is a
    /// new name and an old picture is never shown for it.
    private static func cachedThumbnail(of url: URL, side: Int) -> Data? {
        let manager = FileManager.default
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(url.path)|\(values?.fileSize ?? 0)|\(Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0))|\(side)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in stamp.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("app.kliner.mac", isDirectory: true)
            .appendingPathComponent("walls", isDirectory: true)
        let kept = caches?.appendingPathComponent(String(format: "%016llx.jpg", hash))
        if let kept = kept, let data = try? Data(contentsOf: kept), !data.isEmpty { return data }
        guard let fresh = thumbnail(of: url, side: side, quality: 0.75) else { return nil }
        if let caches = caches, let kept = kept {
            try? manager.createDirectory(at: caches, withIntermediateDirectories: true)
            try? fresh.write(to: kept, options: .atomic)
        }
        return fresh
    }

    /// One picture, at most `side` pixels along its longer edge, as JPEG.
    /// What is see-through — the shadow round a window screenshot — is laid
    /// on light grey first, because JPEG has nowhere to keep it.
    private static func thumbnail(of url: URL, side: Int, quality: Double, whole: Bool = true) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // `whole` decodes the picture itself. A wallpaper carries its own
        // preview and can be a hundred megabytes, so there it stays off.
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        if whole {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        }
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

    /// The wallpaper the picker was clicked on: the number of a row in the
    /// same list the page was shown. No dialog — it is one picture, it is on
    /// the screen a second later, and "Original" puts back the one you had.
    private func setWall(_ body: [String: Any], _ id: Int) {
        guard let at = number(body, "at"), at >= 1, at <= Web.wallLimit else {
            reply(id, ["cancelled": true])
            return
        }
        change(["wallpaper", "--only", String(at), "--yes"], id, title: "Wallpaper")
    }

    /// Finder stops drawing icons on the desktop, or starts again. The files
    /// do not move: this is one setting, and nimo can set it back.
    private func zen(_ body: [String: Any], _ id: Int) {
        let back = flag(body, "back")
        // From the \ key, or a switch: no question. The files do not move,
        // only the icons go, and \ again puts them back — a dialog in front
        // of a key you press to see your desktop is a key that does not work.
        //
        // And no min either: \ is pressed to see the desktop, so it is
        // written straight, in about a millisecond, and the page is told what
        // happened in the same breath. `toggle` lets this side pick the
        // direction, from what is actually on screen, so a settings file left
        // half-written by an older Kliner cannot send the key the wrong way.
        if flag(body, "quick") {
            Web.zenTurn += 1
            let turn = Web.zenTurn
            let hide = flag(body, "toggle") ? !Desk.hidden() : !back
            Desk.set(hide)
            reply(id, ["ok": true, "changed": true, "hidden": hide, "text": ""])
            // Should the icons still be the wrong way a moment later, this
            // Mac did not take the switch: Finder's way instead, slower but
            // certain. Unless the key was pressed again in the meantime.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard Web.zenTurn == turn, Desk.onScreen() == hide else { return }
                DispatchQueue.global(qos: .userInitiated).async { Desk.finderWay(hide) }
            }
            return
        }
        let question = back ? "Show icons on your desktop again?"
                            : "Stop showing icons on your desktop?"
        let why = back ? "They are the same files that were always there."
                       : "Nothing moves. The files stay in your Desktop folder, and Kliner can show them again."
        confirm(question, why, button: back ? "Show them" : "Hide them") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.change(back ? ["zen", "--restore", "--yes"] : ["zen", "--yes"], id, title: "Desktop")
        }
    }

    /// A new name for one file in a page's folder, typed on the small desktop
    /// in the starter. The typing is the question, as it is in Finder: the
    /// name was written by the person it belongs to, in a field of its own,
    /// and Return is the yes. nimo renames it in the same folder, never over
    /// a name that is taken, and writes the old name down first, so the
    /// page's Undo — `undo` here — and `min undo` both give it back.
    private func rename(_ body: [String: Any], _ id: Int) {
        guard let folder = folder(of: body) else {
            reply(id, ["ok": false, "text": ""])
            return
        }
        if flag(body, "undo") {
            run(["rename", "--undo"], id, changes: true)
            return
        }
        guard let name = body["name"] as? String, Web.plain(name),
              let typed = body["to"] as? String else {
            reply(id, ["ok": false, "text": ""])
            return
        }
        let to = typed.trimmingCharacters(in: .whitespaces)
        guard Web.plain(to), !to.hasPrefix("."), !to.contains(":") else {
            reply(id, ["ok": false, "text": "! a name cannot start with a dot or have / or : in it"])
            return
        }
        let path = folder.appendingPathComponent(name).path
        run(["rename", path, "--to", to, "--yes"], id, with: ["name": to], changes: true)
    }

    /// What this Mac is, for the public profile, as the Mac says it itself:
    /// the model's name, the chip, the memory and macOS, and whether the Dock
    /// hides. Asked of system_profiler once, off the main thread.
    private func machine(_ id: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var out: [String: Any] = [:]
            let version = ProcessInfo.processInfo.operatingSystemVersion
            out["macos"] = version.patchVersion > 0
                ? "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
                : "macOS \(version.majorVersion).\(version.minorVersion)"
            out["memory"] = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPHardwareDataType", "-json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            if (try? task.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let first = (json["SPHardwareDataType"] as? [[String: Any]])?.first {
                    if let name = first["machine_name"] as? String { out["model"] = name }
                    if let chip = first["chip_type"] as? String { out["chip"] = chip }
                    else if let cpu = first["cpu_type"] as? String { out["chip"] = cpu }
                    if let memory = first["physical_memory"] as? String { out["memory"] = memory }
                }
            }
            if let dock = UserDefaults(suiteName: "com.apple.dock") {
                out["dockAutohide"] = dock.bool(forKey: "autohide")
            }
            let answer = out
            DispatchQueue.main.async { self?.reply(id, answer) }
        }
    }

    /// A file the page knows by its folder and name — one on your desktop —
    /// held for sending, the same way a picked one is.
    private func sendItem(_ body: [String: Any], _ id: Int) {
        guard let folder = folder(of: body), let name = words(body, "name"), Web.plain(name) else {
            reply(id, ["ok": false, "text": "That file cannot be sent from here."])
            return
        }
        reply(id, Nearby.shared.hold(folder.appendingPathComponent(name)))
    }

    /// A Dock that slides out of the way until you reach for it — or, with
    /// `back`, the Dock as it was before, from what nimo wrote down.
    private func dockFast(_ body: [String: Any], _ id: Int) {
        if flag(body, "back") {
            run(["dock", "--fast", "--restore", "--yes"], id, changes: true)
            return
        }
        dockFast(id)
    }

    /// A Dock that slides out of the way until you reach for it.
    private func dockFast(_ id: Int) {
        confirm("Let your Dock slide away?",
                "It comes back the moment you move the pointer to the edge of the screen. To keep it on screen again, turn off \"Automatically hide and show the Dock\" in System Settings › Desktop & Dock.",
                button: "Let it slide") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.change(["dock", "--fast", "--yes"], id, title: "Dock")
        }
    }

    /// What the starter changes in the Dock, in one question and one run:
    /// the apps that come out and the ones that go in. Same rules as taking
    /// one out: plain names, the apps themselves untouched, and nimo writes
    /// the whole Dock down first, once, before any of it.
    private func dockKeep(_ body: [String: Any], _ id: Int) {
        func plainNames(_ key: String) -> [String] {
            let asked = (body[key] as? [Any] ?? []).compactMap { $0 as? String }
            return asked.filter { name in
                !name.isEmpty && name.count <= 200 && !name.hasPrefix("-")
                    && !name.contains("\u{0}") && name.rangeOfCharacter(from: .newlines) == nil
            }
        }
        let drop = plainNames("drop"), add = plainNames("add")
        guard !(drop.isEmpty && add.isEmpty), drop.count <= 60, add.count <= 60 else {
            reply(id, ["cancelled": true])
            return
        }
        let apps: (Int) -> String = { $0 == 1 ? "1 app" : "\($0) apps" }
        let title = drop.isEmpty ? "Put \(apps(add.count)) in your Dock?"
            : add.isEmpty ? "Take \(apps(drop.count)) out of your Dock?"
            : "Take \(apps(drop.count)) out of your Dock, and put \(apps(add.count)) in?"
        confirm(title, "The apps themselves stay where they are. Only the Dock changes, and Kliner saves it first.",
                button: "Change the Dock") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            guard !self.changing else {
                self.reply(id, ["cancelled": true, "busy": true])
                return
            }
            self.changing = true
            // One run for all of it, one name to a line: one backup of the
            // Dock before anything moves, so "Put the Dock back" is exact.
            // No name can hold a line break; each was checked above.
            var arguments = ["dock"]
            if !drop.isEmpty { arguments += ["--only", drop.joined(separator: "\n")] }
            if !add.isEmpty { arguments += ["--add", add.joined(separator: "\n")] }
            arguments.append("--yes")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Nimo.run(arguments)
                DispatchQueue.main.async {
                    self.changing = false
                    // nimo names each one it could not find; the rest went
                    let missingOut = result.text.components(separatedBy: "cannot find \"").count - 1
                    let missingIn = result.text.components(separatedBy: "cannot find an app called \"").count - 1
                    let out = result.ok ? max(0, drop.count - missingOut) : 0
                    let inn = result.ok ? max(0, add.count - missingIn) : 0
                    if out + inn > 0 {
                        Word.say("Dock", out > 0 && inn > 0 ? "\(apps(out)) out, \(apps(inn)) in"
                                         : out > 0 ? "\(apps(out)) taken out" : "\(apps(inn)) put in")
                    }
                    self.reply(id, ["ok": result.ok && out == drop.count && inn == add.count, "changed": out + inn > 0,
                                    "closed": out, "added": inn, "asked": drop.count, "text": result.text])
                }
            }
        }
    }

    /// The apps that are installed and not in your Dock, with their icons,
    /// for the starter to offer. nimo lists them; only their icons are read.
    private func dockMore(_ id: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Nimo.run(["dock", "--list", "--paths", "--all"])
            var apps: [[String: Any]] = []
            if result.ok {
                for line in result.text.components(separatedBy: "\n") {
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count == 2 else { continue }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, name.count <= 200 else { continue }
                    var one: [String: Any] = ["name": name]
                    if let app = Web.appBundle(parts[1]),
                       let png = Web.png(NSWorkspace.shared.icon(forFile: app.path), side: 96) {
                        one["icon"] = png
                    }
                    apps.append(one)
                    if apps.count >= 240 { break }
                }
            }
            DispatchQueue.main.async { self?.reply(id, ["apps": apps]) }
        }
    }

    /// One app out of the Dock, by the name nimo listed. nimo exports the
    /// whole Dock first, so "Put the Dock back" is exact. The app itself is
    /// not touched: only the icon goes.
    private func unpin(_ body: [String: Any], _ id: Int) {
        guard let name = words(body, "name"), !name.isEmpty, name.count <= 200,
              !name.hasPrefix("-"), !name.contains("\u{0}"),
              name.rangeOfCharacter(from: .newlines) == nil else {
            reply(id, ["cancelled": true])
            return
        }
        confirm("Take \(name) out of your Dock?",
                "The app stays installed. Kliner saves your Dock first, so you can put it back.",
                button: "Take it out") { yes in
            guard yes else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.change(["dock", "--only", name, "--yes"], id, title: "Dock")
        }
    }

    /// Every app that is open, asked to quit. Asked, not killed: an app with
    /// unsaved work puts up its own question, exactly as ⌘Q does.
    ///
    /// It is a static so the menu behind ⌘K can ask it too, with or without
    /// a window to hang the question on.
    static func closeEverything(on window: NSWindow?, then: @escaping (Int?) -> Void) {
        let mine = Bundle.main.bundleIdentifier
        let others = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.bundleIdentifier != mine
                && app.bundleIdentifier != "com.apple.finder"
        }
        guard !others.isEmpty else {
            then(0)
            return
        }
        let names = others.compactMap { $0.localizedName }.sorted()
        let said = names.prefix(8).joined(separator: ", ") + (names.count > 8 ? " and \(names.count - 8) more" : "")

        let alert = NSAlert()
        alert.messageText = "Ask \(names.count) open apps to quit?"
        alert.informativeText = said + ".\n\nEach one is asked the way ⌘Q asks it, so anything unsaved stops and asks you first. Kliner and the Finder stay."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Ask them to quit")
        alert.addButton(withTitle: "Cancel")

        func answer(_ yes: Bool) {
            guard yes else {
                then(nil)
                return
            }
            var asked = 0
            for app in others where app.terminate() { asked += 1 }
            Word.say("Apps", "Asked \(asked) apps to quit")
            then(asked)
        }

        if let window = window, window.isVisible {
            alert.beginSheetModal(for: window) { got in answer(got == .alertFirstButtonReturn) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            answer(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    private func closeApps(_ id: Int) {
        Web.closeEverything(on: window) { closed in
            guard let closed = closed else {
                self.reply(id, ["cancelled": true])
                return
            }
            self.reply(id, ["closed": closed])
        }
    }

    /// The folder your own wallpapers go in, made if it is not there yet and
    /// opened in the Finder. nimo lists what is in it before Apple's own.
    private func wallFolder(_ id: Int) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Kliner Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent("Put your wallpapers here.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let words = """
            Drop pictures in this folder and Kliner steps through them with
            the ones that came with your Mac.

            JPEG, PNG and HEIC. The name of the file is the name Kliner shows.

            """
            try? words.data(using: .utf8)?.write(to: readme)
        }
        _ = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        reply(id, ["folder": "Pictures/Kliner Wallpapers"])
    }

    // MARK: what the Mac is doing

    /// The processor, the memory, and the apps using the most of either.
    /// Read, never touched: nothing here can stop, slow or quit anything.
    private func activity(_ id: Int) {
        let before = lastTicks
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var start = before
            if start == nil {
                // A first look has nothing to compare with, so it takes two.
                start = Web.cpuTicks()
                Thread.sleep(forTimeInterval: 0.3)
            }
            let now = Web.cpuTicks()
            var cpu = 0.0
            if let a = start, let b = now, b.total > a.total, b.busy >= a.busy {
                cpu = Double(b.busy - a.busy) / Double(b.total - a.total) * 100
            }
            let memory = Web.memory()
            let apps = Web.apps()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let now = now { self.lastTicks = now }
                var list: [[String: Any]] = []
                for app in apps.prefix(60) {
                    var one: [String: Any] = ["name": app.name, "cpu": app.cpu, "memory": app.memory, "count": app.count]
                    if let bundle = app.bundle { one["icon"] = self.icon(bundle) }
                    list.append(one)
                }
                self.reply(id, [
                    "cpu": cpu.isFinite ? min(100, max(0, cpu)) : 0,
                    "cores": ProcessInfo.processInfo.activeProcessorCount,
                    "memory": ["used": memory.used, "total": ProcessInfo.processInfo.physicalMemory],
                    "apps": list,
                ])
            }
        }
    }

    /// Apple's own Activity Monitor, for anything more than this.
    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The machine's one host port, asked for once rather than on every look.
    private static let host = mach_host_self()

    /// How long the processors have spent busy, and in all, since the Mac
    /// started. Two of these, a moment apart, are how busy it is now.
    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(Web.host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Memory in use, counted the way Activity Monitor counts it: what apps
    /// hold, what the system has wired down, and what is compressed.
    private static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(Web.host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(getpagesize())
        let apps = UInt64(info.internal_page_count) > UInt64(info.purgeable_count)
            ? UInt64(info.internal_page_count) - UInt64(info.purgeable_count) : 0
        let used = (apps + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
        return (min(used, total), total)
    }

    /// Every process, from `ps`, gathered into the app it belongs to: a
    /// browser is one line with its helpers in it, not forty.
    private static func apps() -> [(name: String, bundle: String?, cpu: Double, memory: UInt64, count: Int)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        var byName: [String: (name: String, bundle: String?, cpu: Double, memory: UInt64, count: Int)] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let cpu = Double(parts[0]), let kilobytes = UInt64(parts[1]) else { continue }
            let path = String(parts[2])
            var bundle: String?
            var name = (path as NSString).lastPathComponent
            if let range = path.range(of: ".app/") {
                let root = String(path[..<range.lowerBound]) + ".app"
                bundle = root
                name = ((root as NSString).lastPathComponent as NSString).deletingPathExtension
            }
            if name.isEmpty { continue }
            let key = bundle ?? name
            var one = byName[key] ?? (name: name, bundle: bundle, cpu: 0, memory: 0, count: 0)
            one.cpu += cpu.isFinite ? cpu : 0
            one.memory += kilobytes * 1024
            one.count += 1
            byName[key] = one
        }
        return byName.values.sorted { $0.memory > $1.memory }
    }

    /// An app's own picture, small, drawn once and kept.
    private func icon(_ bundle: String) -> String {
        if let done = icons[bundle] { return done }
        var out = ""
        let image = NSWorkspace.shared.icon(forFile: bundle)
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                out = "data:image/png;base64," + png.base64EncodedString()
            }
        }
        icons[bundle] = out
        return out
    }

    /// Stopping one thing from starting at sign-in, by the name nimo listed.
    private func stop(_ body: [String: Any], _ id: Int) {
        guard let name = words(body, "name"), !name.isEmpty, name.count <= 200,
              !name.hasPrefix("-"), !name.contains("\u{0}"),
              name.rangeOfCharacter(from: .newlines) == nil else {
            reply(id, ["cancelled": true])
            return
        }
        confirm("Stop \(name) from opening at login?",
                "Nothing is uninstalled, and you can undo this.",
                button: "Stop") { yes in
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
        // the sidebar with its names, or folded to pictures (⌘B)
        case "sidebar" where ["open", "folded"].contains(value):
            Config.set("sidebar", value)
        // the window's left edge: a rail of pictures (the default), or the
        // pages with their names beside them (⌘B)
        case "frame" where ["rail", "names"].contains(value):
            Config.set("frame", value)
        case "preview" where ["on", "off"].contains(value):
            Config.set("preview", value)
        // what the public profile says, kept here as well: one line of JSON
        case "profile" where value.count <= 4000:
            Config.set("profile", value)
        // the map of the window has been seen, so it is not shown by itself
        // again; Help still has it
        case "tour" where value == "done":
            Config.set("tour", value)
        case "days" where ["7", "30", "90"].contains(value):
            Config.set("days", value)
        case "name":
            Config.set("name", Web.clean(value, limit: 60))
        case "email" where Web.looksLikeEmail(value) || value.isEmpty:
            Config.set("email", Web.clean(value, limit: 120))
        // the folder things are sorted into, after you renamed it: a name,
        // never a route, the same rule nimo and the starter have
        // who files were sent to lately, for the Send page: @usernames only,
        // by the same rules as any other, and eight at most
        case "sent":
            let names = value.split(separator: ",").map(String.init)
            if names.count <= 8, names.allSatisfy({ Nearby.valid($0) == nil }) {
                Config.set("sent", names.joined(separator: ","))
            }
        case "tidy":
            let into = Web.clean(value, limit: 60)
            if !into.isEmpty, !into.contains("/"), !into.contains(".."), into != ".", !into.hasPrefix("-"), !into.hasPrefix(".") {
                Config.set("tidy", into)
            }
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
        confirm("Turn on Full Disk Access?",
                "System Settings opens on the right page. Switch on Kliner there, then come back.\n\n"
                + "Kliner still only reads your home folder.",
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
        let seen = Web.seeing()
        reply(id, ["folders": !seen.values.contains(false), "seeing": seen])
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
        // The email is not optional, and the page is not the only one who
        // checks: without one the starter is not finished, nothing is written,
        // and the page goes back to the step that asks for it.
        let post = Web.clean(words(body, "email") ?? "", limit: 120)
        guard Web.looksLikeEmail(post) else {
            reply(id, ["bad": "email"])
            return
        }
        Config.set("email", post)

        let name = Web.clean(words(body, "name") ?? "", limit: 60)
        Config.set("name", name)

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
        // Home. Somebody who has just finished the introduction has not
        // chosen a folder to land on, and should not have been asked to.
        reply(id, ["page": 0])
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

        // The three readings the menu draws across its top.
        var seen: [Quick.Reading] = []
        for one in body["readings"] as? [Any] ?? [] {
            guard let row = one as? [String: Any] else { continue }
            let name = Web.clean(row["name"] as? String ?? "", limit: 20)
            let value = Web.clean(row["value"] as? String ?? "", limit: 12)
            let unit = Web.clean(row["unit"] as? String ?? "", limit: 20)
            let part = (row["part"] as? NSNumber)?.doubleValue ?? 0
            guard !name.isEmpty, !value.isEmpty else { continue }
            seen.append(Quick.Reading(name: name, value: value, unit: unit, part: min(max(part, 0), 1)))
            if seen.count == 3 { break }
        }
        Quick.shared.readings = seen
    }

    /// Where the page's title strip is, and which parts of it are buttons.
    private func chrome(_ body: [String: Any]) {
        if let page = body["page"] as? NSNumber { showing = page.intValue }
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
}

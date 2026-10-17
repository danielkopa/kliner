//
//  Nearby.swift — sending a file to somebody's @username.
//
//  Straight from this Mac to theirs. There is no server: Macs on the same
//  network find each other by the @username each has claimed, the other Mac
//  says yes before anything arrives, and the file goes across byte for byte,
//  exactly as it is on disk. Nothing is compressed, converted or re-encoded,
//  and it lands in Downloads under its own name.
//
//  A username is claimed on this Mac and announced to the Macs that can see
//  it. Before it is claimed, Kliner looks for a Mac nearby that already
//  answers to it; if two Macs that have never met claimed the same one, the
//  one that claimed it first keeps it when they do meet, and the other is
//  told to pick again. Nothing leaves the local network.
//

import AppKit
import Foundation
import MultipeerConnectivity

final class Nearby: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    static let shared = Nearby()

    /// Bonjour's name for Kliner: `_kliner-send._tcp` in Info.plist.
    static let service = "kliner-send"

    /// Everything the page is told, as it happens.
    var tell: ((_ event: [String: Any]) -> Void)?
    /// Somebody is sending you something: the window comes forward.
    var wake: (() -> Void)?

    /// The claimed @username, without the @. Empty until one is claimed.
    private(set) var user = ""
    private var claimedAt = 0
    /// This Mac, as Kliner knows it: made once, kept in the app's defaults.
    private let device: String

    private var me = MCPeerID(displayName: "Kliner")
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// Why the browser is running: a name being checked, the send window
    /// open. It stops when nobody needs it.
    private var looking = 0

    private struct Seen { let user: String; let device: String; let at: Int }
    /// The Kliners nearby, by the peer each one is.
    private var seen: [MCPeerID: Seen] = [:]

    private struct Outgoing {
        let id: String
        let url: URL
        let name: String
        let size: Int64
        let to: String
        var peer: MCPeerID?
        var progress: Progress?
        var over = false
    }
    private struct Incoming {
        let id: String
        let from: String
        let name: String
        let size: Int64
        let peer: MCPeerID
        var answer: ((Bool, MCSession?) -> Void)?
        var progress: Progress?
        var over = false
    }
    private var outgoing: [String: Outgoing] = [:]
    private var incoming: [String: Incoming] = [:]
    /// One session per file, so one file finishing, failing or being
    /// cancelled never touches another.
    private var sessions: [String: MCSession] = [:]
    private var ticker: Timer?

    /// Files picked in the send window, by a token the page holds. The page
    /// never sees or names a path.
    private var picked: [String: URL] = [:]

    private override init() {
        let defaults = UserDefaults.standard
        if let known = defaults.string(forKey: "kliner.device"), !known.isEmpty {
            device = known
        } else {
            device = UUID().uuidString
            defaults.set(device, forKey: "kliner.device")
        }
        super.init()
    }

    // MARK: starting

    /// Called once the window is up: announce the name, if there is one and
    /// receiving is on.
    func start() {
        let name = Config.value("user") ?? ""
        user = Nearby.valid(name) == nil ? name : ""
        claimedAt = Int(Config.value("userAt") ?? "") ?? 0
        rebuild()
    }

    /// Whether Macs nearby may send files here. On unless turned off.
    var receiving: Bool { Config.value("receive") != "off" }

    func setReceiving(_ on: Bool) {
        Config.set("receive", on ? "on" : "off")
        rebuild()
    }

    /// A new peer for a new name: the advertiser and browser are made again,
    /// and every session made with the old one is left to finish on its own.
    private func rebuild() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        let wasLooking = browser != nil
        browser?.stopBrowsingForPeers()
        browser = nil
        seen = [:]
        me = MCPeerID(displayName: user.isEmpty ? "Kliner" : String(("@" + user).prefix(60)))
        if !user.isEmpty && receiving {
            let info = ["u": user, "d": device, "t": String(claimedAt), "v": "1"]
            let one = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: info, serviceType: Nearby.service)
            one.delegate = self
            one.startAdvertisingPeer()
            advertiser = one
        }
        if wasLooking || looking > 0 { lookAround() }
    }

    private func lookAround() {
        if browser != nil { return }
        let one = MCNearbyServiceBrowser(peer: me, serviceType: Nearby.service)
        one.delegate = self
        one.startBrowsingForPeers()
        browser = one
    }

    private func stopLooking() {
        guard looking == 0, outgoing.values.allSatisfy({ $0.over }) else { return }
        browser?.stopBrowsingForPeers()
        browser = nil
        seen = [:]
    }

    // MARK: the name

    /// What is wrong with a name, in a sentence, or nil when it will do.
    /// Three to twenty letters, digits, dots and underscores, starting with a
    /// letter: short enough to say, and the same on every Mac.
    static func valid(_ name: String) -> String? {
        if name.count < 3 { return "At least 3 characters." }
        if name.count > 20 { return "20 characters at most." }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Small letters, numbers, . and _ only."
        }
        guard let first = name.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else {
            return "Start with a letter."
        }
        if name.hasSuffix(".") || name.contains("..") { return "A dot needs a letter on each side." }
        if ["kliner", "admin", "root", "support", "help", "system", "apple", "everyone", "nobody"].contains(name) {
            return "That one is kept by Kliner."
        }
        return nil
    }

    /// Whether a Mac nearby already answers to a name: the Macs in sight
    /// are looked at for a moment and a half, then the answer comes back.
    func check(_ raw: String, done: @escaping ([String: Any]) -> Void) {
        let name = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let why = Nearby.valid(name) {
            done(["ok": false, "bad": why])
            return
        }
        if name == user {
            done(["ok": true, "mine": true, "name": name])
            return
        }
        looking += 1
        lookAround()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.looking = max(0, self.looking - 1)
            let taken = self.seen.values.contains { $0.user == name && $0.device != self.device }
            self.stopLooking()
            done(["ok": true, "name": name, "free": !taken, "taken": taken])
        }
    }

    /// The name is yours: written down, and announced.
    func claim(_ raw: String, done: @escaping ([String: Any]) -> Void) {
        check(raw) { [weak self] answer in
            guard let self = self else { return }
            guard answer["ok"] as? Bool == true, let name = answer["name"] as? String else {
                done(answer)
                return
            }
            if answer["taken"] as? Bool == true {
                done(["ok": false, "taken": true, "name": name])
                return
            }
            if name != self.user {
                self.user = name
                self.claimedAt = Int(Date().timeIntervalSince1970)
                Config.set("user", name)
                Config.set("userAt", String(self.claimedAt))
                self.rebuild()
            }
            done(["ok": true, "user": name])
        }
    }

    // MARK: who is nearby

    /// The send window opens (`on`) or closes: while it is open the Macs
    /// nearby are watched, and every change is told to the page.
    func watch(_ on: Bool) {
        if on {
            looking += 1
            lookAround()
            tellNearby()
        } else {
            looking = max(0, looking - 1)
            stopLooking()
        }
    }

    /// Everybody nearby, one row each: the name, and whether it is a clash
    /// with the name this Mac has.
    private func tellNearby() {
        var best: [String: Seen] = [:]
        for one in seen.values where one.device != device {
            if let known = best[one.user], known.at <= one.at { continue }
            best[one.user] = one
        }
        let people = best.keys.sorted().map { ["user": $0] }
        tell?(["kind": "nearby", "people": people])
        // Two Macs with one name: whoever claimed it first keeps it.
        if !user.isEmpty, let other = best[user], other.at > 0, claimedAt > 0, other.at < claimedAt {
            tell?(["kind": "clash", "user": user])
        }
    }

    /// The peer a name belongs to: the one that claimed it first, if two do.
    private func peer(for name: String) -> MCPeerID? {
        var found: (MCPeerID, Int)?
        for (peer, one) in seen where one.user == name && one.device != device {
            if found == nil || one.at < found!.1 { found = (peer, one.at) }
        }
        return found?.0
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard let info = info, let name = info["u"], Nearby.valid(name) == nil, let device = info["d"] else { return }
            self.seen[peerID] = Seen(user: name, device: device, at: Int(info["t"] ?? "") ?? 0)
            self.tellNearby()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.seen[peerID] = nil
            self.tellNearby()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.tell?(["kind": "offline", "text": "Kliner cannot look for Macs nearby. Check that Local Network is allowed for Kliner in System Settings › Privacy & Security."])
        }
    }

    // MARK: sending

    /// The file to send, picked with the Mac's own chooser. Only files: a
    /// folder would have to be packed into something else first, and what
    /// arrives has to be exactly what was sent.
    func pick(done: @escaping ([String: Any]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "The file goes across exactly as it is: nothing is compressed."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { answer in
            guard answer == .OK, let url = panel.url else {
                done(["cancelled": true])
                return
            }
            done(self.hold(url))
        }
    }

    /// A file the page already knows by folder and name — one on the
    /// desktop, say — held the same way as a picked one.
    func hold(_ url: URL) -> [String: Any] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return ["ok": false, "text": "Only a file can be sent, not a folder."]
        }
        let token = UUID().uuidString
        picked[token] = url
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        var out: [String: Any] = ["ok": true, "token": token, "name": url.lastPathComponent, "size": size]
        if let icon = Nearby.icon(of: url) { out["icon"] = icon }
        return out
    }

    /// The file a token stands for, so it can go another way than straight across.
    func held(_ token: String) -> URL? {
        return picked[token]
    }

    /// Whether a Mac in sight answers to this name right now.
    func sees(_ raw: String) -> Bool {
        let name = raw.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return peer(for: name) != nil
    }

    /// Send a held file to a name. The page is told every step: asking,
    /// sending with how far along it is, done or failed and why.
    func send(token: String, to raw: String) -> [String: Any] {
        let name = raw.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard let url = picked[token] else { return ["ok": false, "text": "Pick the file again."] }
        guard Nearby.valid(name) == nil else { return ["ok": false, "text": "That is not a username."] }
        guard name != user else { return ["ok": false, "text": "That is you."] }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0)
        let id = UUID().uuidString
        var job = Outgoing(id: id, url: url, name: url.lastPathComponent, size: size, to: name)
        guard let target = peer(for: name) else {
            return ["ok": false, "text": "@\(name) is not nearby. Both Macs need Kliner open, on the same network."]
        }
        job.peer = target
        outgoing[id] = job
        let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        sessions[id] = session
        let context: [String: Any] = ["t": "file", "id": id, "from": user, "name": job.name, "size": size]
        let data = try? JSONSerialization.data(withJSONObject: context)
        browser?.invitePeer(target, to: session, withContext: data, timeout: 60)
        return ["ok": true, "id": id, "to": name, "name": job.name, "size": size]
    }

    /// Stop a file on its way, either way.
    func cancel(_ id: String) {
        if var job = outgoing[id], !job.over {
            job.progress?.cancel()
            job.over = true
            outgoing[id] = job
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
        if var job = incoming[id], !job.over {
            job.answer?(false, nil)
            job.answer = nil
            job.progress?.cancel()
            job.over = true
            incoming[id] = job
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
        end(id)
    }

    // MARK: receiving

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.receiving,
                  let data = context,
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  info["t"] as? String == "file",
                  let id = info["id"] as? String, id.count <= 64, self.incoming[id] == nil,
                  let name = info["name"] as? String,
                  let size = (info["size"] as? NSNumber)?.int64Value, size >= 0 else {
                invitationHandler(false, nil)
                return
            }
            let from = (info["from"] as? String).flatMap { Nearby.valid($0) == nil ? $0 : nil } ?? "someone"
            let clean = Nearby.cleanName(name)
            self.incoming[id] = Incoming(id: id, from: from, name: clean, size: size, peer: peerID, answer: invitationHandler)
            self.wake?()
            self.tell?(["kind": "incoming", "id": id, "from": from, "name": clean, "size": size])
            // A question nobody answers is a no, after a minute.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                guard let self = self, var job = self.incoming[id], let answer = job.answer else { return }
                answer(false, nil)
                job.answer = nil
                job.over = true
                self.incoming[id] = job
                self.tell?(["kind": "state", "id": id, "state": "failed", "text": "Nobody answered, so it was not taken."])
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.tell?(["kind": "offline", "text": "Macs nearby cannot see you yet. Check that Local Network is allowed for Kliner in System Settings › Privacy & Security."])
        }
    }

    /// Yes or no to a file on its way here. Yes only if there is room for it.
    func answer(_ id: String, yes: Bool) {
        guard var job = incoming[id], let answer = job.answer else { return }
        job.answer = nil
        if yes {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let room = ((try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage) ?? Int64.max
            if room < job.size + 200_000_000 {
                answer(false, nil)
                job.over = true
                incoming[id] = job
                tell?(["kind": "state", "id": id, "state": "failed", "text": "There is not enough room on this Mac for it."])
                return
            }
            let session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            sessions[id] = session
            incoming[id] = job
            answer(true, session)
            tell?(["kind": "state", "id": id, "state": "waiting"])
        } else {
            answer(false, nil)
            job.over = true
            incoming[id] = job
        }
    }

    // MARK: the session, for both

    private func idOf(_ session: MCSession) -> String? {
        sessions.first(where: { $0.value === session })?.key
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard let id = self.idOf(session) else { return }
            if var job = self.outgoing[id], !job.over {
                if state == .connected, job.progress == nil {
                    job.progress = session.sendResource(at: job.url, withName: id, toPeer: peerID) { [weak self] error in
                        DispatchQueue.main.async { self?.sent(id, error) }
                    }
                    self.outgoing[id] = job
                    self.tell?(["kind": "state", "id": id, "state": "sending"])
                    self.tick()
                } else if state == .notConnected {
                    job.over = true
                    self.outgoing[id] = job
                    let text = job.progress == nil ? "@\(job.to) did not take it." : "The connection to @\(job.to) dropped."
                    self.tell?(["kind": "state", "id": id, "state": "failed", "text": text])
                    self.end(id)
                }
            }
            if var job = self.incoming[id], !job.over, state == .notConnected, job.answer == nil {
                job.over = true
                self.incoming[id] = job
                self.tell?(["kind": "state", "id": id, "state": "failed", "text": "The connection to @\(job.from) dropped."])
                self.end(id)
            }
        }
    }

    private func sent(_ id: String, _ error: Error?) {
        guard var job = outgoing[id], !job.over else { return }
        job.over = true
        outgoing[id] = job
        if error == nil {
            tell?(["kind": "state", "id": id, "state": "done", "to": job.to, "name": job.name, "size": job.size])
        } else {
            tell?(["kind": "state", "id": id, "state": "failed", "text": "It did not get all the way to @\(job.to)."])
        }
        // a moment for the other side to finish writing it before the session goes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.end(id) }
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async {
            guard var job = self.incoming[resourceName], !job.over else { return }
            job.progress = progress
            self.incoming[resourceName] = job
            self.tell?(["kind": "state", "id": resourceName, "state": "receiving"])
            self.tick()
        }
    }

    /// The file is here. macOS takes the copy it wrote away the moment this
    /// returns, so it is moved into Downloads before anything else happens.
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        var job: Incoming?
        DispatchQueue.main.sync { job = self.incoming[resourceName] }
        guard let one = job, !one.over else { return }
        var saved: URL?
        var problem: String?
        if let temp = localURL, error == nil {
            let size = Int64((try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? -1)
            if size != one.size {
                problem = "It arrived, but not whole, so it was not kept."
            } else {
                let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
                let target = Nearby.free(one.name, in: downloads)
                do {
                    try FileManager.default.moveItem(at: temp, to: target)
                    saved = target
                } catch {
                    problem = "It arrived, but could not be put in Downloads."
                }
            }
        } else {
            problem = "It did not get all the way here."
        }
        DispatchQueue.main.async {
            guard var job = self.incoming[resourceName] else { return }
            job.over = true
            self.incoming[resourceName] = job
            if let saved = saved {
                self.tell?(["kind": "state", "id": resourceName, "state": "done", "from": job.from,
                            "name": saved.lastPathComponent, "size": job.size, "path": saved.path])
            } else {
                self.tell?(["kind": "state", "id": resourceName, "state": "failed", "text": problem ?? "It did not arrive."])
            }
            self.end(resourceName)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    /// A file that is over: its session goes, and the browser if nothing
    /// else needs it.
    private func end(_ id: String) {
        if let session = sessions[id] {
            session.disconnect()
            sessions[id] = nil
        }
        stopLooking()
    }

    /// How far along every file is, four times a second, while one moves.
    private func tick() {
        if ticker != nil { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            var moving = false
            for job in self.outgoing.values where !job.over {
                guard let progress = job.progress else { continue }
                moving = true
                self.tell?(["kind": "progress", "id": job.id, "part": progress.fractionCompleted])
            }
            for job in self.incoming.values where !job.over {
                guard let progress = job.progress else { continue }
                moving = true
                self.tell?(["kind": "progress", "id": job.id, "part": progress.fractionCompleted])
            }
            if !moving {
                timer.invalidate()
                self.ticker = nil
            }
        }
    }

    // MARK: small things

    /// A name to save under: its own, without any way out of the folder.
    static func cleanName(_ name: String) -> String {
        var one = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        one = one.components(separatedBy: .newlines).joined(separator: " ")
        while one.hasPrefix(".") { one.removeFirst() }
        one = one.trimmingCharacters(in: .whitespaces)
        if one.isEmpty { one = "From Kliner" }
        return String(one.prefix(200))
    }

    /// A name nobody is using in that folder yet: "poster 2.jpg" after "poster.jpg".
    static func free(_ name: String, in folder: URL) -> URL {
        let manager = FileManager.default
        var target = folder.appendingPathComponent(name)
        if !manager.fileExists(atPath: target.path) { return target }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while manager.fileExists(atPath: target.path), n < 1000 {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return target
    }

    /// Finder's own icon for a file, small, for the send window.
    static func icon(of url: URL) -> String? {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// Where a received file is, shown in Finder. Only inside Downloads.
    static func reveal(_ path: String) {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(downloads + "/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

//
//  Cloud.swift — sending a file to somebody's @username, anywhere.
//
//  Nearby.swift sends straight across when both Macs are on one network.
//  This is the way for every other time: the file goes up to kliner.app and
//  waits there, for up to a week, until Kliner opens on the other Mac and
//  asks for it. It is locked before it leaves this Mac, with a key made for
//  that one file, and that key is locked again so only the other Mac can
//  open it. kliner.app keeps pieces it cannot read: not the file's name, not
//  its real size, not a byte of it. What arrives is checked against the
//  fingerprint taken before it left, and lands in Downloads under its own
//  name, exactly as it was sent.
//
//  The @username is kept by kliner.app too, so it is one name everywhere,
//  tied to a key that is made on this Mac and never leaves it. The same
//  place keeps the profile you may choose to publish.
//

import CryptoKit
import Foundation

final class Cloud {
    static let shared = Cloud()

    /// kliner.app's own address. `cloud = https://…` in ~/.nimo/config
    /// points Kliner at another one, for a server that is not the real one yet.
    static let home = "https://api.kliner.app"
    /// A file goes up in pieces of this much of it, each locked on its own,
    /// so a piece that did not make it is sent again and not the whole file.
    static let chunk = 8_388_608
    /// What locking adds to a piece: its nonce in front and its tag behind.
    static let extra = 28
    /// The most kliner.app keeps for one file, locked: 5 GiB.
    static let most: Int64 = 5_368_709_120
    /// How often the inbox, and the files waiting to be taken, are looked at.
    static let every: TimeInterval = 20
    /// How often kliner.app is asked while Kliner is behind other apps.
    static let quietEvery: TimeInterval = 120
    static let offline = "Kliner cannot reach kliner.app right now."
    /// Names kliner.app keeps for itself.
    static let reserved: Set<String> = ["kliner", "admin", "root", "support", "help", "system", "apple",
                                        "everyone", "nobody", "api", "www", "about", "privacy", "terms",
                                        "beta", "waitlist", "profile", "settings", "login", "signup", "me",
                                        "mail", "team", "staff"]

    /// Everything the page is told, as it happens.
    var tell: ((_ event: [String: Any]) -> Void)?
    /// Somebody is sending you something: the window comes forward.
    var wake: (() -> Void)?

    /// The @username kliner.app knows this Mac by, without the @. Empty
    /// until one is claimed there.
    private(set) var user = ""
    /// Whether the last request got an answer from kliner.app, whatever the
    /// answer was.
    private(set) var reachable = false

    /// This Mac, as Kliner knows it: made once, kept in the app's defaults,
    /// the same one Nearby uses.
    private let device: String
    private let session: URLSession
    /// Reads the time off kliner.app's answers.
    private let clock: DateFormatter
    /// How far this Mac's clock is from kliner.app's, in seconds, once an
    /// answer has said so. A signature carries the time, and a Mac whose
    /// clock is wrong would otherwise be turned away for ever.
    private var skew = 0

    /// The two keys, made once on this Mac, and the name they hold.
    private struct Identity {
        let sign: Curve25519.Signing.PrivateKey
        let box: Curve25519.KeyAgreement.PrivateKey
        var user: String
        var at: Int
    }
    private var identity: Identity?

    /// The part of a file's journey that happens away from the main thread:
    /// reading or writing it, and keeping its fingerprint. Only its own
    /// queue touches it, so one big file never holds up another.
    private final class Flow {
        let queue = DispatchQueue(label: "app.kliner.cloud.file", qos: .utility, autoreleaseFrequency: .workItem)
        var hasher = SHA256()
        var done: Int64 = 0
        var stopped = false
    }

    private struct Outgoing {
        let id: String
        let url: URL
        let name: String
        let size: Int64
        let to: String
        /// Who it is from: the name this Mac had when it was sent, or the
        /// one it changed to since (renamed).
        var from: String
        let flow: Flow
        /// kliner.app's own id for it, once it has one.
        var server = ""
        var key: SymmetricKey?
        var sha = ""
        /// The size read while the fingerprint was taken.
        var length: Int64 = 0
        var parts = 0
        var expires = 0
        /// Up on kliner.app, whole, waiting to be taken.
        var waiting = false
        var over = false
    }
    private struct Incoming {
        /// kliner.app's id for it, which is the page's too.
        let id: String
        let from: String
        /// Who it is for: the name this Mac had when it was offered, or the
        /// one it changed to since (renamed).
        var to: String
        let name: String
        let size: Int64
        let sha: String
        let parts: Int
        let chunk: Int
        let key: SymmetricKey
        var flow: Flow?
        var temp: URL?
        var answered = false
        var over = false
    }
    private var outgoing: [String: Outgoing] = [:]
    private var incoming: [String: Incoming] = [:]
    /// Every file offered here since Kliner opened, so each is asked about once.
    private var announced: Set<String> = []
    /// Files that arrived whole whose "received" did not reach kliner.app
    /// yet, by id, with the name to sign as. Sent again on the next look.
    private var owed: [String: String] = [:]
    private var ticker: Timer?
    /// Kliner is behind other apps (Web says so): the inbox is looked at
    /// every two minutes instead of every twenty seconds.
    var quiet = false
    private var lastIn = Date.distantPast
    private var inboxBusy = false
    private var outboxBusy: Set<String> = []
    private var started = false

    /// What kliner.app said, or that it said nothing.
    private struct Answer {
        /// The HTTP status; 0 when kliner.app could not be reached at all.
        let status: Int
        let json: [String: Any]
        let data: Data

        var ok: Bool { return status >= 200 && status < 300 }
        var code: String { return json["error"] as? String ?? "" }

        /// What went wrong, as a sentence for the page: kliner.app's own
        /// when it gave one.
        func sentence(_ otherwise: String) -> String {
            if status == 0 { return Cloud.offline }
            if let message = json["message"] as? String {
                let one = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !one.isEmpty { return String(one.prefix(300)) }
            }
            return otherwise
        }
    }

    /// A file locked and ready to go up.
    private struct Sealed {
        let key: SymmetricKey
        let sha: String
        let size: Int64
        let parts: Int
        let bytes: Int64
        let header: String
    }
    /// What the other Mac locked inside a header for this one.
    private struct Offered {
        let key: SymmetricKey
        let name: String
        let size: Int64
        let sha: String
        let chunk: Int
    }
    /// How a piece that came down went.
    private enum Taken { case fine, bad, unwritten }

    private init() {
        let defaults = UserDefaults.standard
        var known = defaults.string(forKey: "kliner.device") ?? ""
        if known.isEmpty {
            known = UUID().uuidString
            defaults.set(known, forKey: "kliner.device")
        }
        device = known

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(secondsFromGMT: 0)
        stamp.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        clock = stamp
    }

    // MARK: starting

    /// Called once the window is up: the keys are read, and if they hold a
    /// name, the inbox is looked at now and every twenty seconds after.
    func start() {
        identity = Cloud.load()
        user = identity?.user ?? ""
        if !started {
            started = true
            // Pieces of a file that was on its way when Kliner last quit are
            // of no use now: it is offered again, from the start.
            try? FileManager.default.removeItem(at: Cloud.incomingFolder)
        }
        if !user.isEmpty {
            listen()
            tick()
        }
    }

    /// Whether an id is one of the files going through kliner.app, and not
    /// one going straight across.
    func owns(_ id: String) -> Bool {
        return outgoing[id] != nil || incoming[id] != nil
    }

    // MARK: the name

    /// What is wrong with a name, in a sentence, or nil when it will do.
    /// The same rule as Nearby's, and kliner.app's: three to twenty letters,
    /// digits, dots and underscores, starting with a letter.
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
        if Cloud.reserved.contains(name) { return "That one is kept by Kliner." }
        return nil
    }

    /// A name as it was typed: small letters, no spaces around it, no @.
    private static func bare(_ raw: String) -> String {
        return raw.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    /// The page shape for "kliner.app did not answer".
    private static var away: [String: Any] {
        return ["ok": false, "offline": true, "bad": Cloud.offline]
    }

    /// Whether a name is free on kliner.app.
    func check(_ raw: String, done: @escaping ([String: Any]) -> Void) {
        let name = Cloud.bare(raw)
        if let why = Cloud.valid(name) {
            done(["ok": false, "bad": why])
            return
        }
        if name == user {
            done(["ok": true, "mine": true, "name": name, "free": false, "taken": false])
            return
        }
        call("GET", "/v1/names/\(name)", tries: 1) { answer in
            if answer.status == 0 {
                done(Cloud.away)
                return
            }
            guard answer.ok else {
                done(["ok": false, "bad": answer.sentence("Kliner could not check that name.")])
                return
            }
            let reason = answer.json["reason"] as? String ?? "taken"
            if answer.json["free"] as? Bool == true {
                done(["ok": true, "name": name, "free": true, "taken": false])
            } else if reason == "taken" {
                done(["ok": true, "name": name, "free": false, "taken": true])
            } else if reason == "held" || reason == "claimed" {
                // kept for somebody for a while: for its owner, who changed it
                // a moment ago, or for whoever has the code kliner.app showed
                var out: [String: Any] = ["ok": true, "name": name, "free": false, "taken": false, reason: true,
                                          "text": answer.sentence("That one is held for now.")]
                if let until = (answer.json["until"] as? NSNumber)?.intValue { out["until"] = until }
                if reason == "held", name == (Config.value("userWas") ?? "") { out["yours"] = true }
                done(out)
            } else {
                done(["ok": false, "bad": answer.sentence("That one cannot be used.")])
            }
        }
    }

    /// The name is yours, on kliner.app: the keys are made if there are none
    /// yet, and the name is asked for with them. Asking again for the name
    /// this Mac already holds is fine, and puts it back if kliner.app lost it.
    /// A Mac that has another name already changes it instead (rename): one
    /// name a Mac. `code` is the one kliner.app showed for a name held there.
    func claim(_ raw: String, code: String = "", done: @escaping ([String: Any]) -> Void) {
        let name = Cloud.bare(raw)
        if let why = Cloud.valid(name) {
            done(["ok": false, "bad": why])
            return
        }
        if !user.isEmpty && name != user {
            rename(name, code: code, done: done)
            return
        }
        guard let mine = keys() else {
            done(["ok": false, "bad": "Kliner could not keep its keys on this Mac."])
            return
        }
        var body: [String: Any] = [
            "name": name,
            "sign": Cloud.b64u(mine.sign.publicKey.rawRepresentation),
            "box": Cloud.b64u(mine.box.publicKey.rawRepresentation),
            "device": String(device.prefix(64)),
        ]
        let held = code.trimmingCharacters(in: .whitespaces)
        if !held.isEmpty { body["claim"] = String(held.prefix(40)) }
        call("POST", "/v1/users", json: body, signed: true, by: name) { [weak self] answer in
            guard let self = self else { return }
            if answer.status == 200 || answer.status == 201 {
                let at = (answer.json["created"] as? NSNumber)?.intValue ?? Int(Date().timeIntervalSince1970)
                if var one = self.identity {
                    one.user = name
                    one.at = at
                    Cloud.save(one)
                    self.identity = one
                }
                self.user = name
                Config.set("user", name)
                Config.set("userAt", String(at))
                self.listen()
                self.tick()
                done(["ok": true, "user": name])
            } else if answer.status == 0 {
                done(Cloud.away)
            } else if let held = Cloud.heldAnswer(answer, name) {
                done(held)
            } else if answer.status == 409 || answer.code == "taken" {
                done(["ok": false, "taken": true, "name": name])
            } else {
                done(["ok": false, "bad": answer.sentence("Kliner could not claim that name.")])
            }
        }
    }

    /// The page shape for a name kliner.app is keeping for somebody, or for
    /// a code that does not hold it; nil for every other answer.
    private static func heldAnswer(_ answer: Answer, _ name: String) -> [String: Any]? {
        switch answer.code {
        case "claimed": return ["ok": false, "claimed": true, "name": name, "bad": answer.sentence("Somebody is holding that name on kliner.app.")]
        case "wrong_code": return ["ok": false, "wrongCode": true, "name": name, "bad": answer.sentence("That code does not hold this name.")]
        case "held": return ["ok": false, "held": true, "name": name, "bad": answer.sentence("That name is kept for somebody for now.")]
        case "has_name": return ["ok": false, "bad": answer.sentence("This Mac has a name on kliner.app already.")]
        default: return nil
        }
    }

    /// A new name for the same Mac and the same keys. kliner.app moves the
    /// profile and every file on its way to it, and keeps the old name for
    /// this Mac for a week, so changing back is the same call; the files on
    /// their way from here sign as the new name from now on.
    func rename(_ raw: String, code: String = "", done: @escaping ([String: Any]) -> Void) {
        let name = Cloud.bare(raw)
        if let why = Cloud.valid(name) {
            done(["ok": false, "bad": why])
            return
        }
        if user.isEmpty {
            claim(name, code: code, done: done)
            return
        }
        if identity == nil { identity = Cloud.load() }
        guard identity != nil else {
            done(["ok": false, "bad": "Kliner could not read its keys on this Mac."])
            return
        }
        if name == user {
            done(["ok": true, "user": name])
            return
        }
        var body: [String: Any] = ["name": name]
        let held = code.trimmingCharacters(in: .whitespaces)
        if !held.isEmpty { body["claim"] = String(held.prefix(40)) }
        let was = user
        call("POST", "/v1/users/me/name", json: body, signed: true, by: was) { [weak self] answer in
            guard let self = self else { return }
            if answer.ok {
                let now = Cloud.bare(answer.json["name"] as? String ?? name)
                let until = (answer.json["until"] as? NSNumber)?.intValue ?? 0
                self.renamed(from: was, to: Cloud.valid(now) == nil ? now : name)
                Config.set("userWas", was)
                Config.set("userWasUntil", String(until))
                done(["ok": true, "user": self.user, "was": was, "until": until])
            } else if answer.status == 0 {
                done(Cloud.away)
            } else if let held = Cloud.heldAnswer(answer, name) {
                done(held)
            } else if answer.code == "taken" {
                done(["ok": false, "taken": true, "name": name])
            } else {
                done(["ok": false, "bad": answer.sentence("Kliner could not change your name.")])
            }
        }
    }

    /// Everything here that said the old name says the new one: the keys'
    /// file, the config Nearby reads, and every file still on its way.
    private func renamed(from was: String, to name: String) {
        if var one = identity {
            one.user = name
            Cloud.save(one)
            identity = one
        }
        user = name
        Config.set("user", name)
        Config.set("userAt", String(Int(Date().timeIntervalSince1970)))
        for (id, var job) in outgoing where job.from == was {
            job.from = name
            outgoing[id] = job
        }
        for (id, var job) in incoming where job.to == was {
            job.to = name
            incoming[id] = job
        }
        for (id, who) in owed where who == was { owed[id] = name }
        listen()
        tick()
    }

    /// The account goes from kliner.app, with its profile and every file on
    /// its way to or from it, and then the keys go from this Mac.
    func deleteAccount(done: @escaping ([String: Any]) -> Void) {
        if identity == nil { identity = Cloud.load() }
        guard !user.isEmpty, identity != nil else {
            forget()
            done(["ok": true])
            return
        }
        call("DELETE", "/v1/users/me", signed: true) { [weak self] answer in
            guard let self = self else { return }
            // Not known there any more, or not with these keys: there is
            // nothing left on kliner.app for this Mac to delete.
            if answer.ok || answer.status == 404 || (answer.status == 401 && answer.code == "bad_signature") {
                self.forget()
                done(["ok": true])
            } else if answer.status == 0 {
                done(Cloud.away)
            } else {
                done(["ok": false, "bad": answer.sentence("Kliner could not delete your account.")])
            }
        }
    }

    /// Everything this Mac knew about its account, gone: the name, the keys,
    /// and every file still on its way.
    private func forget() {
        for id in Array(outgoing.keys) {
            guard var job = outgoing[id], !job.over else { continue }
            job.over = true
            outgoing[id] = job
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
        for id in Array(incoming.keys) {
            guard var job = incoming[id], !job.over else { continue }
            job.over = true
            incoming[id] = job
            drop(job)
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
        ticker?.invalidate()
        ticker = nil
        owed = [:]
        identity = nil
        user = ""
        try? FileManager.default.removeItem(at: Cloud.identityFile)
        Config.set("user", "")
        Config.set("userAt", "")
    }

    // MARK: the public profile

    /// Your public page at kliner.app/@name, as the page wrote it. kliner.app
    /// checks every field and drops what it does not know.
    func publish(_ profile: [String: Any], done: @escaping ([String: Any]) -> Void) {
        guard !user.isEmpty else {
            done(["ok": false, "bad": "Claim your username first."])
            return
        }
        call("PUT", "/v1/profile", json: profile, signed: true) { answer in
            if answer.ok {
                var out: [String: Any] = ["ok": true]
                if let url = answer.json["url"] as? String { out["url"] = url }
                done(out)
            } else if answer.status == 0 {
                done(Cloud.away)
            } else {
                done(["ok": false, "bad": answer.sentence("Kliner could not publish your profile.")])
            }
        }
    }

    /// Your public page as kliner.app has it, or null when it is not public.
    func profile(done: @escaping ([String: Any]) -> Void) {
        guard !user.isEmpty else {
            done(["ok": false, "bad": "Claim your username first."])
            return
        }
        call("GET", "/v1/users/\(user)/profile", tries: 1) { answer in
            if answer.status == 404 {
                done(["ok": true, "profile": NSNull()])
            } else if answer.ok {
                done(["ok": true, "profile": answer.json])
            } else if answer.status == 0 {
                done(Cloud.away)
            } else {
                done(["ok": false, "bad": answer.sentence("Kliner could not read your profile.")])
            }
        }
    }

    // MARK: sending

    /// Send a file to a name through kliner.app. The answer comes at once;
    /// the page is then told every step: sending and how far along it is,
    /// up and waiting to be taken, done or failed and why.
    func send(_ url: URL, to raw: String) -> [String: Any] {
        let name = Cloud.bare(raw)
        guard !user.isEmpty, identity != nil else {
            return ["ok": false, "text": "Claim your username first, so they know who it is from."]
        }
        guard Cloud.valid(name) == nil else { return ["ok": false, "text": "That is not a username."] }
        guard name != user else { return ["ok": false, "text": "That is you."] }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            return ["ok": false, "text": "That file is not there any more."]
        }
        guard !isFolder.boolValue else { return ["ok": false, "text": "Only a file can be sent, not a folder."] }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0)
        guard Cloud.sealedSize(size, chunk: Cloud.chunk) <= Cloud.most else {
            return ["ok": false, "text": "Kliner can send up to 5 GB at a time through kliner.app."]
        }
        let id = UUID().uuidString
        let job = Outgoing(id: id, url: url, name: url.lastPathComponent, size: size, to: name, from: user, flow: Flow())
        outgoing[id] = job
        find(id)
        return ["ok": true, "id": id, "to": name, "name": job.name, "size": size]
    }

    /// Who the file is for: their box key, which only their Mac can open with.
    private func find(_ id: String) {
        guard let job = outgoing[id], !job.over else { return }
        call("GET", "/v1/users/\(job.to)", tries: 2) { [weak self] answer in
            guard let self = self, let job = self.outgoing[id], !job.over else { return }
            if answer.status == 404 {
                self.fail(id, "There is nobody called @\(job.to).")
                return
            }
            guard answer.ok, let text = answer.json["box"] as? String,
                  let box = Cloud.unb64u(text), box.count == 32 else {
                self.fail(id, answer.sentence("Kliner could not find @\(job.to) on kliner.app."))
                return
            }
            self.tell?(["kind": "state", "id": id, "state": "sending"])
            self.lock(id, for: box)
        }
    }

    /// The file's fingerprint, its key and its header, made away from the
    /// main thread: a big file takes a while to read through.
    private func lock(_ id: String, for box: Data) {
        guard let job = outgoing[id], !job.over else { return }
        let url = job.url
        let name = job.name
        let from = job.from
        let flow = job.flow
        flow.queue.async { [weak self] in
            let (made, problem) = Cloud.prepare(url, name: name, from: from, box: box)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, var job = self.outgoing[id], !job.over else { return }
                guard let one = made else {
                    self.fail(id, problem)
                    return
                }
                job.key = one.key
                job.sha = one.sha
                job.length = one.size
                job.parts = one.parts
                self.outgoing[id] = job
                self.create(id, header: one.header, bytes: one.bytes)
            }
        }
    }

    /// Read the whole file once for its fingerprint, then lock the file's
    /// key, name, size and fingerprint so only the box key `box` opens them.
    private static func prepare(_ url: URL, name: String, from: String, box: Data) -> (Sealed?, String) {
        var hasher = SHA256()
        var size: Int64 = 0
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var more = true
            while more {
                more = try autoreleasepool { () throws -> Bool in
                    guard let data = try handle.read(upToCount: Cloud.chunk), !data.isEmpty else { return false }
                    hasher.update(data: data)
                    size += Int64(data.count)
                    return true
                }
            }
        } catch {
            return (nil, "Kliner could not read the file.")
        }
        let parts = Cloud.pieces(size, chunk: Cloud.chunk)
        let bytes = Cloud.sealedSize(size, chunk: Cloud.chunk)
        guard bytes <= Cloud.most else {
            return (nil, "Kliner can send up to 5 GB at a time through kliner.app.")
        }
        let sha = Cloud.hex(Data(hasher.finalize()))
        let key = SymmetricKey(size: .bits256)
        let raw: Data = key.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Data in
            return Data(buffer)
        }
        let secret: [String: Any] = ["k": Cloud.b64u(raw), "name": name, "size": size, "sha256": sha,
                                     "chunk": Cloud.chunk, "from": from]
        do {
            let inner = try JSONSerialization.data(withJSONObject: secret, options: [])
            let once = Curve25519.KeyAgreement.PrivateKey()
            let theirs = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: box)
            let shared = try once.sharedSecretFromKeyAgreement(with: theirs)
            let epk = once.publicKey.rawRepresentation
            let wrap = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: epk + box,
                                                      sharedInfo: Data("kliner-file-v1".utf8), outputByteCount: 32)
            let sealed = try ChaChaPoly.seal(inner, using: wrap)
            let outer: [String: Any] = ["v": 1, "epk": Cloud.b64u(epk), "box": Cloud.b64u(sealed.combined)]
            let outerData = try JSONSerialization.data(withJSONObject: outer, options: [])
            let header = Cloud.b64u(outerData)
            guard header.utf8.count <= 4096 else { return (nil, "That file's name is too long to send.") }
            return (Sealed(key: key, sha: sha, size: size, parts: parts, bytes: bytes, header: header), "")
        } catch {
            return (nil, "Kliner could not lock the file.")
        }
    }

    /// Tell kliner.app a file is coming, and how big it is locked.
    private func create(_ id: String, header: String, bytes: Int64) {
        guard let job = outgoing[id], !job.over else { return }
        let body: [String: Any] = ["to": job.to, "parts": job.parts, "bytes": bytes, "header": header]
        call("POST", "/v1/transfers", json: body, signed: true, by: job.from) { [weak self] answer in
            guard let self = self, var job = self.outgoing[id] else { return }
            let server = answer.json["id"] as? String ?? ""
            if answer.ok && Cloud.plainId(server) {
                if job.over {
                    // stopped while kliner.app was making room for it
                    self.call("DELETE", "/v1/transfers/\(server)", signed: true, by: job.from, tries: 2) { _ in }
                    return
                }
                job.server = server
                job.expires = (answer.json["expires"] as? NSNumber)?.intValue ?? 0
                self.outgoing[id] = job
                self.upload(id, part: 0)
                return
            }
            if job.over { return }
            if answer.status == 404 {
                self.fail(id, "There is nobody called @\(job.to).")
            } else {
                self.fail(id, answer.sentence("kliner.app did not take the file."))
            }
        }
    }

    /// Piece `n`, read and locked away from the main thread, then sent.
    private func upload(_ id: String, part n: Int) {
        guard let job = outgoing[id], !job.over, let key = job.key else { return }
        let url = job.url
        let length = job.length
        let flow = job.flow
        flow.queue.async { [weak self] in
            let (piece, hash) = Cloud.piece(of: url, part: n, length: length, key: key, flow: flow)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let job = self.outgoing[id], !job.over else { return }
                guard let body = piece else {
                    self.fail(id, "The file changed or could not be read while it was going up, so it was stopped.")
                    return
                }
                self.put(id, part: n, body: body, hash: hash)
            }
        }
    }

    /// Piece `n` of a file, locked with the file's key and the nonce for `n`,
    /// and the fingerprint of the locked piece for the signature. Nil when
    /// the file is no longer the size it was when its fingerprint was taken.
    private static func piece(of url: URL, part n: Int, length: Int64, key: SymmetricKey, flow: Flow) -> (Data?, String) {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let start = Int64(n) * Int64(Cloud.chunk)
            try handle.seek(toOffset: UInt64(start))
            let chunk = try handle.read(upToCount: Cloud.chunk) ?? Data()
            guard Int64(chunk.count) == min(Int64(Cloud.chunk), length - start) else { return (nil, "") }
            flow.hasher.update(data: chunk)
            let nonce = try ChaChaPoly.Nonce(data: Cloud.nonce(n))
            let sealed = try ChaChaPoly.seal(chunk, using: key, nonce: nonce)
            let body = sealed.combined
            return (body, Cloud.hex(Data(SHA256.hash(data: body))))
        } catch {
            return (nil, "")
        }
    }

    private func put(_ id: String, part n: Int, body: Data, hash: String) {
        guard let job = outgoing[id], !job.over else { return }
        call("PUT", "/v1/transfers/\(job.server)/parts/\(n)", body: body, hash: hash, signed: true,
             by: job.from, tries: 3) { [weak self] answer in
            guard let self = self, let job = self.outgoing[id], !job.over else { return }
            guard answer.ok else {
                self.fail(id, answer.sentence("It did not get all the way to kliner.app."))
                return
            }
            self.tell?(["kind": "progress", "id": id, "part": Double(n + 1) / Double(max(1, job.parts))])
            if n + 1 < job.parts {
                self.upload(id, part: n + 1)
            } else {
                self.ready(id)
            }
        }
    }

    /// Every piece is up. The file was read twice, once for its fingerprint
    /// and once to send it; only if both readings agree is it let go.
    private func ready(_ id: String) {
        guard let job = outgoing[id], !job.over else { return }
        let flow = job.flow
        let sha = job.sha
        flow.queue.async { [weak self] in
            let same = Cloud.hex(Data(flow.hasher.finalize())) == sha
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let job = self.outgoing[id], !job.over else { return }
                guard same else {
                    self.fail(id, "The file changed while it was going up, so it was stopped.")
                    return
                }
                self.call("POST", "/v1/transfers/\(job.server)/ready", signed: true, by: job.from,
                          tries: 2) { [weak self] answer in
                    guard let self = self, var job = self.outgoing[id], !job.over else { return }
                    guard answer.ok else {
                        self.fail(id, answer.sentence("kliner.app did not take the file."))
                        return
                    }
                    job.waiting = true
                    self.outgoing[id] = job
                    self.tell?(["kind": "state", "id": id, "state": "waiting",
                                "text": "Sent. @\(job.to) gets it when Kliner opens on their Mac."])
                    self.listen()
                }
            }
        }
    }

    /// Stop a file on its way, either way: one going up is taken off
    /// kliner.app, one coming here is turned down.
    func cancel(_ id: String) {
        if var job = outgoing[id], !job.over {
            job.over = true
            outgoing[id] = job
            if !job.server.isEmpty {
                call("DELETE", "/v1/transfers/\(job.server)", signed: true, by: job.from, tries: 2) { _ in }
            }
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
        if var job = incoming[id], !job.over {
            job.over = true
            job.answered = true
            incoming[id] = job
            drop(job)
            decline(job)
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Stopped."])
        }
    }

    // MARK: looking in, every twenty seconds

    /// The look every twenty seconds runs while there is something to look
    /// for: a name to receive files for, or a file waiting to be taken.
    private func listen() {
        if ticker != nil { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Cloud.every, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.tick()
        }
        timer.tolerance = 2
        ticker = timer
    }

    /// The window came forward: the inbox is looked at now, not at the next tick.
    func lookNow() {
        guard !user.isEmpty else { return }
        lastIn = Date()
        lookIn()
    }

    private func tick() {
        let waiting = outgoing.values.contains { $0.waiting && !$0.over }
        if user.isEmpty && !waiting && owed.isEmpty {
            ticker?.invalidate()
            ticker = nil
            return
        }
        // every twenty seconds while Kliner is in front, every two minutes behind
        let gap = quiet ? Cloud.quietEvery : Cloud.every
        if !user.isEmpty && Date().timeIntervalSince(lastIn) >= gap - 1 {
            lastIn = Date()
            lookIn()
        }
        if waiting { lookOut() }
        let debts = owed
        owed = [:]
        for (id, name) in debts { received(id, by: name) }
    }

    /// Files for this Mac, waiting on kliner.app.
    private func lookIn() {
        guard !inboxBusy, !user.isEmpty, identity != nil else { return }
        inboxBusy = true
        let me = user
        call("GET", "/v1/inbox", signed: true, by: me) { [weak self] answer in
            guard let self = self else { return }
            self.inboxBusy = false
            guard answer.ok, me == self.user, let rows = answer.json["transfers"] as? [[String: Any]] else { return }
            for row in rows { self.offer(row, to: me) }
        }
    }

    /// A file somebody sent: its header is opened with this Mac's box key,
    /// and the page asks you. One that cannot be opened was not locked for
    /// this Mac, or not properly, and is turned down without a word.
    private func offer(_ row: [String: Any], to me: String) {
        guard let id = row["id"] as? String, Cloud.plainId(id), !announced.contains(id), incoming[id] == nil,
              let keys = identity else { return }
        announced.insert(id)
        guard let from = row["from"] as? String, Cloud.valid(from) == nil,
              let parts = (row["parts"] as? NSNumber)?.intValue, parts >= 1, parts <= 10000,
              let bytes = (row["bytes"] as? NSNumber)?.int64Value, bytes >= 1, bytes <= Cloud.most,
              let header = row["header"] as? String,
              let secret = Cloud.unwrap(header, with: keys.box),
              let file = Cloud.unpack(secret, from: from, parts: parts, bytes: bytes) else {
            call("POST", "/v1/transfers/\(id)/decline", signed: true, by: me, tries: 1) { _ in }
            return
        }
        incoming[id] = Incoming(id: id, from: from, to: me, name: file.name, size: file.size, sha: file.sha,
                                parts: parts, chunk: file.chunk, key: file.key)
        tell?(["kind": "incoming", "id": id, "from": from, "name": file.name, "size": file.size])
        wake?()
    }

    /// The secret half of a header, opened with this Mac's box key. Nil when
    /// it was not locked for this Mac, or is not what a header looks like.
    private static func unwrap(_ header: String, with box: Curve25519.KeyAgreement.PrivateKey) -> [String: Any]? {
        guard header.utf8.count <= 4096, let raw = Cloud.unb64u(header),
              let outer = (try? JSONSerialization.jsonObject(with: raw, options: [])) as? [String: Any],
              (outer["v"] as? NSNumber)?.intValue == 1,
              let epkText = outer["epk"] as? String, let epk = Cloud.unb64u(epkText), epk.count == 32,
              let boxText = outer["box"] as? String, let locked = Cloud.unb64u(boxText) else { return nil }
        do {
            let theirs = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: epk)
            let shared = try box.sharedSecretFromKeyAgreement(with: theirs)
            let wrap = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: epk + box.publicKey.rawRepresentation,
                                                      sharedInfo: Data("kliner-file-v1".utf8), outputByteCount: 32)
            let sealed = try ChaChaPoly.SealedBox(combined: locked)
            let opened = try ChaChaPoly.open(sealed, using: wrap)
            let inner = try JSONSerialization.jsonObject(with: opened, options: [])
            return inner as? [String: Any]
        } catch {
            return nil
        }
    }

    /// What the header says, checked against itself and against what
    /// kliner.app says about the same file. Nil when they do not agree.
    private static func unpack(_ secret: [String: Any], from: String, parts: Int, bytes: Int64) -> Offered? {
        guard let text = secret["k"] as? String, let raw = Cloud.unb64u(text), raw.count == 32,
              let name = secret["name"] as? String,
              let size = (secret["size"] as? NSNumber)?.int64Value, size >= 0, size <= Cloud.most,
              let sha = (secret["sha256"] as? String)?.lowercased(), sha.utf8.count == 64, Cloud.isHex(sha),
              let chunk = (secret["chunk"] as? NSNumber)?.intValue, chunk >= 1, chunk <= 16_777_216 else { return nil }
        if let claimed = secret["from"] as? String, claimed != from { return nil }
        guard parts == Cloud.pieces(size, chunk: chunk), bytes == Cloud.sealedSize(size, chunk: chunk) else { return nil }
        return Offered(key: SymmetricKey(data: raw), name: Cloud.cleanName(name), size: size, sha: sha, chunk: chunk)
    }

    /// Files this Mac sent, looked at on kliner.app until each is taken,
    /// turned down, or left too long. Each is looked at as the name that
    /// sent it.
    private func lookOut() {
        var senders: Set<String> = []
        for job in outgoing.values where job.waiting && !job.over { senders.insert(job.from) }
        for name in senders where !outboxBusy.contains(name) {
            outboxBusy.insert(name)
            call("GET", "/v1/outbox", signed: true, by: name) { [weak self] answer in
                guard let self = self else { return }
                self.outboxBusy.remove(name)
                guard answer.ok, let rows = answer.json["transfers"] as? [[String: Any]] else { return }
                var status: [String: String] = [:]
                for row in rows {
                    if let server = row["id"] as? String, let state = row["status"] as? String {
                        status[server] = state
                    }
                }
                self.heardBack(from: name, status: status)
            }
        }
    }

    private func heardBack(from name: String, status: [String: String]) {
        let now = Int(Date().timeIntervalSince1970)
        for id in Array(outgoing.keys) {
            guard var job = outgoing[id], job.waiting, !job.over, job.from == name else { continue }
            let state = status[job.server] ?? ""
            if state == "received" {
                job.over = true
                outgoing[id] = job
                tell?(["kind": "state", "id": id, "state": "done", "to": job.to, "name": job.name, "size": job.size])
            } else if state == "declined" {
                fail(id, "@\(job.to) said no.")
            } else if state == "cancelled" {
                fail(id, "Stopped.")
            } else if state == "expired" || (job.expires > 0 && now > job.expires + 7200) {
                // kliner.app tidies up once an hour, so a file well past its
                // time is taken as gone even before it says so
                fail(id, "@\(job.to) did not take it in time.")
            }
        }
    }

    // MARK: receiving

    /// Yes or no to a file waiting on kliner.app. Yes only if there is room
    /// for it; then it comes down piece by piece into the Caches folder, and
    /// only once it is whole and matches its fingerprint does it move to
    /// Downloads.
    func answer(_ id: String, yes: Bool) {
        guard var job = incoming[id], !job.over, !job.answered else { return }
        job.answered = true
        guard yes else {
            job.over = true
            incoming[id] = job
            decline(job)
            tell?(["kind": "state", "id": id, "state": "failed", "text": "You said no."])
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let room = ((try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if room < job.size + 200_000_000 {
            job.over = true
            incoming[id] = job
            decline(job)
            tell?(["kind": "state", "id": id, "state": "failed", "text": "There is not enough room on this Mac for it."])
            return
        }
        let manager = FileManager.default
        let folder = Cloud.incomingFolder
        let temp = folder.appendingPathComponent(id + ".part")
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            job.over = true
            incoming[id] = job
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Kliner could not make room for it on this Mac."])
            return
        }
        guard manager.createFile(atPath: temp.path, contents: nil, attributes: nil) else {
            job.over = true
            incoming[id] = job
            tell?(["kind": "state", "id": id, "state": "failed", "text": "Kliner could not make room for it on this Mac."])
            return
        }
        job.flow = Flow()
        job.temp = temp
        incoming[id] = job
        tell?(["kind": "state", "id": id, "state": "receiving"])
        fetch(id, part: 0)
    }

    private func fetch(_ id: String, part n: Int) {
        guard let job = incoming[id], !job.over else { return }
        call("GET", "/v1/transfers/\(id)/parts/\(n)", signed: true, by: job.to, tries: 3) { [weak self] answer in
            guard let self = self, let job = self.incoming[id], !job.over,
                  let flow = job.flow, let temp = job.temp else { return }
            guard answer.ok else {
                var text = answer.sentence("It did not get all the way here.")
                if answer.status == 0 || answer.status >= 500 {
                    text = "The connection to kliner.app dropped. It is offered again the next time Kliner opens."
                } else if answer.status == 404 {
                    text = "It is not on kliner.app any more: @\(job.from) may have taken it back."
                }
                self.fail(id, text)
                return
            }
            let data = answer.data
            let key = job.key
            let expected = min(Int64(job.chunk), job.size - Int64(n) * Int64(job.chunk))
            flow.queue.async { [weak self] in
                let taken = Cloud.take(data, part: n, expected: expected, key: key, into: temp, flow: flow)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let job = self.incoming[id], !job.over else { return }
                    switch taken {
                    case .bad:
                        self.fail(id, "What arrived was not what was sent, so it was not kept.")
                        self.decline(job)
                    case .unwritten:
                        self.fail(id, "Kliner could not write it to this Mac.")
                    case .fine:
                        self.tell?(["kind": "progress", "id": id, "part": Double(n + 1) / Double(max(1, job.parts))])
                        if n + 1 < job.parts {
                            self.fetch(id, part: n + 1)
                        } else {
                            self.settle(id)
                        }
                    }
                }
            }
        }
    }

    /// One piece: its nonce checked against the one piece `n` must have, so
    /// pieces cannot be swapped round, then opened and added to the end.
    private static func take(_ data: Data, part n: Int, expected: Int64, key: SymmetricKey,
                             into temp: URL, flow: Flow) -> Taken {
        if flow.stopped { return .unwritten }
        guard data.count >= Cloud.extra, data.prefix(12) == Cloud.nonce(n) else { return .bad }
        let plain: Data
        do {
            let sealed = try ChaChaPoly.SealedBox(combined: data)
            plain = try ChaChaPoly.open(sealed, using: key)
        } catch {
            return .bad
        }
        guard Int64(plain.count) == expected else { return .bad }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: plain)
        } catch {
            return .unwritten
        }
        flow.hasher.update(data: plain)
        flow.done += Int64(plain.count)
        return .fine
    }

    /// Every piece is here: checked whole, moved to Downloads, and then
    /// kliner.app is told, so it can let the pieces go.
    private func settle(_ id: String) {
        guard let job = incoming[id], !job.over, let flow = job.flow, let temp = job.temp else { return }
        let name = job.name
        let size = job.size
        let sha = job.sha
        flow.queue.async { [weak self] in
            let (saved, problem) = Cloud.keep(temp, name: name, size: size, sha: sha, flow: flow)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, var job = self.incoming[id] else { return }
                let stopped = job.over
                job.over = true
                self.incoming[id] = job
                if let saved = saved {
                    // Once it is in Downloads it is yours, even if Stop came a moment too late.
                    self.received(id, by: job.to)
                    self.tell?(["kind": "state", "id": id, "state": "done", "from": job.from,
                                "name": saved.lastPathComponent, "size": job.size, "path": saved.path])
                } else if !stopped {
                    self.tell?(["kind": "state", "id": id, "state": "failed", "text": problem])
                    self.decline(job)
                }
            }
        }
    }

    /// The finished copy, moved from the Caches folder into Downloads under
    /// a name nobody there is using, when it is exactly what was sent.
    private static func keep(_ temp: URL, name: String, size: Int64, sha: String, flow: Flow) -> (URL?, String) {
        let manager = FileManager.default
        if flow.stopped {
            try? manager.removeItem(at: temp)
            return (nil, "Stopped.")
        }
        guard flow.done == size, Cloud.hex(Data(flow.hasher.finalize())) == sha else {
            try? manager.removeItem(at: temp)
            return (nil, "It arrived, but not whole, so it was not kept.")
        }
        let downloads = Cloud.downloads
        let target = Cloud.free(name, in: downloads)
        guard target.standardizedFileURL.path.hasPrefix(downloads.standardizedFileURL.path + "/") else {
            try? manager.removeItem(at: temp)
            return (nil, "It arrived, but could not be put in Downloads.")
        }
        do {
            try manager.moveItem(at: temp, to: target)
            return (target, "")
        } catch {
            try? manager.removeItem(at: temp)
            return (nil, "It arrived, but could not be put in Downloads.")
        }
    }

    /// kliner.app is told the file arrived. If it does not hear, it is told
    /// again on the next look, so the file is not offered twice.
    private func received(_ id: String, by name: String) {
        call("POST", "/v1/transfers/\(id)/received", signed: true, by: name, tries: 2) { [weak self] answer in
            guard let self = self else { return }
            if answer.status == 0 || answer.status >= 500 {
                self.owed[id] = name
                self.listen()
            }
        }
    }

    private func decline(_ job: Incoming) {
        call("POST", "/v1/transfers/\(job.id)/decline", signed: true, by: job.to, tries: 2) { _ in }
    }

    /// A file that will not get there: said once, and whatever it left on
    /// kliner.app or in the Caches folder is cleared away.
    private func fail(_ id: String, _ text: String) {
        if var job = outgoing[id], !job.over {
            job.over = true
            outgoing[id] = job
            if !job.server.isEmpty && !job.waiting {
                call("DELETE", "/v1/transfers/\(job.server)", signed: true, by: job.from, tries: 2) { _ in }
            }
            tell?(["kind": "state", "id": id, "state": "failed", "text": text])
        }
        if var job = incoming[id], !job.over {
            job.over = true
            incoming[id] = job
            drop(job)
            tell?(["kind": "state", "id": id, "state": "failed", "text": text])
        }
    }

    /// The half-made copy of a file that is not coming after all. On the
    /// file's own queue, so it happens after any piece still being written.
    private func drop(_ job: Incoming) {
        guard let flow = job.flow, let temp = job.temp else { return }
        flow.queue.async {
            flow.stopped = true
            try? FileManager.default.removeItem(at: temp)
        }
    }

    // MARK: talking to kliner.app

    /// Where requests go: `cloud = https://…` in ~/.nimo/config when it is
    /// one; else the address the build wrote into the app (KlinerCloud in
    /// Info.plist: the server deploy.sh put up, so a copy opened on another
    /// Mac talks to the same one); else kliner.app's own. Only the scheme,
    /// host and port are used.
    private var base: String {
        let built = Bundle.main.object(forInfoDictionaryKey: "KlinerCloud") as? String
        for raw in [Config.value("cloud"), built] {
            guard let raw = raw, let url = URL(string: raw),
                  url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { continue }
            if let port = url.port { return "https://\(host):\(port)" }
            return "https://\(host)"
        }
        return Cloud.home
    }

    /// One request to kliner.app, and the one place every request is made.
    /// A signed one carries the three headers kliner.app checks, made fresh
    /// for every try. `done` runs on the main queue. `tries` is how many more
    /// times it goes again when kliner.app cannot be reached or fails, for
    /// requests that can safely be made twice.
    private func call(_ method: String, _ path: String, json: [String: Any]? = nil, body: Data? = nil,
                      hash: String? = nil, signed: Bool = false, by who: String? = nil, tries: Int = 0,
                      fresh: Bool = false, done: @escaping (Answer) -> Void) {
        var payload: Data? = body
        if let json = json {
            guard JSONSerialization.isValidJSONObject(json),
                  let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
                let answer = Answer(status: 400, json: ["error": "invalid", "message": "Kliner could not write that down for kliner.app."], data: Data())
                DispatchQueue.main.async { done(answer) }
                return
            }
            payload = data
        }
        guard let url = URL(string: base + path) else {
            let answer = Answer(status: 0, json: [:], data: Data())
            DispatchQueue.main.async { done(answer) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if json != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if payload != nil {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        if signed && !sign(&request, method: method, path: path, body: payload ?? Data(), hash: hash, as: who ?? user) {
            let answer = Answer(status: 401, json: ["error": "no_user", "message": "Claim your username first."], data: Data())
            DispatchQueue.main.async { done(answer) }
            return
        }
        let again: (Int, Bool) -> Void = { [weak self] left, retried in
            self?.call(method, path, json: json, body: body, hash: hash, signed: signed, by: who,
                       tries: left, fresh: retried, done: done)
        }
        if let payload = payload {
            session.uploadTask(with: request, from: payload) { [weak self] data, response, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.heard(data, response, tries: tries, fresh: fresh, again: again, done: done)
                }
            }.resume()
        } else {
            session.dataTask(with: request) { [weak self] data, response, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.heard(data, response, tries: tries, fresh: fresh, again: again, done: done)
                }
            }.resume()
        }
    }

    /// The three headers: who is asking, when, and their signature over
    ///
    ///     KLINER1 \n METHOD \n PATH \n TIME \n hex sha256 of the body
    ///
    /// made with the signing key that never leaves this Mac. `hash` is the
    /// body's fingerprint when it was already taken, as it is for a piece.
    private func sign(_ request: inout URLRequest, method: String, path: String, body: Data,
                      hash: String?, as name: String) -> Bool {
        guard let keys = identity, !name.isEmpty else { return false }
        let time = String(Int(Date().timeIntervalSince1970) + skew)
        let digest = hash ?? Cloud.hex(Data(SHA256.hash(data: body)))
        let text = "KLINER1\n" + method.uppercased() + "\n" + path + "\n" + time + "\n" + digest
        guard let signature = try? keys.sign.signature(for: Data(text.utf8)) else { return false }
        request.setValue(name, forHTTPHeaderField: "X-Kliner-User")
        request.setValue(time, forHTTPHeaderField: "X-Kliner-Time")
        request.setValue(Cloud.b64u(signature), forHTTPHeaderField: "X-Kliner-Sig")
        return true
    }

    private func heard(_ data: Data?, _ response: URLResponse?, tries: Int, fresh: Bool,
                       again: @escaping (Int, Bool) -> Void, done: @escaping (Answer) -> Void) {
        // Only kliner.app's own answers count (it marks every one X-Kliner: 1).
        // The name can point somewhere else for a while, a parking page before
        // the Worker is wired to it, and an answer from there is no answer at
        // all: not kliner.app saying a code or a name is wrong.
        let http = (response as? HTTPURLResponse).flatMap { $0.value(forHTTPHeaderField: "X-Kliner") == "1" ? $0 : nil }
        let status = http?.statusCode ?? 0
        reachable = status > 0
        if let http = http { learnTime(http) }
        let body = data ?? Data()
        var json: [String: Any] = [:]
        // A piece of a file starts with its nonce, never with a brace.
        if status > 0, body.first == UInt8(ascii: "{"),
           let object = try? JSONSerialization.jsonObject(with: body, options: []),
           let dictionary = object as? [String: Any] {
            json = dictionary
        }
        let answer = Answer(status: status, json: json, data: body)
        if status == 401 && answer.code == "stale" && !fresh {
            // the clock was off: kliner.app's own time is known now, so once more
            again(tries, true)
            return
        }
        if (status == 0 || status >= 500) && tries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                again(tries - 1, fresh)
            }
            return
        }
        done(answer)
    }

    /// kliner.app's clock, from the Date on its answer. Only a real
    /// difference is kept: a second or two is the network, not the clock.
    private func learnTime(_ http: HTTPURLResponse) {
        guard let text = http.value(forHTTPHeaderField: "Date"), let then = clock.date(from: text) else { return }
        let off = Int(then.timeIntervalSince1970 - Date().timeIntervalSince1970)
        skew = abs(off) > 30 ? off : 0
    }

    // MARK: the keys

    /// ~/Library/Application Support/Kliner: the keys, and the name they hold.
    /// Not the Keychain: Kliner is signed again every time it is built, and
    /// the Keychain would ask about the keys each time.
    private static var keysFolder: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Kliner", isDirectory: true)
    }
    private static var identityFile: URL {
        return keysFolder.appendingPathComponent("identity.json")
    }
    /// Where a file coming here is put together until it is whole and checked.
    private static var incomingFolder: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("app.kliner.mac", isDirectory: true)
            .appendingPathComponent("incoming", isDirectory: true)
    }
    private static var downloads: URL {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// The keys this Mac already has, or new ones, written down before they
    /// are used so a name is never claimed with a key that was then lost.
    private func keys() -> Identity? {
        if identity == nil { identity = Cloud.load() }
        if let known = identity { return known }
        let made = Identity(sign: Curve25519.Signing.PrivateKey(), box: Curve25519.KeyAgreement.PrivateKey(),
                            user: "", at: 0)
        guard Cloud.save(made) else { return nil }
        identity = made
        return made
    }

    private static func load() -> Identity? {
        guard let data = try? Data(contentsOf: identityFile),
              let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let signText = object["sign"] as? String, let signRaw = Data(base64Encoded: signText),
              let boxText = object["box"] as? String, let boxRaw = Data(base64Encoded: boxText),
              let sign = try? Curve25519.Signing.PrivateKey(rawRepresentation: signRaw),
              let box = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: boxRaw) else { return nil }
        let name = object["user"] as? String ?? ""
        let at = (object["at"] as? NSNumber)?.intValue ?? 0
        return Identity(sign: sign, box: box, user: Cloud.valid(name) == nil ? name : "", at: at)
    }

    /// Written whole or not at all, readable by you alone: the folder 0700,
    /// the file 0600.
    @discardableResult
    private static func save(_ one: Identity) -> Bool {
        let object: [String: Any] = [
            "v": 1,
            "sign": one.sign.rawRepresentation.base64EncodedString(),
            "box": one.box.rawRepresentation.base64EncodedString(),
            "user": one.user,
            "at": one.at,
        ]
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: keysFolder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: keysFolder.path)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            try data.write(to: identityFile, options: [.atomic])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identityFile.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: small things

    /// Base64url without padding, the way kliner.app writes binary values.
    static func b64u(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unb64u(_ text: String) -> Data? {
        var plain = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rest = plain.utf8.count % 4
        if rest == 1 { return nil }
        if rest > 0 { plain += String(repeating: "=", count: 4 - rest) }
        return Data(base64Encoded: plain)
    }

    /// Small hex, the way kliner.app writes a fingerprint.
    static func hex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 2)
        for byte in data {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isHex(_ text: String) -> Bool {
        let digits = CharacterSet(charactersIn: "0123456789abcdef")
        return !text.unicodeScalars.contains(where: { !digits.contains($0) })
    }

    /// The nonce for piece `n`: four zero bytes, then `n` as eight, big end first.
    static func nonce(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        var value = UInt64(n)
        var at = 11
        while at >= 4 {
            bytes[at] = UInt8(truncatingIfNeeded: value)
            value >>= 8
            at -= 1
        }
        return Data(bytes)
    }

    /// How many pieces a file of `size` goes up in: one, even when it is empty.
    private static func pieces(_ size: Int64, chunk: Int) -> Int {
        let one = Int64(chunk)
        return Int(max(1, (size + one - 1) / one))
    }

    /// How big a file of `size` is once every piece of it is locked.
    private static func sealedSize(_ size: Int64, chunk: Int) -> Int64 {
        return size + Int64(pieces(size, chunk: chunk)) * Int64(Cloud.extra)
    }

    /// kliner.app's ids are short and plain; anything else is not one of them,
    /// and never goes into a path.
    private static func plainId(_ id: String) -> Bool {
        if id.isEmpty || id.utf8.count > 64 { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return !id.unicodeScalars.contains(where: { !allowed.contains($0) })
    }

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
}

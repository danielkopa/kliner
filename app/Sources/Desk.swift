//
//  Desk.swift — the icons on your desktop, and the key that takes them away.
//
//  \ is a key you press to see your desktop. It has to land at once, so this
//  is the one change Kliner makes itself instead of asking min to make it:
//  the same settings min writes, written straight, with no shell in between.
//  min still owns it from a terminal, and `min zen --restore` still puts the
//  icons back whether it was Kliner or min that took them away.
//
//  Two switches, not one. Desktop & Dock › Show Items has one for the plain
//  desktop and another for Stage Manager, and macOS reads whichever matches
//  the mode you are in. Kliner writes both. One on and the other off is how
//  this ends up looking broken: every press flips the one nobody is reading,
//  and the icons never move.
//
//  Should the Mac not take the switches, there is Finder's older way: Finder
//  stops drawing the desktop at all, and is started again. Slower, certain,
//  and only reached once the quick way has been seen not to work.
//

import AppKit

enum Desk {

    private static let managerDomain = "com.apple.WindowManager" as CFString
    private static let finderDomain = "com.apple.finder" as CFString

    /// Both switches macOS has for this, whichever mode the Mac is in.
    private static let switches = ["HideDesktop", "StandardHideDesktopIcons"]

    // MARK: reading

    /// Either spelling of yes, from a settings file that may hold a number,
    /// a string, or nothing at all.
    private static func yes(_ said: Any?) -> Bool? {
        if let number = said as? NSNumber { return number.boolValue }
        if let words = said as? String { return ["true", "yes", "1"].contains(words.lowercased()) }
        return nil
    }

    private static func read(_ key: String, _ domain: CFString) -> Bool? {
        CFPreferencesAppSynchronize(domain)
        return yes(CFPreferencesCopyValue(key as CFString, domain,
                                         kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    /// What the settings say: either switch on, or Finder told to stop
    /// drawing the desktop at all. Any one of the three reads as hidden.
    static func hiddenBySetting() -> Bool {
        for key in switches where read(key, managerDomain) == true { return true }
        return read("CreateDesktop", finderDomain) == false
    }

    /// Whether the icons are on screen right now: Finder's window at the
    /// desktop-icon level, there and not faded out. Three answers, not two —
    /// `nil` is the window list not being able to say, which is not the same
    /// as no icons and must never be read as one.
    static func onScreen() -> Bool? {
        guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.finder").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let pid = Int(app.processIdentifier)
        let its = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }
        // Finder is running and has windows; being shown none of them is the
        // list not answering, not an empty desktop.
        if its.isEmpty { return nil }
        let level = Int(CGWindowLevelForKey(.desktopIconWindow))
        return its.contains { window in
            (window[kCGWindowLayer as String] as? Int) == level
                && ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05
        }
    }

    /// Hidden or not, as the person sees it. The screen is the answer when it
    /// can give one, since that is what they are looking at; the settings are
    /// the answer when it cannot.
    static func hidden() -> Bool {
        if let seen = onScreen() { return !seen }
        return hiddenBySetting()
    }

    // MARK: changing

    private static func write(_ key: String, _ domain: CFString, _ value: Bool) {
        CFPreferencesSetValue(key as CFString, NSNumber(value: value), domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(domain)
    }

    /// The icons go, or come back. Both switches, at once: this is the whole
    /// of the quick way, and it takes about as long as the keypress did.
    static func set(_ hide: Bool) {
        for key in switches { write(key, managerDomain, hide) }
        // Coming back has one more thing to undo: if it was Finder that was
        // told to stop drawing the desktop, only a new Finder draws it again.
        if !hide, read("CreateDesktop", finderDomain) == false { finderWay(false) }
    }

    /// Finder's older way, for a Mac that did not take the switches: Finder
    /// stops drawing the desktop, or starts again, and is restarted either
    /// way, because that is the only thing that makes it look.
    static func finderWay(_ hide: Bool) {
        write("CreateDesktop", finderDomain, !hide)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

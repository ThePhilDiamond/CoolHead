import Foundation

/// Chrome's own memory limit, set as Chrome settings on this Mac (Phil, 15 November 2026: "Yes, with the warning").
///
/// Writes three of Chrome's documented policies to its preferences, as `defaults write com.google.Chrome` would:
/// TotalMemoryLimitMb (past it, Chrome unloads tabs you aren't using; they reload when clicked), and Memory Saver on,
/// at Maximum. Tested on Phil's Chrome 157 the same day: chrome://policy listed all three as Recommended, status OK,
/// and Chrome then said "Your browser is managed by your organization". The option says so before it's pressed.
///
/// Cool Head only removes what it set: its own settings keep the limit it wrote, and if Chrome already had any of
/// these settings (from the person, or an organization), the option isn't offered.
public enum ChromeLimit {
    public enum Status: Equatable {
        case available(Int)   // the limit it would set, in MB
        case set(Int)         // set by Cool Head, in MB
        case unavailable      // Chrome already has one of these settings: left alone
    }

    public static let chrome = "com.google.Chrome"
    static let keys = ["TotalMemoryLimitMb", "HighEfficiencyModeEnabled", "MemorySaverModeSavings"]
    public static let marker = "chromeLimitMB"

    /// Below what Chrome uses now (Phil, 15 November 2026: "Below current use"), so it frees memory as soon as Chrome
    /// applies it: a quarter of this Mac's memory or Chrome's use now, whichever is lower, in whole gigabytes rounded
    /// down, never below 2 GB (Chrome's own minimum is 1 GB).
    public static func limitMB(memory: UInt64 = ProcessInfo.processInfo.physicalMemory, chromeUse: UInt64? = nil) -> Int {
        let gib: UInt64 = 1_073_741_824
        let quarter = Int(memory / 4 / gib)
        let now = chromeUse.map { Int($0 / gib) } ?? quarter
        return max(2, min(quarter, now)) * 1024
    }

    public static func gb(_ mb: Int) -> String { "\(mb / 1024) GB" }

    static func value(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    /// `chromeUse`: Chrome's memory use now (all its processes), for the limit it would set.
    public static func status(domain: String = chrome, marker m: String = marker, memory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                              chromeUse: UInt64? = nil) -> Status {
        let mine = UserDefaults.standard.integer(forKey: m)
        if mine > 0, (value("TotalMemoryLimitMb", domain) as? Int) == mine { return .set(mine) }
        return keys.contains { value($0, domain) != nil } ? .unavailable : .available(limitMB(memory: memory, chromeUse: chromeUse))
    }

    /// Sets the limit the card showed, and Memory Saver at Maximum. Chrome picks them up within about 15 minutes, or
    /// when reopened.
    @discardableResult
    public static func set(_ mb: Int, domain: String = chrome, marker m: String = marker) -> Bool {
        guard mb >= 1024, case .available = status(domain: domain, marker: m) else { return false }
        let d = domain as CFString
        CFPreferencesSetAppValue("TotalMemoryLimitMb" as CFString, mb as CFNumber, d)
        CFPreferencesSetAppValue("HighEfficiencyModeEnabled" as CFString, kCFBooleanTrue, d)
        CFPreferencesSetAppValue("MemorySaverModeSavings" as CFString, 2 as CFNumber, d)     // 2: Maximum
        guard CFPreferencesAppSynchronize(d) else { return false }
        UserDefaults.standard.set(mb, forKey: m)
        return status(domain: domain, marker: m) == .set(mb)
    }

    /// Removes the three settings, only when Cool Head set them.
    @discardableResult
    public static func remove(domain: String = chrome, marker m: String = marker) -> Bool {
        guard case .set = status(domain: domain, marker: m) else { return false }
        let d = domain as CFString
        for k in keys { CFPreferencesSetAppValue(k as CFString, nil, d) }
        guard CFPreferencesAppSynchronize(d) else { return false }
        UserDefaults.standard.removeObject(forKey: m)
        return !keys.contains { value($0, domain) != nil }
    }

    /// The option for the memory card, for this status.
    public static func fix(_ s: Status) -> Fix? {
        switch s {
        case .available(let mb):
            return Fix(id: "chromelimit", title: "Limit Chrome to \(gb(mb))",
                       consequence: "Unused tabs unload, and reload when clicked. Chrome will say it's \u{201C}managed by your organization\u{201D}. Undo any time.",
                       kind: .chromeLimit(mb))
        case .set, .unavailable:
            // once it's on, removing it would make memory worse, so the card doesn't offer it (Phil, 15 November 2026);
            // it's restored from its line at the top of the panel
            return nil
        }
    }

    /// What the memory card says about a limit that's already on: whether Chrome is within it, and if not, why.
    public static func note(_ s: Status, using bytes: UInt64) -> String? {
        guard case .set(let mb) = s else { return nil }
        if bytes / 1_048_576 > UInt64(mb) {
            return "Chrome is over its \(gb(mb)) limit; it starts unloading tabs you aren't using within 15 minutes, or when it's reopened."
        }
        return "Chrome is within its \(gb(mb)) limit."
    }
}

/// Chrome's own setting to show each tab's memory when you point at the tab (Settings ▸ Appearance, "Show memory usage
/// on tab hover preview card"). Chrome knows which tab is which and Cool Head doesn't, so the memory card offers to
/// turn it on, and stops offering once it's on (Phil, 18 November 2026: "Can we see if that setting is enabled? It
/// would be annoying to get that card repeatedly after it's enabled").
///
/// Chrome keeps it in its Local State file as `browser.hovercard.memory_usage_enabled`
/// (chrome/common/pref_names.h). It was registered on (chrome/browser/ui/browser_ui_prefs.cc), and a later Chrome
/// switches it off once (chrome/browser/ui/tabs/tab_strip_prefs.cc), so on current Chrome it's off unless someone turned
/// it on; with no value written, it's an older Chrome where it's on. Only this one value is read from the file.
public enum ChromeHoverMemory {
    public static let localState = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Local State"
    nonisolated(unsafe) static var cached: (changed: Date, on: Bool?)?

    /// Whether the setting is on, from Local State's contents; nil when they aren't Chrome's JSON.
    public static func isOn(_ data: Data) -> Bool? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let hover = (json["browser"] as? [String: Any])?["hovercard"] as? [String: Any]
        return hover?["memory_usage_enabled"] as? Bool ?? true
    }

    /// This Mac's setting, read again only when Chrome has changed the file; nil when there's no Chrome to read.
    public static func read(path: String = localState) -> Bool? {
        guard let changed = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
        if let c = cached, c.changed == changed { return c.on }
        let on = FileManager.default.contents(atPath: path).flatMap(isOn)
        cached = (changed, on)
        return on
    }
}

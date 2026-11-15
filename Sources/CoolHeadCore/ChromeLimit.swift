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
            return "Chrome is over its \(gb(mb)) limit. Chrome applies a new limit within 15 minutes, or when you reopen it, and then unloads tabs you aren't using, never the one you're on."
        }
        return "Chrome is within its \(gb(mb)) limit."
    }
}

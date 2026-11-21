import Foundation

/// Chrome's memory limit as Cool Head 0.10 to 0.15 set it, which Cool Head now removes (Phil, 21 November 2026: "Do it
/// all", the Chrome plan's first stage).
///
/// Those versions wrote three of Chrome's documented policies to its preferences, as `defaults write com.google.Chrome`
/// would: TotalMemoryLimitMb, and Memory Saver on, at Maximum. Chrome reads values written that way as Recommended, and
/// its memory limit only runs when the policy is managed (chrome/browser/memory/enterprise_memory_limit_pref_observer.cc:
/// `if (pref->IsManaged())`), so on a Mac no organization manages it never unloaded a tab. Tested on Chrome for Testing
/// 158, 21 November 2026 (test T3 in the Chrome research): a 1 GB limit showed status OK while Chrome held 2.9 GB and
/// unloaded nothing. Meanwhile Chrome said "Your browser is managed by your organization" (T6). So it isn't offered any
/// more, and the watcher removes what Cool Head set, once per launch; settings someone else wrote are never touched.
public enum ChromeLimit {
    public enum Status: Equatable {
        case set(Int)   // set by Cool Head, in MB
        case notSet     // not Cool Head's, or not there
    }

    public static let chrome = "com.google.Chrome"
    static let keys = ["TotalMemoryLimitMb", "HighEfficiencyModeEnabled", "MemorySaverModeSavings"]
    public static let marker = "chromeLimitMB"

    public static func gb(_ mb: Int) -> String { "\(mb / 1024) GB" }

    static func value(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    /// Whether the limit Cool Head wrote is still there: its own record and Chrome's value agree.
    public static func status(domain: String = chrome, marker m: String = marker) -> Status {
        let mine = UserDefaults.standard.integer(forKey: m)
        return mine > 0 && (value("TotalMemoryLimitMb", domain) as? Int) == mine ? .set(mine) : .notSet
    }

    /// What Cool Head 0.10 to 0.15 wrote when Limit Chrome was pressed; kept only so the selftest can check removal on a
    /// scratch settings domain, never Chrome's.
    @discardableResult
    static func writeAsEarlierVersions(_ mb: Int, domain: String, marker m: String) -> Bool {
        let d = domain as CFString
        CFPreferencesSetAppValue("TotalMemoryLimitMb" as CFString, mb as CFNumber, d)
        CFPreferencesSetAppValue("HighEfficiencyModeEnabled" as CFString, kCFBooleanTrue, d)
        CFPreferencesSetAppValue("MemorySaverModeSavings" as CFString, 2 as CFNumber, d)     // 2: Maximum
        guard CFPreferencesAppSynchronize(d) else { return false }
        UserDefaults.standard.set(mb, forKey: m)
        return status(domain: domain, marker: m) == .set(mb)
    }

    /// Removes the three settings, only when Cool Head set them. Chrome drops the "managed" notice when it next reads its
    /// settings, within 15 minutes or when it's reopened.
    @discardableResult
    public static func remove(domain: String = chrome, marker m: String = marker) -> Bool {
        guard case .set = status(domain: domain, marker: m) else { return false }
        let d = domain as CFString
        for k in keys { CFPreferencesSetAppValue(k as CFString, nil, d) }
        guard CFPreferencesAppSynchronize(d) else { return false }
        UserDefaults.standard.removeObject(forKey: m)
        return !keys.contains { value($0, domain) != nil }
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

import Foundation

/// Chrome's memory limit as Cool Head 0.10 to 0.15 set it, which Cool Head now removes.
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
/// turn it on, and stops offering once it's on, so the offer doesn't keep coming back after it's done.
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

/// Chrome's Memory Saver, read from Chrome's Local State file, and set to Maximum there while Chrome is closed, as the
/// person's own setting. Chrome keeps it as
/// `performance_tuning.high_efficiency_mode.state` (0 off, 2 on) and `.aggressiveness` (0 Moderate, 1 Balanced, 2
/// Maximum) (components/performance_manager/public/user_tuning/prefs.h). Written that way it is the person's own choice:
/// no "managed by your organization", and they can change it in Chrome's Performance settings. Tested on Google Chrome
/// 158 in a separate test profile, 21 November 2026: it took, survived two relaunches, replaced an earlier Moderate, and
/// nothing else holds a copy or checksum of the two values. Maximum unloads a tab hidden for 2 hours and keeps tabs
/// revisited often; it doesn't help a Chrome that's dragging right now, so it's offered only under `shouldOffer`.
public enum ChromeMemorySaver {
    public struct State: Equatable {
        public let on: Bool
        public let level: Int       // 0 Moderate, 1 Balanced, 2 Maximum
        public var atMaximum: Bool { on && level == 2 }
        public init(on: Bool, level: Int) { self.on = on; self.level = level }
    }

    /// From Local State's contents; nil when they aren't Chrome's JSON. Missing values read as off.
    public static func state(_ data: Data) -> State? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let mode = (json["performance_tuning"] as? [String: Any])?["high_efficiency_mode"] as? [String: Any]
        return State(on: (mode?["state"] as? Int ?? 0) != 0, level: mode?["aggressiveness"] as? Int ?? 0)
    }

    public static func read(path: String = ChromeHoverMemory.localState) -> State? {
        FileManager.default.contents(atPath: path).flatMap(state)
    }

    /// When Cool Head last set it, so a person who lowered it again isn't asked for 30 days.
    public static let setKey = "memorySaverSetByCoolHead"

    /// Offered when Chrome is using a lot of memory and it isn't at Maximum, and any of: this Mac has 8 GB of memory or
    /// less (pressure arrives sooner there); memory has slowed the Mac at least twice this week; or once, and Memory Saver
    /// is off (research synthesis, "When Cool Head recommends Memory Saver at Maximum"). Not within 30 days of Cool Head
    /// setting it, if the person has since lowered it: that was their choice.
    public static func shouldOffer(_ s: State?, week: PressureHistory.Week?, memoryGB: Double, setAt: Date?, now: Date) -> Bool {
        if s?.atMaximum == true { return false }
        if let t = setAt, now.timeIntervalSince(t) < 30 * 24 * 3600 { return false }
        let count = week?.count ?? 0
        return memoryGB <= 8.5 || count >= 2 || (count >= 1 && s?.on != true)
    }

    public enum Write: Equatable { case set, chromeOpen, unreadable, failed(String) }

    /// Sets Maximum in Local State. Only while Chrome is closed (its SingletonLock gone, or left by a process that has
    /// ended on this Mac); only the two values change, checked by reading the result back; the file keeps its mode (600),
    /// and is replaced in one step, so Chrome never sees half a file.
    public static func setMaximum(path: String = ChromeHoverMemory.localState) -> Write {
        let dir = (path as NSString).deletingLastPathComponent
        if profileInUse(dir) { return .chromeOpen }
        guard let data = FileManager.default.contents(atPath: path),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        var tuning = json["performance_tuning"] as? [String: Any] ?? [:]
        var mode = tuning["high_efficiency_mode"] as? [String: Any] ?? [:]
        mode["state"] = 2; mode["aggressiveness"] = 2
        tuning["high_efficiency_mode"] = mode; json["performance_tuning"] = tuning
        guard let out = try? JSONSerialization.data(withJSONObject: json),
              let back = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any],
              (back as NSDictionary).isEqual(to: json) else { return .failed("its settings file couldn't be written exactly") }
        let mode600 = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber ?? 0o600
        let temp = dir + "/.Local State.coolhead-\(UUID().uuidString)"
        guard FileManager.default.createFile(atPath: temp, contents: out, attributes: [.posixPermissions: mode600]) else { return .failed("couldn't write next to its settings file") }
        guard rename(temp, path) == 0 else { try? FileManager.default.removeItem(atPath: temp); return .failed("couldn't replace its settings file") }
        return read(path: path)?.atMaximum == true ? .set : .failed("the new setting didn't read back")
    }

    /// Whether a Chrome is using this data folder: its SingletonLock names `<host>-<pid>`. A lock left by a process that
    /// has ended on this Mac is stale (a quit by signal leaves it); a lock from another host, or a live process, isn't.
    static func profileInUse(_ dir: String) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: dir + "/SingletonLock") else { return false }
        guard let dash = target.lastIndex(of: "-"), let pid = pid_t(target[target.index(after: dash)...]) else { return true }
        let host = String(target[..<dash])
        var buf = [CChar](repeating: 0, count: 256)
        let here = gethostname(&buf, buf.count) == 0 ? String(cString: buf) : ""
        let sameHost = host == here || here.hasPrefix(host + ".") || host.hasPrefix(here + ".")
        return !sameHost || Proc.bsd(pid) != nil
    }
}

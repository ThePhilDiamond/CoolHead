import Foundation

/// A job Cool Head froze to save battery ("Pause until you plug in"). It is resumed when the Mac is plugged in, when
/// the person asks, when Cool Head quits, and when Cool Head next starts, so nothing is ever left frozen.
public struct PausedJob: Codable, Identifiable {
    public var id: String { key }
    public let key: String
    public let pid: Int32
    public let start: Double?            // the process's start time, to be sure it's still the same process
    public let name: String
    public let reportSubject: String
    public let since: Date
}

/// A reminder to resume a sync app the person paused (Phil, 15 November 2026: "pausing sync should be temporary and
/// we should make sure to write to a reminder file somewhere to resume it later"). Cool Head can't pause or resume
/// the app itself; it opens it and reminds.
public struct SyncPause: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let bundle: String
    public let until: Date
    public var reminded = false
}

/// The paused jobs and sync reminders, saved on this Mac with Cool Head's settings so a restart or an update doesn't
/// lose them. Nothing else is kept.
enum PauseStore {
    static func load<T: Decodable>(_ key: String) -> [T] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: d)) ?? []
    }
    static func save<T: Encodable>(_ items: [T], _ key: String) {
        if items.isEmpty { UserDefaults.standard.removeObject(forKey: key); return }
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }
}

/// "Save Battery When Unplugged" (Phil, 15 November 2026: "Battery aware could be a toggle"): on by default. When on
/// and the Mac is on battery, a heavy job is flagged even when the Mac is cool, with Pause until you plug in.
public enum BatteryMode {
    public static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "saveBatteryUnplugged") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveBatteryUnplugged") }
    }
}

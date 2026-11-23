import Foundation

/// "Every time" for Run it cooler: apps and jobs the person chose to run cooler whenever they run, listed under Always
/// cooler in the Trusted tool. An app is slowed while it isn't the app in front, a few seconds after you switch away from
/// it, and is back to full speed the moment you switch to it, so the app you're using is never slowed; a job with no
/// windows is slowed whenever it runs. Only your own processes: macOS doesn't let Cool Head change anyone else's.
///
/// Kept on this Mac only, like Trust: the key (`Trust.key`) and the name to show. Nothing about what happened.
/// Trusting something and always slowing it are opposites, so adding one removes the other.
public enum CoolerRules {
    static let defaultsKey = "alwaysCooler"
    /// How long after you switch away from an app before it's slowed, so a download or a copy to the clipboard settles
    /// first.
    public static let settle: TimeInterval = 5

    /// Rules: key → the name to show.
    public static var all: [String: String] {
        Trust.defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
    public static func contains(_ key: String?) -> Bool { key.map { all[$0] != nil } ?? false }

    /// A CPU limit a rule carries (CPUCap.Level), by rule key; kept on this Mac like the rules. Only the level is kept:
    /// what "half speed" means is measured fresh each time the app starts.
    static let levelsKey = "alwaysCoolerLimit"
    public static var levels: [String: CPUCap.Level] {
        (Trust.defaults.dictionary(forKey: levelsKey) as? [String: String] ?? [:]).compactMapValues(CPUCap.Level.init(rawValue:))
    }
    public static func setLevel(_ key: String, _ level: CPUCap.Level?) {
        var d = Trust.defaults.dictionary(forKey: levelsKey) as? [String: String] ?? [:]
        d[key] = level?.rawValue
        Trust.defaults.set(d, forKey: levelsKey)
    }

    /// Adds a rule, and stops trusting it.
    public static func add(_ key: String, name: String) {
        var d = all; d[key] = name; Trust.defaults.set(d, forKey: defaultsKey)
        Trust.forget(key)
    }
    public static func remove(_ key: String) { forget(key) }
    /// Removes a rule without touching the trusted list (what Trust.add uses).
    static func forget(_ key: String) {
        var d = all
        guard d.removeValue(forKey: key) != nil else { return }
        Trust.defaults.set(d, forKey: defaultsKey)
    }

    /// An app's rule follows which app is in front; anything else's applies whenever it runs.
    public static func isApp(_ key: String) -> Bool { key.hasPrefix("app:") }

    /// Whether something under a rule should run cooler now. An app: not while it's in front, nor in the first few
    /// seconds after you switch away from it. Anything else: always.
    public static func slowNow(key: String, frontKey: String?, leftFrontAt: Date?, now: Date) -> Bool {
        guard isApp(key) else { return true }
        if frontKey == key { return false }
        if let t = leftFrontAt, now.timeIntervalSince(t) < settle { return false }
        return true
    }

    /// What a card says about something that already has a rule, in place of offering Run it cooler again.
    public static func cardLine(app: Bool) -> String {
        app ? "It already runs cooler every time you switch away from it, as you chose."
            : "It already runs cooler every time it runs, as you chose."
    }
}

extension Card {
    /// This card for something that already has a rule: it says so, and doesn't offer Run it cooler again.
    public func underRule(app: Bool) -> Card {
        var c = Card(state: state, headline: headline, explanation: explanation + " " + CoolerRules.cardLine(app: app),
                     fixes: fixes.filter { $0.kind != .cooler })
        c.names = names; c.facts = facts; c.cardID = cardID; c.choice = choice; c.diagnosis = diagnosis
        c.optionFacts = optionFacts.filter { $0.key != "cooler" }
        return c
    }
}

import Foundation

/// Checks for the crash-loop card (see CrashLoops.swift): crash reports' headers read right, only app crashes count, a
/// loop needs 5 crashes of one app in 24 hours, macOS's own apps aren't counted, and the card leaves the action to its
/// options. The live read prints counts only, never an app's name.
extension Fixture {
    static func crashHeader(_ app: String, bundle: String, _ time: Date, type: String = "309", fraction: Bool = true) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fraction ? "yyyy-MM-dd HH:mm:ss.SS Z" : "yyyy-MM-dd HH:mm:ss Z"
        return #"{"app_name":"\#(app)","timestamp":"\#(f.string(from: time))","app_version":"9.1","bug_type":"\#(type)","os_version":"macOS 26.6.2 (25G212)","bundleID":"\#(bundle)","is_first_party":0,"name":"\#(app)","incident_id":"0F1E2D3C"}"#
    }

    /// `n` crashes of a made-up app, one every `every` seconds, the latest `ago` seconds before `now`.
    static func crashes(_ app: String, bundle: String, _ n: Int, every: TimeInterval, ago: TimeInterval = 600, now: Date) -> [CrashLoops.Crash] {
        (0..<n).map { CrashLoops.Crash(app: app, bundle: bundle, time: now.addingTimeInterval(-ago - Double($0) * every)) }
    }

    static func crashLoopChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let t = now.addingTimeInterval(-3600)

        // the header: app crashes only, with or without hundredths of a second
        let a = CrashLoops.parseHeader(crashHeader("Backblaze", bundle: "com.backblaze.bzbmenu", t))
        let b = CrashLoops.parseHeader(crashHeader("Backblaze", bundle: "com.backblaze.bzbmenu", t, fraction: false))
        let hang = CrashLoops.parseHeader(crashHeader("Backblaze", bundle: "com.backblaze.bzbmenu", t, type: "288"))
        let r1 = a?.app == "Backblaze" && a?.bundle == "com.backblaze.bzbmenu" && abs((a?.time ?? .distantPast).timeIntervalSince(t)) < 1
            && b != nil && hang == nil && CrashLoops.parseHeader("not a header") == nil
        review.append(("crash-reads", r1, "app crash \(a.map { "\($0.app) \($0.bundle ?? "")" } ?? "none"); without hundredths \(b != nil); hang report counted \(hang != nil)"))

        // a loop: 5 in 24 hours, not 4; older ones don't count; macOS's own apps aren't counted
        let five = crashes("Backblaze", bundle: "com.backblaze.bzbmenu", 5, every: 3600, now: now)
        let four = crashes("Backblaze", bundle: "com.backblaze.bzbmenu", 4, every: 3600, now: now)
        let old = crashes("Backblaze", bundle: "com.backblaze.bzbmenu", 3, every: 3600, ago: 30 * 3600, now: now)
        let apple = crashes("Music", bundle: "com.apple.Music", 9, every: 600, now: now)
        let other = crashes("Docker", bundle: "com.docker.docker", 12, every: 600, now: now)
        let loops = CrashLoops.loops(five + apple + other, now: now)
        let l1 = loops.map(\.app) == ["Docker", "Backblaze"] && loops.last?.count == 5
            && CrashLoops.loops(four + old, now: now).isEmpty && CrashLoops.loops(apple, now: now).isEmpty
        review.append(("crash-loop-threshold", l1, loops.map { "\($0.app) \($0.count)" }.joined(separator: ", ")))

        // the card: count and time in the headline, needs a look, Look it up recommended, Console second
        let cards = CrashLoops.cards(CrashLoops.loops(five, now: now))
        let c = cards.first
        let c1 = cards.count == 1 && c?.card.headline.hasPrefix("Backblaze crashed 5 times since ") == true && c?.needsLook == true
            && c?.card.recommended?.id == "lookup" && c?.card.fixes.map(\.id) == ["lookup", "console"]
            && c?.card.fixes.allSatisfy { !$0.caution } == true && c?.displaySubject == "Backblaze"
        review.append(("crash-loop-card", c1, c.map { $0.card.headline + " " + $0.card.explanation } ?? "none"))

        // the text gives the verdict and the evidence; the options carry the action
        let w1 = cards.allSatisfy { c in c.card.fixes.allSatisfy { !(c.card.headline + " " + c.card.explanation).contains($0.title) } }
        review.append(("crash-loop-wording", w1, "\(cards.count) card: no option title in the text"))

        // this Mac, quickly; counts only
        let start = Date()
        let (live, system) = CrashLoops.read()
        let took = Date().timeIntervalSince(start)
        review.append(("crash-live-read", took < 1, String(format: "%.2f s; %d app crashes in the last day; system folder readable: %@; apps in a loop: %d",
                                                          took, live.count, system ? "yes" : "no", CrashLoops.loops(live, now: Date()).count)))
        return review
    }

    /// For `coolhead wording` and screenshots: a made-up app that crashed 40 times since early yesterday evening.
    static func crashLoopSamples(_ now: Date) -> [(String, Card)] {
        CrashLoops.cards(CrashLoops.loops(crashes("Backblaze", bundle: "com.backblaze.bzbmenu", 40, every: 1800, ago: 900, now: now), now: now))
            .map { ("crash-loop", $0.card) }
    }
}

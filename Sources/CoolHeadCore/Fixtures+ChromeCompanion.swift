import Foundation

/// Checks for Chrome's card with Cool Head for Chrome (see ChromeCompanion): one click when it's connected, offered when
/// it isn't and memory keeps slowing the Mac.
extension Fixture {
    static func companionCard(_ now: Date, _ status: ChromeCompanion.Status, weekCount: Int = 3) -> Card {
        MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                          context: MemoryContext(slowed: true, week: PressureHistory.Week(count: weekCount, minutes: 40, chromeCount: 2),
                                                 chrome: chromeParts(now, extGB: 1.6), companion: status), tabMemoryOn: false)
    }

    static func chromeCompanionChecks(_ now: Date) -> [(String, Bool, String)] {
        let on = companionCard(now, .connected)
        let ids = on.fixes.map(\.id)
        let offered = companionCard(now, .notInstalled).fixes.contains { $0.id == "companion" }
        let notYet = !companionCard(now, .notInstalled, weekCount: 1).fixes.contains { $0.id == "companion" }
        let noChrome = !companionCard(now, .noChrome).fixes.contains { $0.id == "companion" }
        return [("companion-one-click", on.recommended?.id == "sleep" && on.recommended?.consequence.hasPrefix("Frees about 2.1 GB.") == true
                 && !ids.contains("tabs") && ids.contains("duplicates") && on.fixes.first { $0.id == "extensions" }.map { if case .chromeCompanion = $0.kind { return true } else { return false } } == true
                 && offered && notYet && noChrome, ids.joined(separator: " ") + "; offered \(offered), not after once \(notYet), not without Chrome \(noChrome)")]
    }

    static func chromeCompanionSamples(_ now: Date) -> [(String, Card)] {
        [("memory-chrome-companion", companionCard(now, .connected)), ("memory-chrome-get-companion", companionCard(now, .notInstalled))]
    }
}

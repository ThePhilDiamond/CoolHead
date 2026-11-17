import Foundation

/// The golden ranking (see Ranking.swift): every sample card's winner and options match GoldenRanking.swift, and no
/// two samples share an ID.
extension Fixture {
    static func rankingChecks(_ now: Date) -> [(String, Bool, String)] {
        let lines = Ranking.lines(now: now)
        let (removed, added) = Ranking.differences(now: now)
        let ids = lines.map { $0.components(separatedBy: " · ")[0] }
        let repeated = Set(ids.filter { id in ids.filter { $0 == id }.count > 1 }).sorted()
        let note = removed.isEmpty && added.isEmpty
            ? "\(lines.count) samples, as recorded"
            : "recorded: \(removed.prefix(3).joined(separator: " | ")); now: \(added.prefix(3).joined(separator: " | "))"
                + " (\(removed.count) changed; if intended, run `coolhead ranking --write` and commit GoldenRanking.swift)"
        return [("golden-ranking", removed.isEmpty && added.isEmpty, note),
                ("sample-ids-unique", repeated.isEmpty, repeated.isEmpty ? "\(ids.count) IDs" : "repeated: \(repeated.joined(separator: ", "))")]
    }

    /// No sample cards of its own for `coolhead wording`.
    static func rankingSamples(_ now: Date) -> [(String, Card)] { [] }
}

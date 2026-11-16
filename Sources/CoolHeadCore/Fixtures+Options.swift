import Foundation

/// Checks for how options are grouped and labelled (see `Fix.doer`, `Fix.caution`, `Card.betterThanRecommended`). Runs
/// over every example card, the same list `coolhead wording` prints.
extension Fixture {
    static func optionChecks(_ now: Date) -> [(String, Bool, String)] {
        let samples = Wording.samples(now: now)
        var bad: [String] = []
        for (id, c) in samples {
            for f in c.fixes {
                // one corner label at most: Caution is for what Cool Head does, Fixes the cause for your tasks
                if f.caution && f.doer == .you { bad.append("\(id): \(f.title) is a task for you labelled Caution") }
                if f.caution && c.betterThanRecommended.contains(where: { $0.id == f.id }) { bad.append("\(id): \(f.title) would get both labels") }
            }
            if c.fixes.filter(\.recommended).count > 1 { bad.append("\(id): more than one recommendation") }
            // one click first: a task is recommended only when no one-click option eases it without interrupting
            if let r = c.recommended, r.doer == .you,
               let alt = c.fixes.first(where: { $0.doer == .coolHead && !$0.caution && !$0.holdBack && $0.result >= .eases }) {
                bad.append("\(id): recommends the task \(r.title) over \(alt.title)")
            }
        }
        let caution = samples.filter { $0.1.fixes.contains(where: \.caution) }.count
        let better = samples.filter { !$0.1.betterThanRecommended.isEmpty }.count
        let recs = samples.compactMap(\.1.recommended)
        let labelled = "\(caution) with a Caution option, \(better) with a task that fixes the cause; recommendations: \(recs.count), "
            + "\(recs.filter { $0.doer == .coolHead && !$0.caution }.count) one click and safe, \(recs.filter(\.caution).count) Caution, \(recs.filter { $0.doer == .you }.count) tasks"
        return [("option-labels", bad.isEmpty,
                 bad.isEmpty ? "\(samples.count) example cards: at most one corner label per option, one click first; \(labelled)" : bad.joined(separator: "; "))]
    }
}

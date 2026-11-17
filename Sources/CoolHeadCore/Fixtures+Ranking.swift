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
        // every sample's explanation, as recorded
        let explained = Ranking.explanationLines(now: now), gold = Ranking.goldenExplanations
        let lost = gold.filter { !explained.contains($0) }, new = explained.filter { !gold.contains($0) }
        let explainedNote = lost.isEmpty && new.isEmpty ? "\(explained.count) explanations, as recorded"
            : "recorded: \(lost.prefix(2).joined(separator: " | ")); now: \(new.prefix(2).joined(separator: " | ")) (\(max(lost.count, new.count)) changed; if intended, run `coolhead ranking --write`)"
        var review = [("golden-ranking", removed.isEmpty && added.isEmpty, note),
                      ("golden-explanations", lost.isEmpty && new.isEmpty, explainedNote),
                      ("sample-ids-unique", repeated.isEmpty, repeated.isEmpty ? "\(ids.count) IDs" : "repeated: \(repeated.joined(separator: ", "))")]

        // every card has an ID of its own and at least one sample, and wins each sample it lists
        let winners = Dictionary(lines.map { l -> (String, String) in let p = l.components(separatedBy: " · "); return (p[0], p[1]) },
                                 uniquingKeysWith: { a, _ in a })
        let cardIDs = ProcessCards.all.map { $0.id } + ProcessCards.extras.map { $0.id }
        let wrong = ProcessCards.all.flatMap { t in t.samples.filter { winners[$0] != t.id }.map { "\(t.id) doesn't win \($0) (\(winners[$0] ?? "no such sample"))" } }
        let bare = ProcessCards.all.filter { $0.samples.isEmpty }.map { $0.id }
        review.append(("card-samples", wrong.isEmpty && bare.isEmpty && Set(cardIDs).count == cardIDs.count,
                       wrong.isEmpty && bare.isEmpty ? "\(ProcessCards.all.count) cards and \(ProcessCards.extras.count) extras, each card winning its \(ProcessCards.all.map { $0.samples.count }.reduce(0, +)) samples"
                                                     : (wrong + bare.map { "\($0) lists no sample" }).joined(separator: "; ")))

        // no two cards tie, on any sample or made-up overlap, each varied in warmth, battery, a game and the front app
        var seen: [Situation] = []
        Card.observer = { seen.append($0) }
        _ = Wording.samples(now: now)
        Card.observer = nil
        var sampleTies: [String] = [], missing: [String] = []
        for s in seen { for warm in [false, true] { for battery in [nil, 30] as [Int?] { for game in [nil, "Lumen"] as [String?] {
            for front in [nil, s.e.appBundle] as [String?] {
                let v = Situation(s.e, now: s.now, busySince: s.busySince, warm: warm, gameRunning: game, frontApp: front, battery: battery,
                                  syncFeed: s.syncFeed, agent: s.agent, backupFeed: s.backupFeed, disguise: s.disguise, background: s.background, apps: s.apps)
                let (card, c) = Ranker.choose(v)
                for m in Decision.missing(card, id: c.winner) where !missing.contains(m) { missing.append(m) }
                let t = "\(s.e.name): \(c.winner) or \(c.ties.joined(separator: ", "))"
                if !c.ties.isEmpty, !sampleTies.contains(t) { sampleTies.append(t) }
            }
        } } } }
        let overlaps = overlaps(now: now).map { want, s in (want, s, Ranker.choose(s).1) }
        let overlapTies = overlaps.filter { !$0.2.ties.isEmpty }.map { "\($0.1.e.name): \($0.2.winner) or \($0.2.ties.joined(separator: ", "))" }
        review.append(("ranking-no-ties", sampleTies.isEmpty && overlapTies.isEmpty,
                       sampleTies.isEmpty && overlapTies.isEmpty ? "\(seen.count) sample situations, each varied 16 ways, and \(overlaps.count) overlaps" : "tied: " + (sampleTies + overlapTies).joined(separator: "; ")))
        // the decision record: every recommended option and every stronger one held back has its facts, written by hand
        review.append(("decision-facts-complete", missing.isEmpty, missing.isEmpty ? "every card and option the samples reach, varied 16 ways" : missing.joined(separator: "; ")))
        let missed = overlaps.filter { $0.0 != $0.2.winner }.map { "\($0.1.e.name) got \($0.2.winner), not \($0.0)" }
        review.append(("ranking-overlaps", missed.isEmpty,
                       missed.isEmpty ? overlaps.map { "\($0.1.e.name): \($0.2.winner) of \($0.2.matched.count)" }.joined(separator: "; ") : missed.joined(separator: "; ")))
        return review
    }

    /// Made-up processes that two or more cards match, beyond what the samples cover: the card each must get.
    public static func overlaps(now: Date = Date()) -> [(String, Situation)] {
        let start = now.addingTimeInterval(-7200)
        func probe(_ name: String, _ path: String, _ args: [String] = [], by: String? = nil) -> Situation {
            var e = Evidence.sample(name: name, path: path, args: args, start: start, cores: 1.5)
            e.servedBy = by
            return Situation(e, now: now, busySince: now.addingTimeInterval(-3600))
        }
        let steam = "/Users/x/Library/Application Support/Steam/steamapps/common/Lumen/Lumen.app"
        func helper(_ app: String, _ kind: String) -> String { "\(app)/Contents/Frameworks/\(kind).app/Contents/MacOS/\(kind)" }
        let webkit = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
        return [
            ("sync-app", probe("Dropbox Helper (Renderer)", helper("/Applications/Dropbox.app", "Dropbox Helper (Renderer)"), ["--type=renderer"])),
            ("game", probe("Lumen Helper (Renderer)", helper(steam, "Lumen Helper (Renderer)"), ["--type=renderer"])),
            ("game", probe("Lumen Helper (GPU)", helper(steam, "Lumen Helper (GPU)"), ["--type=gpu-process"])),
            ("game", probe("Lumen", steam + "/Contents/MacOS/Lumen")),
            // can't happen today (macOS names the app only for its XPC services, and no catalogue entry is one): if one
            // were added, the served card would win, since it also knows which app the work is for
            ("served", probe("mds_stores", "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mds_stores", by: "/Applications/Google Drive.app")),
            ("security-software", probe("Netskope Helper (Renderer)", helper("/Applications/Netskope Client.app", "Netskope Helper (Renderer)"), ["--type=renderer"])),
            ("web-page", probe("com.apple.WebKit.WebContent", webkit + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", by: "/Applications/Safari.app")),
            ("web-page-in-app", probe("com.apple.WebKit.GPU", webkit + "com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU", by: "/System/Applications/Mail.app")),
        ]
    }

    /// No sample cards of its own for `coolhead wording`.
    static func rankingSamples(_ now: Date) -> [(String, Card)] { [] }
}

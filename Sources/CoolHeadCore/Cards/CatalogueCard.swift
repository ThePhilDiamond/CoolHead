import Foundation

/// One of macOS's own processes that the catalogue knows (Catalogue.swift): what it is doing, and whether this has
/// gone on longer than usual.
enum CatalogueCard: ProcessCard {
    static let name = "a program we know by name"
    static let id = "catalogue"
    static let kind = CardKind.explanation
    static let rule = "Catalogue.swift: macOS's own processes, what each does and how long it usually takes"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this program and what usually helps it") }
    static let samples = ["spotlight-normal", "spotlight-long", "kernel-task-long", "docker-vm", "windowserver-old-electron", "time-machine-build"]

    static func card(_ s: Situation) -> Card? {
        let e = s.e
        guard let k = Pattern.match(name: e.name, path: e.path, pid: e.pid), e.progress == nil else { return nil }
        // after a macOS update, indexing and analysis are expected for hours to days (see BackgroundWork)
        let updated = k.afterUpdate ? s.background?.update : nil
        let long = updated == nil && s.busyFor > k.usualHours * 3600 && s.busyFor >= 20 * 60
        // its busy threads at background priority: on the efficiency cores, little power whatever % CPU says
        let cool = s.active && s.background?.cool == true
            ? " It's running at low priority, on the chip's efficiency cores, so it uses little power even though it looks busy." : ""
        // Time Machine copying a build's output: the build folder is the cause to fix (see BackupExclusions)
        let feed = k.id == "time-machine" && s.active ? s.backupFeed : nil
        let explanation = (long
            ? "It usually takes under \(Fmt.duration(k.usualHours * 3600))."
            : updated.map { "You updated to macOS \($0.version) \(BackgroundWork.ago($0.date, now: s.now)); this usually goes on for hours or days after an update." }
                ?? k.usually + (k.endsOnItsOwn ? " It stops on its own." : "")) + cool + Fmt.its([s.gpuClause])
            + (feed.map { " " + $0.sentence() } ?? "")
        var fixes: [Fix] = feed.map { [$0.fix(recommended: true)] } ?? []
        if long {
            if k.whenLong == "Look it up" { fixes.append(Card.lookUp(e.name, recommended: true)) }
            else {
                // what the catalogue advises, as a button: open the app it's about, or Activity Monitor to find the heat
                if k.whenLong.hasPrefix("Find what is heating") {
                    fixes.append(Fix.openApp("advice", k.whenLong, bundle: Fix.activityMonitor, steps: "Click % CPU to put the busiest first.", recommended: true))
                } else if let b = e.appBundle {
                    fixes.append(Fix.openApp("advice", k.whenLong, bundle: b, steps: k.risk ?? "", recommended: true))
                } else {
                    fixes.append(Fix.guide("advice", k.whenLong, k.risk ?? "", steps: [k.whenLong + ".", k.risk].compactMap { $0 }, recommended: true))
                }
                fixes.append(Card.lookUp(e.name, recommended: false))
            }
            fixes.append(Card.wait(until: nil, now: s.now, recommended: false))
            fixes.append(Card.share)
        } else {
            fixes.append(Card.wait(until: nil, now: s.now, recommended: true))
        }
        if let bundle = e.quittableBundle, let app = e.quittableApp, k.risk != nil, k.whenLong.hasPrefix("Quit") {
            fixes.append(Fix(id: "quit", title: "Quit \(app)", consequence: k.risk!, kind: .quitApp(bundle)).losingWork())
        }
        let head = !s.active ? "\(k.doing). It's quiet now."
            : long ? "\(k.doing). It's been \(Fmt.duration(s.busyFor)), longer than usual."
            : updated != nil ? "\(k.doing). That's normal after an update."
            : "\(k.doing). That's normal."
        // a statement, not an option: macOS restarts its own programs
        return Card(state: !s.active ? .quiet : long ? .unknown : .working, headline: head,
                    explanation: explanation + (e.mine ? "" : " macOS needs it, so stopping it would only start it again."), fixes: fixes)
    }
}

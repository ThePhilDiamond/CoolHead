import Foundation

/// Sync apps (Protected.swift): catching up is normal, and pausing loses nothing; slowing or quitting come after.
enum SyncAppCard: ProcessCard {
    static let name = "a sync app"
    static let id = "sync-app"
    static let kind = CardKind.explanation
    static let rule = "Sync apps catch up and stop; a build writing into a synced folder is the cause (seen with Google Drive errors)"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this sync app") }
    static let samples = ["sync-app", "sync-app-warm-fed-by-a-build", "sync-app-fed-in-its-folder"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if let sync = SyncApps.app(bundle: s.e.appBundle) {
            var signs = [s.syncFeed.map { "is uploading the files \($0.who) keeps writing into a folder it syncs" } ?? "is catching up on your changes"]
            if s.warm && s.e.coresNow >= 0.5 { signs.append("is adding to the heat") }
            if let g = s.gameRunning { signs.append("is competing with \(g)") }
            if s.onBattery { signs.append("is using your battery") }
            c.diagnosis = Diagnosis(saw: "\(sync) " + Decision.list(signs))
            c.optionFacts["cooler"] = OptionFacts(helps: "slows its syncing, so it uses less power and makes less heat", undo: .anyTime)
            c.optionFacts["pause"] = OptionFacts(helps: "stops the load until you resume; we'll remind you", cost: "your changes wait until then")
            c.optionFacts["quit"] = OptionFacts(helps: "ends the load completely", cost: "nothing syncs until you open \(sync) again")
            if let feed = s.syncFeed {
                c.optionFacts["movebuild"] = OptionFacts(helps: "stops the extra uploads for good, since \(sync) no longer sees \(feed.who)'s files")
            }
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let sync = SyncApps.app(bundle: e.appBundle), let bundle = e.appBundle else { return nil }
        if e.coresNow < 0.25 { return Card(state: .quiet, CardTemplate(sync, .quiet, nil), fixes: []) }
        // a build or job writing lots of files into a folder it syncs is the cause to fix, ahead of pausing
        return Card(state: .working,
                    CardTemplate(sync, .words("is syncing your files"), .normal,
                                 evidence: ["It uploads and checks every change, and stops when it is done."] + (s.syncFeed.map { [$0.sentence(sync)] } ?? []),
                                 effect: [CardTemplate.it([s.warm && e.coresNow >= 0.5 ? "adds heat" : nil])].compactMap { $0 }),
                    fixes: [s.syncFeed?.fix(sync, recommended: true),
                            Fix(id: "pause", title: "Pause syncing", consequence: "This opens \(sync) so you can pause it, and Cool Head reminds you to start it again. Changes wait until then.",
                                kind: .pauseSync(bundle, sync), recommended: s.warm || s.gameRunning != nil
                                    || (s.onBattery && (e.coresNow >= 2 || ((s.battery ?? 100) < 50 && e.coresNow >= 1)))),
                            RunCooler.offered(e) ? Fix(id: "cooler", title: "Run it cooler", consequence: CardTemplate.says("This slows its syncing.", undo: true), kind: .cooler) : nil,
                            Fix(id: "quit", title: "Quit \(sync)", consequence: "This stops syncing until you open it again.", kind: .quitApp(bundle))].compactMap { $0 })
    }
}

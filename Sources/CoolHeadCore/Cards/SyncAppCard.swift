import Foundation

/// Sync apps (Protected.swift): catching up is normal, and pausing loses nothing; slowing or quitting come after.
enum SyncAppCard: ProcessCard {
    static let id = "sync-app"
    static let kind = CardKind.explanation
    static let rule = "Sync apps catch up and stop; a build writing into a synced folder is the cause (Phil's Google Drive errors, 15 November 2026)"
    static let match = Match.bundle
    static let samples = ["sync-app", "sync-app-warm-fed-by-a-build", "sync-app-fed-in-its-folder"]

    static func card(_ s: Situation) -> Card? {
        let e = s.e
        guard let sync = SyncApps.app(bundle: e.appBundle), let bundle = e.appBundle else { return nil }
        if e.coresNow < 0.25 { return Card(state: .quiet, headline: "\(sync) is quiet now.", explanation: "", fixes: []) }
        // a build or job writing lots of files into a folder it syncs is the cause to fix, ahead of pausing
        return Card(state: .working, headline: "\(sync) is syncing your files.",
                    explanation: "It uploads and checks every change, and stops when it's caught up."
                        + (s.syncFeed.map { " " + $0.sentence(sync) } ?? "") + Fmt.its([s.warm && e.coresNow >= 0.5 ? "adding to the heat" : nil]),
                    fixes: [s.syncFeed?.fix(sync, recommended: true),
                            Fix(id: "pause", title: "Pause syncing", consequence: "Opens \(sync) so you can pause it; we'll remind you to resume. Changes wait until then.",
                                kind: .pauseSync(bundle, sync), recommended: s.warm || s.gameRunning != nil
                                    || (s.onBattery && (e.coresNow >= 2 || ((s.battery ?? 100) < 50 && e.coresNow >= 1)))),
                            RunCooler.offered(e) ? Fix(id: "cooler", title: "Run it cooler", consequence: "Syncs slower. Undo any time.", kind: .cooler) : nil,
                            Fix(id: "quit", title: "Quit \(sync)", consequence: "Stops syncing until you open it again.", kind: .quitApp(bundle))].compactMap { $0 })
    }
}

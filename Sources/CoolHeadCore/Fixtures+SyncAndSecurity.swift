import Darwin
import Foundation

/// Checks for security software and sync apps (see Protected.swift and SyncFeed.swift).
extension Fixture {
    static func syncAndSecurityChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        // Security software is never stopped, slowed or quit; sync apps offer pausing (System Sentinel review,
        // 15 November 2026), after Run it cooler under One Click First (16 November 2026)
        let falcon = Evidence.sample(name: "falcond", path: "/Library/CS/falcond", start: now.addingTimeInterval(-3600), cores: 1)
        let warp = Evidence.sample(name: "Cloudflare WARP", path: "/Applications/Cloudflare WARP.app/Contents/MacOS/Cloudflare WARP", start: now, cores: 0.8)
        let reset = Evidence.sample(name: "Reset", path: "/Users/x/bin/Reset", start: now, cores: 1)
        let fc = Card.make(falcon, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        let wc = Card.make(warp, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        let noHarm = { (c: Card) in !c.fixes.contains { f in
            switch f.kind { case .stop, .cooler, .quitApp, .forceQuit, .pauseJob: return true; default: return false } } }
        let secOK = fc.headline.contains("CrowdStrike Falcon is security software") && noHarm(fc) && wc.headline.contains("VPN") && noHarm(wc)
            && SecuritySoftware.product(path: reset.path, name: reset.name) == nil
        let drive = "/Applications/Google Drive.app"
        let gd = Evidence.sample(name: "Google Drive", path: drive + "/Contents/MacOS/Google Drive", args: [drive + "/Contents/MacOS/Google Drive", "--single_process"],
                                 start: now.addingTimeInterval(-3 * 3600), cores: 2)
        let gdWarm = Card.make(gd, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        let gdCool = Card.make(gd, now: now, busySince: now.addingTimeInterval(-3600))
        let syncOK = gdWarm.headline == "Google Drive is syncing your files." && gdWarm.recommended?.id == "cooler"
            && gdWarm.fixes.map(\.id) == ["cooler", "quit", "pause"] && gdCool.recommended == nil && !gdWarm.fixes.contains { $0.id == "stop" }
        review.append(("protected-and-sync", secOK && syncOK, "security \(secOK), sync \(syncOK): \(gdWarm.fixes.map(\.id))"))
        // a build writing into a folder the sync app syncs (Phil's Google Drive errors, 15 November 2026): its own folder
        // is certain; Documents and Desktop only "may" be backed up; anything else isn't its business
        let home = "/Users/x"
        let ownFolder = SyncFeed.place(home + "/Library/CloudStorage/GoogleDrive-x@example.com/My Drive/App", sync: "Google Drive", home: home)
        let otherApps = SyncFeed.place(home + "/Library/CloudStorage/Dropbox/App", sync: "Google Drive", home: home)
        let docs = SyncFeed.place(home + "/Documents/AI/Mac.apk", sync: "Google Drive", home: home)
        let elsewhere = SyncFeed.place(home + "/Coding/Mac.apk", sync: "Google Drive", home: home)
        let placesOK = ownFolder == .some(nil) && otherApps == nil && docs == .some("Documents") && elsewhere == nil
        let feed = SyncFeed.find(sync: "Google Drive", writers: [(home + "/Documents/AI/Mac.apk", "java", 5_000_000), (home + "/Coding/Other", "clang", 9_000_000)], home: home)
        let fed = Card.make(gd, now: now, busySince: now.addingTimeInterval(-3600), warm: true, syncFeed: feed)
        let fedOK = feed == SyncFeed(who: "java", folder: "Mac.apk", area: "Documents", path: home + "/Documents/AI/Mac.apk") && fed.recommended?.kind == .cooler
            && fed.betterThanRecommended.map(\.title) == ["Keep Mac.apk out of synced folders"]
            && fed.explanation.contains("It may be uploading the files java is writing in Mac.apk, inside Documents: if Google Drive backs up Documents")
            && !fed.explanation.contains("x@example.com")
        review.append(("sync-fed-by-a-build", placesOK && fedOK, "places \(placesOK); \(fed.recommended?.title ?? "none"): \(fed.explanation)"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func syncAndSecuritySamples(_ now: Date) -> [(String, Card)] { [] }
}

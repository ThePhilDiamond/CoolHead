import Foundation

/// Checks for turning off another app's background helper (see BackgroundAgents) and keeping build output out of Time
/// Machine (see BackupExclusions).
extension Fixture {
    /// Google's updater, for the example card and the checks.
    public static let updaterPath = "/Users/x/Library/Application Support/Google/GoogleUpdater/150.0/GoogleUpdater.app/Contents/MacOS/GoogleUpdater"
    public static let updaterAgent = BackgroundAgents.Agent(label: "com.google.GoogleUpdater.wake", plist: "/Users/x/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist",
                                                            program: updaterPath, owner: "GoogleUpdater")

    static func backgroundAndBackupChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "coolhead-agents-\(getpid())-\(UUID().uuidString.prefix(8))"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }

        // which helper runs a program, from the plists alone: Program or ProgramArguments; never macOS's own, never one
        // that runs a macOS program (a shell could run anything), never security software
        func plist(_ file: String, _ d: [String: Any]) {
            let data = try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
            fm.createFile(atPath: dir + "/" + file, contents: data)
        }
        let updater = "/Users/x/Library/Application Support/Google/GoogleUpdater/150.0/GoogleUpdater.app/Contents/MacOS/GoogleUpdater"
        plist("com.google.GoogleUpdater.wake.plist", ["Label": "com.google.GoogleUpdater.wake", "ProgramArguments": [updater, "--wake"]])
        plist("com.example.sync.plist", ["Label": "com.example.sync", "Program": "/opt/example/syncd"])
        plist("com.apple.thing.plist", ["Label": "com.apple.thing", "Program": "/opt/apple/thing"])
        plist("com.example.shell.plist", ["Label": "com.example.shell", "ProgramArguments": ["/bin/sh", "-c", "run"]])
        plist("not-a-plist.txt", ["Label": "x", "Program": "/opt/x"])
        let found = BackgroundAgents.all(in: [dir]).map(\.label)
        let owner = BackgroundAgents.owner(of: [updater], in: [dir])
        let viaParent = BackgroundAgents.owner(of: ["/opt/example/child", "/opt/example/syncd"], in: [dir])
        let a1 = found == ["com.example.sync", "com.google.GoogleUpdater.wake"] && owner?.owner == "GoogleUpdater"
            && owner?.label == "com.google.GoogleUpdater.wake" && viaParent?.owner == "com.example.sync"
            && BackgroundAgents.owner(of: ["/opt/apple/thing"], in: [dir]) == nil && BackgroundAgents.owner(of: ["/bin/sh"], in: [dir]) == nil
        review.append(("agent-found-by-program", a1, "found \(found), updater's owner \(owner?.owner ?? "none"), via its parent \(viaParent?.label ?? "none")"))

        // the option: offered on a busy helper's card, with Caution (what it does for its app isn't known), never the
        // recommendation, and never for a process that isn't yours or a card that's quiet
        let helper = Evidence.sample(name: "GoogleUpdater", path: updater, start: now.addingTimeInterval(-3600), cores: 1.2)
        let busy = Card.make(helper, now: now, busySince: now.addingTimeInterval(-1800), agent: owner)
        let notMine = catalogueProcess("GoogleUpdater", updater, mine: false, start: now.addingTimeInterval(-3600), cores: 1.2)
        let theirs = Card.make(notMine, now: now, busySince: now.addingTimeInterval(-1800), agent: owner)
        let quiet = Card.make(Evidence.sample(name: "GoogleUpdater", path: updater, start: now.addingTimeInterval(-3600), cores: 0.05), now: now, agent: owner)
        let opt = busy.fixes.first { $0.id == "agent" }
        let a2 = opt?.title == "Stop it starting by itself" && opt?.caution == true && opt?.interrupts == true && opt?.recommended == false
            && opt?.doer == .coolHead && opt?.consequence.contains("Whatever it does for GoogleUpdater") == true && busy.hasAction
            && !theirs.fixes.contains { $0.id == "agent" } && quiet.fixes.isEmpty
        review.append(("agent-option", a2, "options \(busy.fixes.map(\.id)); recommended \(busy.recommended?.id ?? "none"); \(opt?.consequence ?? "no option")"))

        // and really, in this login session, on a helper of the test's own (one fixed label, so the record launchd keeps
        // of what's turned off gains one line, not one per run): loaded, turned off (not loaded, kept from loading),
        // listed, turned back on (loaded again), and left as it was
        let label = "org.coolhead.selftest.agent"
        let testPlist = dir + "/\(label).plist"
        // its program waits for this selftest to end, then ends too, so a selftest stopped part way doesn't leave it
        // running (26 November 2026: it was /bin/sleep 600)
        plist("\(label).plist", ["Label": label, "ProgramArguments": ["/bin/sh", "-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 1; done"],
                                  "RunAtLoad": true])
        let test = BackgroundAgents.Agent(label: label, plist: testPlist, program: "/bin/sh", owner: "Cool Head's selftest")
        let marker = "selftestAgents-\(getpid())"
        let session = BackgroundAgents.launchctl(["print", BackgroundAgents.domain]).status == 0
        if !session {
            review.append(("agent-really-turns-off", true, "no login session here (\(BackgroundAgents.domain)), so nothing to test in; the finding and option checks above still ran"))
        } else {
            BackgroundAgents.launchctl(["bootout", "\(BackgroundAgents.domain)/\(label)"])
            BackgroundAgents.launchctl(["enable", "\(BackgroundAgents.domain)/\(label)"])
            BackgroundAgents.launchctl(["bootstrap", BackgroundAgents.domain, testPlist])
            let loaded = BackgroundAgents.isLoaded(label)
            let off = BackgroundAgents.turnOff(test, marker: marker)
            let offState = (BackgroundAgents.isDisabled(label), BackgroundAgents.isLoaded(label))
            let listed = BackgroundAgents.turnedOff(marker: marker).map(\.label) == [label]
            let on = BackgroundAgents.turnOn(test, marker: marker)
            let onState = (BackgroundAgents.isDisabled(label), BackgroundAgents.isLoaded(label))
            let unlisted = BackgroundAgents.turnedOff(marker: marker).isEmpty && UserDefaults.standard.data(forKey: marker) == nil
            BackgroundAgents.launchctl(["bootout", "\(BackgroundAgents.domain)/\(label)"])
            let apple = !BackgroundAgents.turnOff(BackgroundAgents.Agent(label: "com.apple.never", plist: "/dev/null", program: "/bin/sleep", owner: "x"), marker: marker)
            let a3 = loaded && off && offState == (true, false) && listed && on && onState == (false, true) && unlisted && apple
            review.append(("agent-really-turns-off", a3,
                           "loaded \(loaded); off \(off) (disabled \(offState.0), loaded \(offState.1)), listed \(listed); back on \(on) (disabled \(onState.0), loaded \(onState.1)), unlisted \(unlisted); refuses com.apple \(apple)"))
        }
        UserDefaults.standard.removeObject(forKey: marker)

        // Time Machine: only build output, found by folder name inside your home folder, never the project itself
        let home = "/Users/x"
        let b1 = BackupExclusions.buildFolder(of: "/Users/x/Code/App/build/Release/a.o", home: home) == "/Users/x/Code/App/build"
            && BackupExclusions.buildFolder(of: "/Users/x/Library/Developer/Xcode/DerivedData/App-abc/Build/Intermediates/x.o", home: home)
                == "/Users/x/Library/Developer/Xcode/DerivedData"
            && BackupExclusions.buildFolder(of: "/Users/x/Code/site/node_modules/.cache/x", home: home) == "/Users/x/Code/site/node_modules"
            && BackupExclusions.buildFolder(of: "/Users/x/Documents/report.docx", home: home) == nil
            && BackupExclusions.buildFolder(of: "/Users/x/Code/App/build", home: home) == nil          // a file named build
            && BackupExclusions.buildFolder(of: "/opt/build/x.o", home: home) == nil                   // outside your home folder
        let writers: [(who: String, files: [String], bytes: UInt64)] = [
            ("cp", ["/Users/x/Documents/big.mov"], 900_000_000),
            ("swift-frontend", ["/Users/x/Code/App/.build/debug/a.o"], 50_000_000),
            ("xcodebuild", ["/Users/x/Library/Developer/Xcode/DerivedData/App-abc/Build/x.o"], 400_000_000),
        ]
        let picked = BackupExclusions.find(writers: writers, home: home, excluded: { _ in false })
        let skipped = BackupExclusions.find(writers: writers, home: home, excluded: { $0.hasSuffix("DerivedData") })
        let b2 = picked == BackupFeed(who: "xcodebuild", path: "/Users/x/Library/Developer/Xcode/DerivedData")
            && skipped?.path == "/Users/x/Code/App/.build" && BackupExclusions.find(writers: [writers[0]], home: home, excluded: { _ in false }) == nil
        review.append(("backup-build-folder", b1 && b2, "folders \(b1); picked \(picked?.path ?? "none") by \(picked?.who ?? "none"); with that excluded, \(skipped?.path ?? "none")"))

        // the option, on Time Machine's card: recommended, not Caution (known and undoable), saying why
        let backupd = catalogueProcess("backupd", "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd", mine: false,
                                       start: now.addingTimeInterval(-5 * 3600), cores: 1.5)
        let tm = Card.make(backupd, now: now, busySince: now.addingTimeInterval(-5 * 3600), backupFeed: picked)
        let tmPlain = Card.make(backupd, now: now, busySince: now.addingTimeInterval(-5 * 3600))
        let rec = tm.recommended
        let b3 = rec?.title == "Keep DerivedData out of Time Machine" && rec?.caution == false && rec?.doer == .coolHead
            && tm.explanation.contains("It probably backs up DerivedData in Xcode, which xcodebuild keeps rewriting")
            && !tmPlain.fixes.contains { $0.id == "backup" } && !tmPlain.explanation.contains("may be backing up")
        review.append(("backup-option", b3, "\(tm.headline) \(tm.explanation) Recommended: \(rec?.title ?? "none")"))

        func tmutil(_ p: String) -> String {
            String(decoding: Hardware.run("/usr/bin/tmutil", ["isexcluded", p]) ?? Data(), as: UTF8.self)
        }
        // and really, on a folder of the test's own, in Cool Head's own Application Support folder (a temporary folder
        // won't do: Time Machine always skips those): backed up to start with; left out, and Time Machine's own tmutil
        // agrees; a file inside counts as left out; backed up again, and tmutil agrees
        let own = NSHomeDirectory() + "/Library/Application Support/Cool Head/selftest-\(getpid())"
        let folder = own + "/build"
        try? fm.createDirectory(atPath: folder + "/Release", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: own) }
        let before = !BackupExclusions.isExcluded(folder) && tmutil(folder).contains("[Included]")
        let bmarker = "selftestBackup-\(getpid())"
        let out = BackupExclusions.exclude(folder, marker: bmarker)
        let outState = (BackupExclusions.isExcluded(folder), BackupExclusions.isExcluded(folder + "/Release"), tmutil(folder).contains("[Excluded]"))
        let listedB = BackupExclusions.excludedByCoolHead(marker: bmarker) == [folder]
        let back = BackupExclusions.include(folder, marker: bmarker)
        let backState = (BackupExclusions.isExcluded(folder), tmutil(folder).contains("[Included]"))
        let unlistedB = UserDefaults.standard.stringArray(forKey: bmarker) == nil
        UserDefaults.standard.removeObject(forKey: bmarker)
        let b4 = before && out && outState == (true, true, true) && listedB && back && backState == (false, true) && unlistedB
        review.append(("backup-really-excludes", b4,
                       "backed up to start with \(before); left out \(out) (it \(outState.0), inside \(outState.1), tmutil \(outState.2)), listed \(listedB); back \(back) (left out \(backState.0), tmutil included \(backState.1)), unlisted \(unlistedB)"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func backgroundAndBackupSamples(_ now: Date) -> [(String, Card)] { [] }
}

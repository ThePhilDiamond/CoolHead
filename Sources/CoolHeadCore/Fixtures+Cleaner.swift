import Foundation

/// Checks for the Cleaner tool (see Cleaner): each rule against a folder of made-up files, the Trash and Put back for
/// real with a throwaway file, the password job's command, and a scan of this Mac that must be quick and never offer
/// macOS's own files. The Cleaner has no cards, so no example cards.
extension Fixture {
    static func cleanerSamples(_ now: Date) -> [(String, Card)] { [] }

    static func cleanerChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "coolhead-cleaner-\(getpid())-\(UUID().uuidString.prefix(8))"
        let home = root + "/home", library = root + "/Library", apps = root + "/Applications"
        defer { try? fm.removeItem(atPath: root) }
        func dir(_ p: String) { try? fm.createDirectory(atPath: p, withIntermediateDirectories: true) }
        func age(_ p: String, _ days: Double) {
            if days > 0 { try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86_400)], ofItemAtPath: p) }
        }
        func file(_ p: String, bytes: Int = 10, daysOld: Double = 0) {
            dir((p as NSString).deletingLastPathComponent)
            fm.createFile(atPath: p, contents: Data(count: bytes))
            age(p, daysOld)
        }
        func plist(_ p: String, _ d: [String: Any]) { dir((p as NSString).deletingLastPathComponent); (d as NSDictionary).write(toFile: p, atomically: true) }
        func bundle(_ p: String, id: String) { plist(p + "/Contents/Info.plist", ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]) }
        for d in [home + "/Library/LaunchAgents", home + "/Library/Logs", home + "/Library/Caches", home + "/Library/Saved Application State",
                  home + "/Library/PreferencePanes", library + "/PreferencePanes", library + "/LaunchDaemons", apps] { dir(d) }
        let roots = Cleaner.Roots(home: home, library: library, applications: [apps], now: now, macOSMajor: 26)

        // lists in sentences take the Oxford comma
        let j = Fmt.list(["a", "b", "c"]) == "a, b, and c" && Fmt.list(["a", "b"]) == "a and b" && Fmt.list(["a"]) == "a"
        let k = Cleaner.kinds([.init(id: "pane:x", group: .check, title: "", detail: "", bytes: nil),
                               .init(id: "pane:y", group: .check, title: "", detail: "", bytes: nil),
                               .init(id: "install:Sonoma", group: .check, title: "", detail: "", bytes: nil)])
        review.append(("cleaner-sentences", j && k == ["2 settings panes in the System Settings sidebar", "an old macOS installer"], "\(k)"))

        // Quick clean: a helper whose program is gone; never one whose program is there, on another disk, run by an
        // interpreter, started through an app bundle, or labelled like Apple's
        let la = home + "/Library/LaunchAgents/"
        plist(la + "gone.plist", ["Label": "com.example.gone", "ProgramArguments": [root + "/nowhere/updater"]])
        plist(la + "there.plist", ["Label": "com.example.there", "Program": "/bin/ls"])
        plist(la + "disk.plist", ["Label": "com.example.disk", "Program": "/Volumes/Backup/tool"])
        plist(la + "script.plist", ["Label": "com.example.script", "ProgramArguments": ["/bin/sh", root + "/nowhere/run.sh"]])
        plist(la + "bundle.plist", ["Label": "com.example.bundle", "BundleProgram": "Contents/MacOS/helper"])
        plist(la + "apple.plist", ["Label": "com.apple.fake", "Program": root + "/nowhere/x"])
        let agents = Cleaner.brokenAgents(roots)
        review.append(("cleaner-broken-helpers", agents.map(\.agentLabel) == ["com.example.gone"] && agents.first?.group == .quick
                       && agents.first?.title == "Example's background helper", "found \(agents.map { $0.agentLabel ?? "" })"))

        // Quick clean: logs over 30 days only, and only when they add up to a megabyte
        file(home + "/Library/Logs/App/old.log", bytes: 1_200_000, daysOld: 40)
        file(home + "/Library/Logs/DiagnosticReports/new.ips", bytes: 900_000)
        let logs = Cleaner.oldLogs(roots)
        review.append(("cleaner-old-logs", logs.count == 1 && logs[0].paths.count == 1 && logs[0].paths[0].hasSuffix("old.log"),
                       "\(logs.first?.paths.count ?? 0) file(s), \(logs.first?.bytes ?? 0) bytes"))

        // "Owner gone": an installed app claims its own ID and its helpers'; a name no app uses, quiet for a month, is
        // left behind; Apple's names never; and when Applications can't be read, nothing is called left behind
        bundle(apps + "/Kept.app", id: "com.example.kept")
        bundle(apps + "/Vendor/Tool.app", id: "com.vendor.tool")
        let installed = Cleaner.installedApps(roots)
        let sas = home + "/Library/Saved Application State/"
        for id in ["com.example.kept", "com.example.kept.helper", "com.vendor.tool", "com.example.gone", "com.apple.Safari"] {
            file(sas + id + ".savedState/data.data", daysOld: 60); age(sas + id + ".savedState", 60)
        }
        file(sas + "com.example.recent.savedState/data.data")
        let saved = Cleaner.savedState(roots, apps: installed)
        let savedNames = saved.first?.paths.map { ($0 as NSString).lastPathComponent } ?? []
        let blind = Cleaner.savedState(roots, apps: nil)
        let unreadable = Cleaner.installedApps(.init(home: home, library: library, applications: [root + "/missing"], macOSMajor: 26)) == nil
        review.append(("cleaner-owner-gone", installed?.ids == ["com.example.kept", "com.vendor.tool"] && savedNames == ["com.example.gone.savedState"]
                       && blind.isEmpty && unreadable,
                       "installed \(installed?.ids.sorted() ?? []); left behind \(savedNames); Applications unreadable gives nothing \(unreadable)"))

        // a deleted app's caches: 50 MB or more, quiet for a month, named for no app; Caution, never ticked
        for id in ["com.example.gone", "com.example.kept"] {
            file(home + "/Library/Caches/\(id)/big.data", bytes: 51_000_000, daysOld: 60); age(home + "/Library/Caches/\(id)", 60)
        }
        file(home + "/Library/Caches/com.example.small/s.data", bytes: 1_000, daysOld: 60); age(home + "/Library/Caches/com.example.small", 60)
        let caches = Cleaner.orphanCaches(roots, apps: installed)
        review.append(("cleaner-deleted-app-caches", caches.map(\.id) == ["caches:com.example.gone"] && caches.allSatisfy { $0.caution && $0.group == .check },
                       "\(caches.map(\.id))"))

        // settings panes: left behind only when nothing else from the developer is here (no app, no helper, no driver);
        // the shared folder needs a password; on a managed Mac the shared folder isn't offered at all
        bundle(home + "/Library/PreferencePanes/Gone.prefPane", id: "com.gonevendor.pane")
        bundle(home + "/Library/PreferencePanes/Kept.prefPane", id: "com.vendor.settings")
        bundle(library + "/PreferencePanes/Driver.prefPane", id: "com.drivermaker.pane")
        plist(library + "/LaunchDaemons/com.drivermaker.daemon.plist", ["Label": "com.drivermaker.daemon"])
        bundle(library + "/PreferencePanes/Shared.prefPane", id: "com.sharedgone.pane")
        let panes = Cleaner.panes(roots, apps: installed)
        var managed = roots; managed.enrolled = true
        let managedPanes = Cleaner.panes(managed, apps: installed)
        review.append(("cleaner-settings-panes", panes.map(\.id) == ["pane:com.gonevendor.pane", "pane:com.sharedgone.pane"]
                       && panes.map(\.needsAdmin) == [false, true] && panes.allSatisfy(\.caution) && managedPanes.map(\.id) == ["pane:com.gonevendor.pane"],
                       "found \(panes.map(\.id)); on a managed Mac \(managedPanes.map(\.id))"))

        // macOS installers: only an older macOS than this one, never on a managed Mac, and always with a password
        for n in ["Sonoma", "Tahoe", "Someday"] { dir(apps + "/Install macOS \(n).app") }
        let inst = Cleaner.oldInstallers(roots)
        review.append(("cleaner-old-installers", inst.map(\.id) == ["install:Sonoma"] && inst.allSatisfy(\.needsAdmin)
                       && Cleaner.oldInstallers(managed).isEmpty, "\(inst.map(\.id))"))

        // a folder the person chose: an identical second download (Quick clean), not one that differs; an installer over
        // 30 days old (Caution), not a new one or one open now
        let dl = root + "/Downloads"
        file(dl + "/Report.pdf", bytes: 5_000); file(dl + "/Report (1).pdf", bytes: 5_000)
        file(dl + "/Notes.txt", bytes: 10); fm.createFile(atPath: dl + "/Notes (1).txt", contents: Data("different".utf8))
        file(dl + "/Old.dmg", bytes: 100, daysOld: 40); file(dl + "/Open.dmg", bytes: 100, daysOld: 40); file(dl + "/New.pkg", bytes: 100)
        let downloads = Cleaner.scanDownloads(dl, now: now, mounted: [dl + "/Open.dmg"])
        let ids = Set(downloads.map(\.id))
        review.append(("cleaner-downloads", ids == ["download:Old.dmg", "copy:Report (1).pdf"]
                       && downloads.first { $0.id.hasPrefix("copy:") }?.group == .quick && downloads.first { $0.id.hasPrefix("download:") }?.caution == true
                       && Cleaner.secondDownload("a (12).zip") == "a.zip" && Cleaner.secondDownload("a.zip") == nil, "\(downloads.map(\.id))"))

        // for real: a throwaway file goes to the Trash and comes back; a link moves as a link, its target staying; a path
        // through a linked folder planted in a scanned folder is refused
        let defaults = UserDefaults(suiteName: "coolhead-selftest-cleaner")!
        defaults.removePersistentDomain(forName: "coolhead-selftest-cleaner")
        let tag = UUID().uuidString.prefix(6)
        let victim = home + "/Library/Caches/coolhead-selftest-\(tag).txt"
        file(victim, bytes: 100)
        let link = home + "/Library/Caches/coolhead-selftest-link-\(tag)"
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: dl + "/Report.pdf")
        let tunnel = home + "/Library/Caches/coolhead-selftest-tunnel-\(tag)"
        try? fm.createSymbolicLink(atPath: tunnel, withDestinationPath: dl)
        let through = tunnel + "/Notes.txt"
        let t = Cleaner.trash(.init(id: "t", group: .quick, title: "", detail: "", bytes: nil, paths: [victim, link, through]), home: home, defaults: defaults)
        let inTrash = t.moved.count == 2 && t.moved.allSatisfy { fm.fileExists(atPath: $0.to) }
        let listed = Cleaner.movedList(defaults).count == 2
        let back = t.moved.allSatisfy { Cleaner.putBack($0, defaults: defaults) }
        review.append(("cleaner-trash-and-put-back", inTrash && listed && back && fm.fileExists(atPath: victim) && t.failed == [through]
                       && fm.fileExists(atPath: dl + "/Report.pdf") && fm.fileExists(atPath: dl + "/Notes.txt") && Cleaner.movedList(defaults).isEmpty,
                       "moved \(t.moved.count) (a file and a link, its target kept), refused \(t.failed.count) (through a linked folder), put back \(back)"))
        defaults.removePersistentDomain(forName: "coolhead-selftest-cleaner")

        // the password job's command: each name its own argument, never parsed by a shell; nothing for items that need none
        let a = Cleaner.adminArguments([(from: "/Library/PreferencePanes/A b.prefPane", to: home + "/.Trash/A b.prefPane")])
        let none = Cleaner.adminMoves(.init(id: "x", group: .check, title: "", detail: "", bytes: nil, paths: [victim]), home: home)
        review.append(("cleaner-password-command", a.prefix(2) == ["/bin/sh", "-c"] && Array(a.suffix(2)) == ["/Library/PreferencePanes/A b.prefPane", home + "/.Trash/A b.prefPane"]
                       && none.isEmpty, a.joined(separator: " | ")))

        // this Mac: a quick scan that never offers macOS's own files or anything outside the places it reads
        let start = Date()
        let mine = Cleaner.scan(.thisMac())
        let took = Date().timeIntervalSince(start)
        let stray = mine.flatMap(\.paths).filter { $0.hasPrefix("/System/") || !Cleaner.safe($0, home: NSHomeDirectory()) }
        let counts = Dictionary(grouping: mine, by: \.group.rawValue).mapValues(\.count).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        review.append(("cleaner-this-mac", took < 30 && stray.isEmpty,
                       "\(mine.count) find(s) in \(String(format: "%.1f", took)) s (\(counts.joined(separator: ", "))); outside its places: \(stray.count)"))
        return review
    }
}

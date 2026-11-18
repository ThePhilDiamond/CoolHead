import Foundation

/// Every card Cool Head can show, from its recorded examples, so all the wording can be read in one place
/// (`coolhead wording`). Hand-written wording (Phil, 15 November 2026: "Yes, hand-write it"): no model rewords anything,
/// so this list is what people read.
public enum Wording {
    public static func samples(now: Date = Date()) -> [(String, Card)] {
        var out: [(String, Card)] = Fixture.all(now).map { f in
            (f.id, Card.make(f.evidence, now: now, busySince: now.addingTimeInterval(-f.busyFor)))
        }
        // each feature's sample cards, from its Fixtures+<Feature>.swift file, alphabetical (the build writes the list)
        for samples in Fixture.sampleSuites { out += samples(now) }
        // another app's background helper, and Time Machine copying a build's output
        out.append(("background-helper", Card.make(Evidence.sample(name: "GoogleUpdater", path: Fixture.updaterPath, start: now.addingTimeInterval(-3600), cores: 1.2),
                                                   now: now, busySince: now.addingTimeInterval(-1800), agent: Fixture.updaterAgent)))
        out.append(("time-machine-build", Card.make(Fixture.catalogueProcess("backupd", "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd", mine: false,
                                                                             start: now.addingTimeInterval(-5 * 3600), cores: 1.5),
                                                    now: now, busySince: now.addingTimeInterval(-50 * 60),
                                                    backupFeed: BackupFeed(who: "xcodebuild", path: NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"))))
        // memory
        var tight = MacState(); tight.memoryPressure = "warning"; tight.swapUsedMB = 1500; tight.swapTotalMB = 3000
        func group(_ name: String, _ kind: MemGroup.Kind, _ bundle: String?, _ gb: Double, _ n: Int) -> MemGroup {
            MemGroup(key: name, name: name, kind: kind, bundle: bundle, bytes: UInt64(gb * 1_000_000_000), count: n)
        }
        let chrome = group("Google Chrome", .browser, "/Applications/Google Chrome.app", 5.5, 41)
        out.append(("memory-chrome", MemoryAdvice.card([chrome], mac: tight, now: now, chrome: .available(4096), tabMemoryOn: false)))
        out.append(("memory-chrome-limited", MemoryAdvice.card([chrome], mac: tight, now: now, chrome: .set(4096), tabMemoryOn: false)))
        out.append(("memory-safari", MemoryAdvice.card([group("Safari", .browser, "/Applications/Safari.app", 4, 20)], mac: tight, now: now)))
        out.append(("memory-edge", MemoryAdvice.card([group("Microsoft Edge", .browser, "/Applications/Microsoft Edge.app", 4, 20)], mac: tight, now: now, chrome: .unavailable)))
        out.append(("memory-sync-app", MemoryAdvice.card([group("Google Drive", .app, "/Applications/Google Drive.app", 6, 3), chrome], mac: tight, now: now, chrome: .available(4096))))
        // names that look alike: an app and a command-line program of the same name, told apart (see Naming)
        var claudeCLI = MemGroup(key: "other-claude", name: "claude", kind: .other, bundle: nil, bytes: 1_600_000_000, count: 1)
        claudeCLI.what = .commandLine
        out.append(("memory-app-and-program-alike", MemoryAdvice.card([group("Claude", .app, "/Applications/Claude.app", 2.9, 4), claudeCLI], mac: tight, now: now)))
        var node = MemGroup(key: "other-node", name: "node", kind: .other, bundle: nil, bytes: 3_000_000_000, count: 1)
        node.what = .background
        out.append(("memory-program-first", MemoryAdvice.card([node, group("Slack", .app, "/Applications/Slack.app", 1.2, 5)], mac: tight, now: now)))
        // a nearly full startup disk, and heavy swapping while macOS still says normal (research nodes N-002, N-006)
        var lowDisk = tight; lowDisk.diskFreeBytes = 12_400_000_000
        out.append(("memory-low-disk", MemoryAdvice.card([group("Slack", .app, "/Applications/Slack.app", 3.1, 5)], mac: lowDisk, now: now)))
        var swapping = MacState(); swapping.memoryPressure = "normal"; swapping.swapUsedMB = 4200; swapping.swapTotalMB = 5120; swapping.swappedOutMB = 1400
        out.append(("memory-heavy-swap", MemoryAdvice.card([group("Xcode", .app, "/Applications/Xcode.app", 6.2, 9)], mac: swapping, now: now)))
        out.append(("memory-docker", MemoryAdvice.card([group("Docker", .app, "/Applications/Docker.app", 4, 3)], mac: tight, now: now)))
        out.append(("memory-job", MemoryAdvice.card([MemGroup(key: "job-1", name: "a script", kind: .job, bundle: nil, bytes: 3_000_000_000, count: 1, pid: 4242)], mac: tight, now: now)))
        // hangs
        let job = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                  start: now.addingTimeInterval(-7200), cores: 0)
        let app = Evidence.sample(name: "Foo", path: "/Applications/Foo.app/Contents/MacOS/Foo", start: now.addingTimeInterval(-7200), cores: 0)
        out.append(("hang-paused-in-terminal", Hang.card(.paused, Fixture.withParent(job, "zsh"), stuckFor: 3600, terminal: "/System/Applications/Utilities/Terminal.app", now: now)))
        out.append(("hang-paused-by-something-else", Hang.card(.paused, Fixture.withParent(job, "launchd"), stuckFor: 600, waiting: ["ffmpeg", "ffmpeg"], now: now)))
        out.append(("hang-waiting-on-a-drive", Hang.card(.diskWait, Fixture.withParent(job, "launchd"), stuckFor: 300, volumes: ["Backup"], now: now)))
        let ffmpeg = Evidence.sample(name: "ffmpeg", path: "/opt/homebrew/bin/ffmpeg", args: ["ffmpeg", "-i", "in.mov", "out.mp4"], cwd: "/Users/x/Movies",
                                     start: now.addingTimeInterval(-7200), cores: 0)
        out.append(("hang-started-a-program-of-its-own-name", Hang.card(.paused, Fixture.withParent(ffmpeg, "launchd"), stuckFor: 600, waiting: ["ffmpeg", "ffprobe"], now: now)))
        out.append(("hang-not-responding-new", Hang.card(.notResponding, app, stuckFor: 120, now: now)))
        out.append(("hang-not-responding-settled", Hang.card(.notResponding, app, stuckFor: 600, now: now)))
        // busy apps and processes the catalogue doesn't cover
        let hour: TimeInterval = 3600
        func ev(_ name: String, _ path: String, _ args: [String] = [], cores: Double, gpu: Double? = nil, start: TimeInterval = 2 * hour) -> Evidence {
            var e = Evidence.sample(name: name, path: path, args: args, start: now.addingTimeInterval(-start), cores: cores)
            e.gpuShare = gpu
            return e
        }
        func card(_ id: String, _ e: Evidence, busy: TimeInterval = hour, warm: Bool = false, game: String? = nil, front: String? = nil, battery: Int? = nil, feed: SyncFeed? = nil) {
            out.append((id, Card.make(e, now: now, busySince: now.addingTimeInterval(-busy), warm: warm, gameRunning: game, frontApp: front, battery: battery, syncFeed: feed)))
        }
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        card("chrome-tab", ev("Google Chrome Helper (Renderer)", helper, ["--type=renderer"], cores: 1.2))
        card("chrome-tab-in-front-warm", ev("Google Chrome Helper (Renderer)", helper, ["--type=renderer"], cores: 1.2), warm: true, front: "/Applications/Google Chrome.app")
        card("chrome-extension", ev("Google Chrome Helper (Renderer)", helper, ["--type=renderer", "--extension-process"], cores: 0.8))
        card("chrome-graphics", ev("Google Chrome Helper (GPU)", helper.replacingOccurrences(of: "(Renderer)", with: "(GPU)"), ["--type=gpu-process"], cores: 0.2, gpu: 0.6))
        card("safari-tab", ev("com.apple.WebKit.WebContent", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", cores: 1.1))
        card("web-page-drawing", ev("com.apple.WebKit.GPU", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU", cores: 0.2, gpu: 0.55))
        let drive = ev("Google Drive", "/Applications/Google Drive.app/Contents/MacOS/Google Drive", cores: 1.5)
        card("sync-app", drive)
        card("sync-app-warm-fed-by-a-build", drive, warm: true, feed: SyncFeed(who: "MyApp", folder: "MyApp", area: "Documents", path: "/Users/x/Documents/MyApp"))
        card("sync-app-fed-in-its-folder", drive, feed: SyncFeed(who: "gradle", folder: "app", area: nil, path: "/Users/x/Library/CloudStorage/GoogleDrive-x/My Drive/app"))
        card("security-software", ev("falcond", "/Library/CS/falcond", cores: 1.0))
        card("vpn", ev("Tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale", cores: 0.6))
        card("game", ev("Hades", "/Users/x/Library/Application Support/Steam/steamapps/common/Hades/Hades.app/Contents/MacOS/Hades", cores: 2.5, gpu: 0.8), warm: true)
        card("app-on-the-graphics-chip", ev("Blender", "/Applications/Blender.app/Contents/MacOS/Blender", cores: 0.2, gpu: 0.7), busy: 20 * 60, warm: true)
        let training = ev("python3", "/usr/bin/python3", ["python3", "train.py"], cores: 2.2, start: 3 * hour)
        card("job-unknown-warm-on-battery-during-a-game", training, busy: 3 * hour, warm: true, game: "Hades", battery: 40)
        card("job-just-started", ev("python3", "/usr/bin/python3", ["python3", "train.py"], cores: 1.5, start: 60), busy: 60)
        out += Fixture.hardwareReports(now).flatMap { s in s.1.cards(now: now).map { ("hardware-\(s.0)", $0.card) } }   // see Hardware.swift
        return out
    }

    /// One card as text: headline, explanation, then each option with what it does and any steps.
    public static func text(_ c: Card) -> String {
        var s = c.headline + "\n"
        if !c.explanation.isEmpty { s += "  " + c.explanation + "\n" }
        for f in c.fixes {
            s += "  \(f.recommended ? "→" : "·") [\(f.doer == .coolHead ? "one click" : "you")] \(f.title)" + (f.consequence.isEmpty ? "" : ": \(Fmt.plain(f.consequence))") + "\n"
            if case .guide(let steps) = f.kind { for (i, step) in steps.enumerated() { s += "      \(i + 1). \(Fmt.plain(step))\n" } }
        }
        return s
    }
}

extension LiveCard {
    /// An example card as the panel shows it, for screenshots (COOLHEAD_SNAPSHOT_SAMPLES): no process behind it.
    public static func sample(_ id: String, _ card: Card) -> LiveCard { LiveCard(id: id, pid: nil, card: card, details: card.choice?.line.map { [$0] } ?? []) }
}

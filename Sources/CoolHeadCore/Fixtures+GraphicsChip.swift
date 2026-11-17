import Darwin
import Foundation

/// Checks for the graphics chip (see GPU.swift).
extension Fixture {
    static func graphicsChipChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let game = Evidence.sample(name: "BloonsTD6", path: "/Users/x/Library/Application Support/Steam/steamapps/common/BloonsTD6/BloonsTD6.app/Contents/MacOS/BloonsTD6",
                                   start: now.addingTimeInterval(-2 * 3600), cores: 0.6)
        let tabExe = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/157.0.8103.51/Helpers/Google Chrome Helper (Aperitif Renderer).app/Contents/MacOS/Google Chrome Helper (Aperitif Renderer)"
        let busy10 = now.addingTimeInterval(-600)
        // The graphics chip (System Sentinel review, 15 November 2026): a process keeping it busy is a suspect even with
        // little CPU, and its card says how much; games stay calm and are never slowed; Chrome's graphics process and
        // WebKit's read right; slowing isn't offered for the graphics chip, since it slows CPU work, not drawing
        func withGPU(_ e: Evidence, _ g: Double?) -> Evidence { var e = e; e.gpuShare = g; return e }
        let chipLine = "It's keeping about 70% of the graphics chip busy"
        let drawer = withGPU(Evidence.sample(name: "Foo", path: "/Applications/Foo.app/Contents/MacOS/Foo", start: now.addingTimeInterval(-7200), cores: 0.1), 0.7)
        let drawerCard = Card.make(drawer, now: now, busySince: now.addingTimeInterval(-1800), warm: true)
        let drawerNoChip = Card.make(withGPU(drawer, nil), now: now, busySince: now.addingTimeInterval(-1800))
        let gpuGameCard = Card.make(withGPU(Evidence.sample(name: "BloonsTD6", path: game.path, start: now.addingTimeInterval(-7200), cores: 0.1), 0.9),
                                    now: now, busySince: now.addingTimeInterval(-7200), warm: true)
        let chromeChip = Card.make(withGPU(Evidence.sample(name: "Google Chrome Helper (Aperitif)", path: tabExe, args: [tabExe, "--type=gpu-process"],
                                                           start: now.addingTimeInterval(-3600), cores: 0.1), 0.8), now: now, busySince: busy10)
        let webkitGPU = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        let safariChip = Card.make(withGPU(Evidence.sample(name: "com.apple.WebKit.GPU", path: webkitGPU, start: now.addingTimeInterval(-3600), cores: 0.1), 0.7),
                                   now: now, busySince: busy10)
        let screen = Card.make(withGPU(Evidence.sample(name: "WindowServer", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
                                                       start: now.addingTimeInterval(-86400), cores: 0.2), 0.6), now: now, busySince: busy10)
        let mlJob = Card.make(withGPU(Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "train.py"], cwd: "/Users/x/Model",
                                                      start: now.addingTimeInterval(-3600), cores: 0.1), 0.9), now: now, busySince: now.addingTimeInterval(-3600))
        let g1 = drawerCard.state == .unknown && drawerCard.explanation.contains(chipLine) && drawerCard.explanation.contains("adding to the heat")
            && drawerCard.fixes.contains { $0.kind == .quitApp("/Applications/Foo.app") } && !drawerCard.fixes.contains { $0.kind == .cooler }
            && drawerNoChip.state == .quiet
        let g2 = gpuGameCard.state == .working && gpuGameCard.headline.contains("is a game") && gpuGameCard.explanation.contains("keeping about 90% of the graphics chip busy")
            && !gpuGameCard.fixes.contains { $0.kind == .cooler }
        let g3 = chromeChip.state != .quiet && chromeChip.explanation.hasPrefix("Its graphics process has kept about 80% of the graphics chip busy for 10 minutes.")
            && chromeChip.recommended?.title == "Turn on Energy Saver" && !chromeChip.fixes.contains { $0.kind == .cooler }
        let g4 = safariChip.headline == "A web page is drawing a lot: video or animation." && safariChip.state != .quiet
        let g5 = screen.state == .working && screen.headline.contains("drawing the screen") && screen.explanation.contains("keeping about 60% of the graphics chip busy")
        let g6 = mlJob.state == .unknown && mlJob.fixes.contains { $0.kind == .stop } && mlJob.explanation.contains("keeping about 90% of the graphics chip busy")
        let g7 = drawer.lines().contains("Graphics chip: about 70% of it now") && !withGPU(drawer, nil).lines().contains { $0.hasPrefix("Graphics chip") }
            && Fmt.share(0.02) == "under 5%" && Fmt.share(0.68) == "about 70%"
        review.append(("graphics-chip-cards", g1 && g2 && g3 && g4 && g5 && g6 && g7,
                       "app \(g1), game \(g2), Chrome \(g3), web page \(g4), screen \(g5), job \(g6), details \(g7): \(drawerCard.explanation)"))
        // and on this Mac's own IORegistry: the read works with no permission, each share is within the whole chip, and
        // macOS's own WindowServer is among the users. A Mac whose graphics driver doesn't publish it has nothing to read,
        // which is fine.
        let parse = GPU.pid(creator: "pid 400, WindowServer") == 400 && GPU.pid(creator: "WindowServer") == nil
            && GPU.share(from: 1_000_000_000, to: 1_500_000_000, seconds: 1) == 0.5 && GPU.share(from: 5, to: 2, seconds: 1) == 0
        let t1 = GPU.times()
        usleep(500_000)
        let t2 = GPU.times()
        let shares = t2.map { GPU.share(from: t1[$0.key] ?? $0.value, to: $0.value, seconds: 0.5) }
        let windowServer = t2.keys.contains { Proc.path($0)?.hasSuffix("/WindowServer") == true }
        let live = t2.isEmpty || (windowServer && shares.allSatisfy { $0 >= 0 && $0 <= 1 })
        review.append(("graphics-chip-read", parse && live,
                       t2.isEmpty ? "this Mac publishes no graphics-chip use (parsing \(parse))"
                                  : "\(t2.count) processes use the graphics chip; WindowServer among them \(windowServer); busiest \(Fmt.share(shares.max() ?? 0)) of it"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func graphicsChipSamples(_ now: Date) -> [(String, Card)] { [] }
}

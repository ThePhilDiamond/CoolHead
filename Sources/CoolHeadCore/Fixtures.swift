import AppKit
import Foundation

/// Recorded examples and the card each should produce. `coolhead selftest` runs them; CI runs it on every pull request.
/// Add one with every catalogue entry or rule you change (see docs/DIAGNOSIS.md). A feature's own checks go in their
/// own file, Fixtures+<Feature>.swift, listed in `suites` (see CONTRIBUTING.md).
public struct Fixture {
    public let id: String
    let evidence: Evidence
    let busyFor: TimeInterval
    let expectState: JobState
    let expectHeadline: String          // a phrase the headline must contain
    let expectAction: String?   // the start of the recommended fix's title

    /// Runs every example; returns (id, passed, what happened).
    /// Each feature's checks live in their own file, Fixtures+<Feature>.swift, and are listed here one per line in
    /// alphabetical order, so pull requests made at the same time add their checks in different places and don't
    /// conflict. A new feature adds its file and one line here.
    static let suites: [(Date) -> [(String, Bool, String)]] = [
        appBuildChecks,
        backgroundAndBackupChecks,
        backgroundWorkChecks,
        batteryPageChecks,
        browserRestartChecks,
        browserTamperingChecks,
        catalogueChecks,
        disguiseChecks,
        graphicsChipChecks,
        hangChecks,
        hardwareChecks,
        hardwarePageChecks,
        leakChecks,
        leftoversChecks,
        memorySignalChecks,
        namingChecks,
        networkChecks,
        optionChecks,
        powerHistoryChecks,
        powerStateChecks,
        runCoolerChecks,
        servedChecks,
        syncAndSecurityChecks,
        updateCheckChecks,
    ]

    public static func runAll() -> [(String, Bool, String)] {
        let now = Date()
        // never offer to quit a language runtime: Homebrew's Python is an app bundle, and quitting it stops a job
        let py = Evidence.sample(name: "Python", path: "/opt/homebrew/Cellar/python@3.13/3.13.16/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python",
                                 args: ["python3", "job.py"], start: now, cores: 1)
        let chrome = Evidence.sample(name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", start: now, cores: 1)
        let quit = [("never-quit-python", py.quittableApp == nil, "Python.app is not offered to quit"),
                    ("quit-real-app", chrome.quittableApp == "Google Chrome", "Google Chrome can be offered to quit")]
        // the shared case report must never carry anything private
        let secret = "/Users/alice/Secret Project"
        let leaky = Evidence(pid: 4242, name: "Python", path: "\(secret)/.venv/bin/python3",
                             args: ["python3", "\(secret)/run_payroll.py", "--token=abc123"], cwd: secret,
                             start: now.addingTimeInterval(-7200), mine: true, coresNow: 2, coresAverage: 2, performanceShare: 0.6,
                             memoryBytes: 2_000_000_000,
                             ancestors: [.init(pid: 4100, name: "zsh", path: "/bin/zsh", args: ["zsh", "-c", "cd '\(secret)' && ./go.sh"])],
                             writing: ["\(secret)/payroll-out.log"], locks: [.init(path: "\(secret)/.lock", note: "held by alice for payroll")],
                             progress: Progress(file: "\(secret)/payroll-out.log", line: "alice: 40/100 payslips", done: 40, total: 100,
                                                unit: "payslips", minutesLeft: nil, lineTime: now.addingTimeInterval(-5400)),
                             bytesWrittenDuringSample: 0, lastOutput: now.addingTimeInterval(-5400), lastLine: "alice: 40/100 payslips",
                             savesAsItGoes: false, workStart: now.addingTimeInterval(-7200))
        let leakyCard = Card.make(leaky, now: now, busySince: now.addingTimeInterval(-7200))
        let report = CaseReport.make(leaky, card: leakyCard, mac: MacState(), busySince: now.addingTimeInterval(-7200), now: now)
            + CaseReport.title(leaky, card: leakyCard)
        let found = ["alice", "Secret", "payroll", "payslips", "abc123", "go.sh", "4242", ".venv", "/Users"].filter { report.contains($0) }
        let mds = Evidence.sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores",
                                  start: now, cores: 1)
        let mdsReport = CaseReport.make(mds, card: Card.make(mds, now: now), mac: MacState(), busySince: now, now: now)
        // the problem report's activity log names processes only as the case report would
        var leakyCardLive = LiveCard(id: "x", pid: 4242, card: leakyCard, details: leaky.lines())
        leakyCardLive.reportSubject = CaseReport.subject(leaky)
        let problem = ProblemReport.make(kind: ProblemReport.kinds[0], words: "",
                                         activity: [.init(t: now, text: "Card: \(leakyCardLive.reportSubject), can't tell"),
                                                    .init(t: now, text: "Stop pressed for \(leakyCardLive.reportSubject): stopped")],
                                         cards: [leakyCardLive], mac: MacState(), now: now)
        let problemFound = ["alice", "Secret", "payroll", "payslips", "abc123", "go.sh", "4242", ".venv", "/Users"].filter { problem.contains($0) }
        let privacy = [("problem-report-leaks-nothing", problemFound.isEmpty, problemFound.isEmpty ? "no private detail in the problem report" : "leaked: \(problemFound)"),
                       ("case-report-leaks-nothing", found.isEmpty, found.isEmpty ? "no private detail in the report" : "leaked: \(found)"),
                       ("case-report-names-macos", mdsReport.contains("mds_stores (part of macOS)"), "macOS processes keep their name")]
        // review of 15 November 2026: each finding that was fixed keeps a check here
        var review: [(String, Bool, String)] = []
        // F2: a job whose progress line is old but which is writing now is working, not stuck
        let saving = Evidence(pid: 1, name: "python3", path: "/usr/bin/python3", args: ["python3", "train.py"], cwd: "/Users/x/Model",
                              start: now.addingTimeInterval(-4 * 3600), mine: true, coresNow: 1, coresAverage: 1, performanceShare: nil,
                              memoryBytes: 0, ancestors: [], writing: ["/Users/x/Model/train.log", "/Users/x/Model/checkpoint.bin"], locks: [],
                              progress: Progress(file: "/Users/x/Model/train.log", line: "500/500 epochs done", done: 500, total: 500,
                                                 unit: "epochs", minutesLeft: nil, lineTime: now.addingTimeInterval(-7200)),
                              bytesWrittenDuringSample: 50_000_000, lastOutput: now, lastLine: nil, savesAsItGoes: false, workStart: nil)
        let sc = Card.make(saving, now: now, busySince: now.addingTimeInterval(-7200))
        review.append(("F2-writing-is-not-stuck", sc.state == .working, "a job saving its result is \(sc.state.rawValue)"))
        // F5: dates and battery figures are not progress
        let date = Progress.parse("11/15/2026 10:00:01 server started", file: "", time: now)
        let battery = Progress.parse("Battery 38% · Mac using 21 W", file: "", time: now)
        let real = Progress.parse("25600/26512 passages, 178.4 min, about 6 min left", file: "", time: now)
        review.append(("F5-dates-and-battery-not-progress", date == nil && battery == nil && real?.fraction != nil,
                       "date \(date == nil ? "ignored" : "misread"), battery \(battery == nil ? "ignored" : "misread"), real progress \(real?.fraction != nil ? "read" : "missed")"))
        // F6: never Stop for macOS's own programs or an app's main program
        let login = Evidence.sample(name: "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
                                    start: now.addingTimeInterval(-86400), cores: 1)
        let xcode = Evidence.sample(name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", start: now.addingTimeInterval(-86400), cores: 1)
        let noStop = [login, xcode].allSatisfy { !Card.make($0, now: now, busySince: now.addingTimeInterval(-7200)).fixes.contains { $0.kind == .stop } }
        review.append(("F6-no-stop-for-macos-or-apps", noStop, "loginwindow and Xcode are not offered Stop"))
        // F7: Quit only for an app's own main program, not a helper inside another app
        let helper = Evidence.sample(name: "Simulator", path: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator",
                                     start: now, cores: 1)
        review.append(("F7-quit-only-main-programs", helper.quittableBundle == nil && xcode.quittableBundle == "/Applications/Xcode.app",
                       "a helper inside Xcode can't be quit as Xcode"))
        // F18: a catalogue name only counts for macOS's own copy
        review.append(("F18-name-needs-macos-path", Pattern.match(name: "bird", path: "/Users/x/bin/bird", pid: 99999) == nil
                       && Pattern.match(name: "bird", path: "/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird", pid: 99999) != nil,
                       "someone's own program called bird isn't taken for iCloud"))
        // F22: secrets in command lines are hidden
        let shown = Redact.args(["tool", "--token=abc123", "--password", "hunter2", "https://me:pw123@example.com/x"]).joined(separator: " ")
        review.append(("F22-secrets-hidden", !shown.contains("abc123") && !shown.contains("hunter2") && !shown.contains("pw123"), shown))
        // memory advice: grouping and options with their risks
        let chromeHelper = MemoryAdvice.group(pid: 10, path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", args: [], footprint: 300)
        let pyJob = MemoryAdvice.group(pid: 11, path: "/opt/homebrew/Cellar/python@3.13/3.13.16/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python", args: ["python3", "index.py"], footprint: 300)
        review.append(("memory-groups", chromeHelper?.key == "/Applications/Google Chrome.app" && chromeHelper?.kind == .browser && pyJob?.kind == .job,
                       "Chrome's helpers count as Chrome; a Python script counts as a job"))
        var tight = MacState(); tight.memoryPressure = "warning"; tight.swapUsedMB = 1500; tight.swapTotalMB = 3000
        let browserCard = MemoryAdvice.card([MemGroup(key: "c", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 5_500_000_000, count: 41)], mac: tight, now: now, chrome: .available(4096))
        // One Click First (Phil, 16 November 2026): Limit Chrome is recommended; closing the heaviest tabs fixes the cause
        review.append(("memory-browser", browserCard.recommended?.id == "chromelimit"
                       && browserCard.betterThanRecommended.map(\.id) == ["tabs"]
                       && browserCard.fixes.contains { $0.kind == .quitApp("/Applications/Google Chrome.app") && $0.consequence.contains("Closes all tabs") }
                       && browserCard.headline.contains("Google Chrome is using the most"), browserCard.headline))
        // Chrome's memory limit (Phil, 15 November 2026: "Yes, with the warning"): offered with the "managed" notice,
        // undoable, and recommended under One Click First (Phil, 16 November 2026: "What's the downside to Chrome saying
        // it's managed by your organization? Seems immaterial to me... I think one click first is right"); not offered when Chrome already has those settings, or for other browsers. Set and
        // removed for real on a scratch settings domain, never on Chrome's.
        let gbs: [UInt64] = [4, 8, 16, 64].map { $0 * 1_073_741_824 }
        // a quarter of memory or Chrome's use now, whichever is lower, whole GB rounded down, at least 2 GB
        let capMBs = [ChromeLimit.limitMB(memory: gbs[0], chromeUse: 3_000_000_000), ChromeLimit.limitMB(memory: gbs[1], chromeUse: 1_500_000_000),
                      ChromeLimit.limitMB(memory: gbs[2], chromeUse: 3_700_000_000), ChromeLimit.limitMB(memory: gbs[2], chromeUse: 6_000_000_000),
                      ChromeLimit.limitMB(memory: gbs[3], chromeUse: 10_000_000_000)]
        let offered = browserCard.fixes.first { $0.id == "chromelimit" }
        let chromeGroup = [MemGroup(key: "c", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 5_500_000_000, count: 41)]
        let limitedCard = MemoryAdvice.card(chromeGroup, mac: tight, now: now, chrome: .set(4096))
        let noRemove = !limitedCard.fixes.contains { $0.id == "chromelimit" } && limitedCard.explanation.contains("over its 4 GB limit")
        let driveFirst = MemoryAdvice.card([MemGroup(key: "g", name: "Google Drive", kind: .app, bundle: "/Applications/Google Drive.app", bytes: 4_700_000_000, count: 3)]
                                           + chromeGroup, mac: tight, now: now, chrome: .available(4096))
        let secondOffered = driveFirst.fixes.contains { $0.id == "chromelimit" }
        let notOffered = !MemoryAdvice.card(chromeGroup, mac: tight, now: now, chrome: .unavailable).fixes.contains { $0.id == "chromelimit" }
            && !MemoryAdvice.card([MemGroup(key: "e", name: "Microsoft Edge", kind: .browser, bundle: "/Applications/Microsoft Edge.app", bytes: 5_500_000_000, count: 41)],
                                  mac: tight, now: now, chrome: .available(4096)).fixes.contains { $0.id == "chromelimit" }
        let scratch = "io.github.thephildiamond.coolhead.selftest-chrome", scratchMark = "selftestChromeLimitMB"
        let sixteen = gbs[2]
        _ = ChromeLimit.remove(domain: scratch, marker: scratchMark)
        let didSet = ChromeLimit.set(ChromeLimit.limitMB(memory: sixteen, chromeUse: 5_000_000_000), domain: scratch, marker: scratchMark)
        let wrote = (ChromeLimit.value("TotalMemoryLimitMb", scratch) as? Int) == 4096 && (ChromeLimit.value("MemorySaverModeSavings", scratch) as? Int) == 2
            && (ChromeLimit.value("HighEfficiencyModeEnabled", scratch) as? Bool) == true
        let didRemove = ChromeLimit.remove(domain: scratch, marker: scratchMark)
        // someone else's setting: not offered, not touched
        CFPreferencesSetAppValue("MemorySaverModeSavings" as CFString, 1 as CFNumber, scratch as CFString); CFPreferencesAppSynchronize(scratch as CFString)
        let leftAlone = ChromeLimit.status(domain: scratch, marker: scratchMark) == .unavailable && !ChromeLimit.set(4096, domain: scratch, marker: scratchMark)
            && (ChromeLimit.value("MemorySaverModeSavings", scratch) as? Int) == 1 && ChromeLimit.value("TotalMemoryLimitMb", scratch) == nil
        CFPreferencesSetAppValue("MemorySaverModeSavings" as CFString, nil, scratch as CFString); CFPreferencesAppSynchronize(scratch as CFString)
        review.append(("chrome-memory-limit", capMBs == [2048, 2048, 3072, 4096, 9216]
                       && offered?.title == "Limit Chrome to 4 GB" && offered?.consequence.contains("managed by your organization") == true
                       && offered?.recommended == true && browserCard.fixes.firstIndex { $0.id == "chromelimit" } == 0
                       && noRemove && secondOffered && notOffered && didSet && wrote && didRemove && leftAlone,
                       "limits \(capMBs); offered \(offered?.title ?? "no"), also when Chrome is second \(secondOffered); once on, no Remove option and the card explains it \(noRemove); set \(didSet) wrote \(wrote) removed \(didRemove); others' settings left alone \(leftAlone)"))
        // a sync app using the most memory: quitting loses nothing, so it says so, and Pause syncing is there too
        // (noticed in the Chrome limit test, 15 November 2026: "Quit Google Drive" said "It'll ask to save first")
        let driveQuit = driveFirst.fixes.first { $0.id == "quit" }
        let drivePause = driveFirst.fixes.contains { if case .pauseSync = $0.kind { return true }; return false }
        review.append(("memory-sync-app", driveQuit?.title == "Quit Google Drive" && driveQuit?.recommended == true
                       && driveQuit?.consequence.contains("Nothing is lost") == true && drivePause,
                       "\(driveQuit?.title ?? "no quit"): \(driveQuit?.consequence ?? ""); Pause syncing offered \(drivePause)"))
        // Restart Chrome, keeping your tabs: offered for Chromium browsers among the three biggest, never recommended,
        // right before Quit (both Caution, ordered by impact), with what doesn't come back said plainly
        let restartFix = browserCard.fixes.first { $0.id == "restart" }
        let browserOrder = browserCard.fixes.map(\.id).joined(separator: " ")
        let driveOrder = driveFirst.fixes.map(\.id).joined(separator: " ")
        func card(_ name: String) -> Card {
            MemoryAdvice.card([MemGroup(key: name, name: name, kind: .browser, bundle: "/Applications/\(name).app", bytes: 5_500_000_000, count: 41)], mac: tight, now: now, chrome: .unavailable)
        }
        let edgeRestart = card("Microsoft Edge").fixes.first { $0.id == "restart" }
        let notChromium = ["Safari", "Firefox", "Arc", "Opera"].filter { card($0).fixes.contains { $0.id == "restart" } }
        let restartCard = restartFix?.title == "Restart Google Chrome, keeping your tabs"
            && restartFix?.kind == .restartBrowser("/Applications/Google Chrome.app") && restartFix?.recommended == false
            && restartFix?.consequence == "Closes and reopens Google Chrome, freeing memory it built up. Your tabs come back; Incognito windows, unsent form text, and downloads in progress don't."
            && browserOrder == "chromelimit tabs restart quit saver" && driveOrder == "quit restart quit2 chromelimit pause"
            && edgeRestart?.consequence.contains("InPrivate windows") == true && notChromium.isEmpty
            && BrowserRestart.note(.stillOpen, name: "Google Chrome").text.contains("so it wasn't reopened") && BrowserRestart.note(.stillOpen, name: "Google Chrome").failed
            && !BrowserRestart.note(.restarted(seconds: 3), name: "Google Chrome").failed
        review.append(("restart-browser-option", restartCard, "Chrome first: \(browserOrder); Chrome second: \(driveOrder); Edge \(edgeRestart != nil); offered for others \(notChromium)"))
        let dockerCard = MemoryAdvice.card([MemGroup(key: "d", name: "Docker", kind: .app, bundle: "/Applications/Docker.app", bytes: 4_000_000_000, count: 3)], mac: tight, now: now)
        let dockerQuit = dockerCard.fixes.first { $0.id == "quit" }
        review.append(("memory-app-risk", dockerQuit?.consequence.contains("Stops all containers") == true && dockerQuit?.recommended == false,
                       "Quit Docker says it stops every container, and isn't recommended"))
        var jobGroup = MemGroup(key: "job-1", name: "job", kind: .job, bundle: nil, bytes: 3_000_000_000, count: 1)
        jobGroup.evidence = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "index.py"], cwd: "/Users/x/Archive",
                                            start: now.addingTimeInterval(-3 * 3600), cores: 4)
        let jobCard = MemoryAdvice.card([jobGroup], mac: tight, now: now)
        review.append(("memory-job-stop", jobCard.fixes.contains { $0.kind == .stop && $0.consequence.contains("Frees") && $0.consequence.contains("lose up to") },
                       "a memory-heavy job can be stopped, with what that frees and costs"))
        // Phil's rule (15 November 2026): no warning offers only "wait". Every card that needs a look must have an
        // option that does something (stop, slow, quit, look up or share).
        func actionable(_ c: Card) -> Bool {
            c.fixes.contains { f in
                switch f.kind { case .wait, .guide: return false; default: return true }      // showing how isn't doing
            }
        }
        let warnings = all(now).map { f in Card.make(f.evidence, now: now, busySince: now.addingTimeInterval(-f.busyFor)) }
            .filter { $0.state == .stalled || $0.state == .unknown } + [browserCard, dockerCard, jobCard,
            MemoryAdvice.card([MemGroup(key: "m", name: "WindowServer", kind: .macOS, bundle: nil, bytes: 3_000_000_000, count: 1)], mac: tight, now: now)]
        let bare = warnings.filter { !actionable($0) }.map(\.headline)
        review.append(("no-warning-only-waits", bare.isEmpty, bare.isEmpty ? "all \(warnings.count) warnings have a real option" : "only wait: \(bare)"))
        // waiting on a card hides it until its time unless it gets worse: a "needs a look" card that becomes
        // "stuck" (or tight memory that becomes critical) outranks what was waited on
        let unknownCard = LiveCard(id: "1-unknown", pid: 1, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: [])
        let stuckCard = LiveCard(id: "1-stalled", pid: 1, card: Card(state: .stalled, headline: "", explanation: "", fixes: []), details: [])
        let memWarn = LiveCard(id: "memory-warning", pid: nil, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: [])
        let memCrit = LiveCard(id: "memory-critical", pid: nil, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: [])
        review.append(("wait-returns-only-if-worse", unknownCard.severity == 1 && stuckCard.severity == 2 && memWarn.severity == 1 && memCrit.severity == 2
                       && unknownCard.cause == stuckCard.cause, "waited at 1; returns at 2 for the same cause"))
        // Phil (15 November 2026): "why is it green if it's running warm? We should be flagging causes if the heat is
        // elevated." A busy job on a warm Mac says it's adding heat, offers running it cooler, and counts as a
        // heat cause (severity 1), so the badge is yellow; the same job on a cool Mac stays calm (severity 0).
        let job = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                  start: now.addingTimeInterval(-2 * 3600), cores: 2)
        let warmCard = Card.make(job, now: now, busySince: now.addingTimeInterval(-3600), warm: true)
        let coolCard = Card.make(job, now: now, busySince: now.addingTimeInterval(-3600), warm: false)
        let working = Card(state: .working, headline: "", explanation: "", fixes: [])
        var warmLive = LiveCard(id: "2-working", pid: 2, card: working, details: [])
        warmLive.heatCause = true
        let coolLive = LiveCard(id: "2-working", pid: 2, card: working, details: [])
        review.append(("heat-flags-causes", warmCard.explanation.contains("adding to the heat") && !coolCard.explanation.contains("heat")
                       && warmCard.fixes.contains { $0.kind == .cooler } && warmLive.severity == 1 && coolLive.severity == 0,
                       warmCard.explanation))
        // The option order (Phil, 16 November 2026: "we could label risky actions while keeping them ordered by impact
        // and grouped by action type which is more intuitive and consistent"): recommended first, and a task for you
        // gives way to a safe one-click option (One Click First); then by result (fixes the cause, eases, informs); at
        // equal result, Caution after the rest; then the older ranking. Waiting is not in the list (a clock instead).
        let shuffled = Card(state: .unknown, headline: "", explanation: "", fixes: [
            Fix(id: "share", title: "", consequence: "", kind: .share),
            Fix(id: "stop", title: "", consequence: "", kind: .stop),
            Fix(id: "wait", title: "", consequence: "", kind: .wait(now)),
            Fix(id: "quit", title: "", consequence: "", kind: .quitApp("/Applications/X.app")),
            Fix(id: "lookup", title: "", consequence: "", kind: .lookUp("x"), recommended: true),
            Fix(id: "cooler", title: "", consequence: "", kind: .cooler),
            Fix(id: "find", title: "", consequence: "", kind: .guide([]))])
        let order = shuffled.fixes.map(\.id).joined(separator: " ")
        let everyCard = all(now).map { f in Card.make(f.evidence, now: now, busySince: now.addingTimeInterval(-f.busyFor), warm: true) }
        let allSorted = everyCard.allSatisfy { c in
            let keys = c.fixes.map { [$0.recommended ? 0 : 1, -$0.result.rawValue, $0.caution ? 1 : 0, Card.rank($0)] }
            return keys == keys.sorted { $0.lexicographicallyPrecedes($1) } && !c.fixes.contains { if case .wait = $0.kind { return true }; return false }
                && c.fixes.filter(\.recommended).count <= 1 }
        review.append(("option-order", order == "cooler quit stop find lookup share" && allSorted, order))
        // Games are protected (Phil, 15 November 2026): a game is calm and never offered Run it cooler; while warm it
        // recommends lower settings; quitting warns about unsaved progress; other busy work is offered to run cooler
        let game = Evidence.sample(name: "BloonsTD6", path: "/Users/x/Library/Application Support/Steam/steamapps/common/BloonsTD6/BloonsTD6.app/Contents/MacOS/BloonsTD6",
                                   start: now.addingTimeInterval(-2 * 3600), cores: 0.6)
        let gameCalm = Card.make(game, now: now, busySince: now.addingTimeInterval(-7200))
        let gameWarm = Card.make(game, now: now, busySince: now.addingTimeInterval(-7200), warm: true)
        let rival = Card.make(job, now: now, busySince: now.addingTimeInterval(-3600), gameRunning: "BloonsTD6")
        review.append(("games-are-protected", gameCalm.state == .working && gameCalm.headline.contains("is a game") && gameCalm.recommended == nil
                       && !gameWarm.fixes.contains { $0.kind == .cooler } && gameWarm.recommended?.id == "settings"
                       && gameWarm.fixes.contains { $0.kind == .quitApp("/Users/x/Library/Application Support/Steam/steamapps/common/BloonsTD6/BloonsTD6.app") && $0.consequence.contains("Save your game") }
                       && rival.fixes.first { $0.kind == .cooler }?.consequence.contains("more power for BloonsTD6") == true
                       && rival.explanation.contains("competing with BloonsTD6"),
                       rival.explanation))
        // Chrome without quitting (Phil, 15 November 2026): a tab, an extension and the graphics process are told apart
        // by their launch arguments; a tab in the background is slowed, a tab in the browser you're using gets Energy
        // Saver instead; Close just that tab comes before Quit; the graphics process is never slowed
        let chromeApp = "/Applications/Google Chrome.app"
        let tabExe = chromeApp + "/Contents/Frameworks/Google Chrome Framework.framework/Versions/157.0.8103.51/Helpers/Google Chrome Helper (Aperitif Renderer).app/Contents/MacOS/Google Chrome Helper (Aperitif Renderer)"
        let tabE = Evidence.sample(name: "Google Chrome Helper (Aperitif Renderer)", path: tabExe, args: [tabExe, "--type=renderer", "--renderer-client-id=5"], start: now.addingTimeInterval(-3600), cores: 1.5)
        let extE = Evidence.sample(name: "Google Chrome Helper (Aperitif Renderer)", path: tabExe, args: [tabExe, "--type=renderer", "--extension-process"], start: now.addingTimeInterval(-3600), cores: 0.8)
        let gpuE = Evidence.sample(name: "Google Chrome Helper (Aperitif)", path: tabExe, args: [tabExe, "--type=gpu-process"], start: now.addingTimeInterval(-3600), cores: 0.9)
        let busy10 = now.addingTimeInterval(-600)
        let tabBack = Card.make(tabE, now: now, busySince: busy10)
        let tabFront = Card.make(tabE, now: now, busySince: busy10, frontApp: chromeApp)
        let extCard = Card.make(extE, now: now, busySince: busy10)
        let gpuCard = Card.make(gpuE, now: now, busySince: busy10)
        func ids(_ c: Card) -> String { c.fixes.map(\.id).joined(separator: " ") }
        let stopTitle = tabBack.fixes.first { (f: Fix) in f.kind == Fix.Kind.stop }?.title
        let c1 = tabBack.headline == "A Google Chrome tab is working hard." && tabBack.recommended?.title == "Run this tab cooler"
        let c2 = tabFront.recommended?.title == "Turn on Energy Saver"
        let c3 = tabBack.fixes.contains { $0.kind == Fix.Kind.openPage(chromeApp, "chrome://settings/performance") }
        let c4 = ids(tabBack).contains("closetab quit") && ids(extCard).hasSuffix("stopext quit") && stopTitle == "Close just that tab"
        // One Click First: the extension is run cooler; turning it off, which fixes the cause, is a task tagged as better
        let c5 = extCard.recommended?.kind == Fix.Kind.cooler
            && extCard.betterThanRecommended.contains { $0.kind == Fix.Kind.openPage(chromeApp, "chrome://extensions") } && extCard.headline.contains("extension")
        let c6 = gpuCard.recommended?.title == "Turn on Energy Saver" && !gpuCard.fixes.contains { $0.kind == Fix.Kind.cooler }
        let chromeOK = c1 && c2 && c3 && c4 && c5 && c6 && Card.subject(tabE) == "Google Chrome tab"
        review.append(("chrome-without-quitting", chromeOK, "background tab: \(ids(tabBack)); in front: \(tabFront.recommended?.title ?? "none"); extension: \(ids(extCard)); graphics: \(ids(gpuCard))"))
        let gd = Evidence.sample(name: "Google Drive", path: "/Applications/Google Drive.app/Contents/MacOS/Google Drive",
                                 args: ["/Applications/Google Drive.app/Contents/MacOS/Google Drive", "--single_process"],
                                 start: now.addingTimeInterval(-3 * 3600), cores: 2)
        // Battery (Phil, 15 November 2026): on battery, a heavy job (a script or tool, never an app) recommends Pause until
        // you plug in and says it's draining the battery; plugged in, it doesn't; a stuck job isn't paused
        let heavy = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                    start: now.addingTimeInterval(-2 * 3600), cores: 2)
        let steady = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "index.py"], cwd: "/Users/x/Notes",
                                     start: now.addingTimeInterval(-2 * 3600), cores: 1.2)
        let min15 = now.addingTimeInterval(-900), hour = now.addingTimeInterval(-3600)
        func pauses(_ c: Card) -> Bool { c.recommended?.kind == Fix.Kind.pauseJob }
        // Phil (15 November 2026): only the really hungry or long-running above 50% battery; any steady load below it
        let hungryAt80 = Card.make(heavy, now: now, busySince: min15, battery: 80)          // 2 cores, 15 minutes: yes
        let steadyAt80 = Card.make(steady, now: now, busySince: min15, battery: 80)         // 1.2 cores, 15 minutes: no
        let longAt80 = Card.make(steady, now: now, busySince: hour, battery: 80)            // 1.2 cores, an hour: yes
        let steadyAt40 = Card.make(steady, now: now, busySince: min15, battery: 40)         // below half: yes
        let plugged = Card.make(heavy, now: now, busySince: min15)
        let appMain = Evidence.sample(name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", start: now.addingTimeInterval(-7200), cores: 2)
        let appOnBat = Card.make(appMain, now: now, busySince: min15, battery: 30)
        let gdBat = Card.make(gd, now: now, busySince: min15, battery: 40)
        // a sync app on battery: Run it cooler (one click) is recommended, and Pause syncing is still offered
        let syncKind = gdBat.recommended?.kind == Fix.Kind.cooler && gdBat.fixes.contains { if case .pauseSync = $0.kind { return true }; return false }
        let batteryLimits = pauses(hungryAt80) && !pauses(steadyAt80) && pauses(longAt80) && pauses(steadyAt40)
        let batteryOK = batteryLimits && hungryAt80.explanation.contains("draining your battery")
            && !plugged.fixes.contains { $0.kind == Fix.Kind.pauseJob } && !appOnBat.fixes.contains { $0.kind == Fix.Kind.pauseJob } && syncKind
        review.append(("battery-pauses-jobs", batteryOK, "hungry at 80%: \(pauses(hungryAt80)), steady at 80%: \(pauses(steadyAt80)), long at 80%: \(pauses(longAt80)), steady at 40%: \(pauses(steadyAt40))"))
        // and pausing for real: a child process is frozen, then carries on, and nothing is left on the list
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["20"]
        if (try? sleeper.run()) != nil {
            let spid = sleeper.processIdentifier
            usleep(200_000)
            let pw = Watcher()
            let lc = LiveCard(id: "p", pid: spid, start: Proc.bsd(spid)?.start, card: Card(state: .working, headline: "", explanation: "", fixes: []), details: [])
            let paused = { if case .done = pw.pauseJob(lc) { return true }; return false }() && Proc.bsd(spid)?.stopped == true
            pw.resumeAllPaused(why: "selftest")
            usleep(100_000)
            let resumed = Proc.bsd(spid)?.stopped == false && pw.pausedJobs.isEmpty
            sleeper.terminate()
            review.append(("pause-and-resume", paused && resumed, "paused \(paused), resumed \(resumed)"))
        }
        // Trust (Phil, 15 November 2026): a trusted item is calm, but flagged anyway if it looks stuck, the Mac is hot,
        // or it has been busy nonstop for 8 hours, so nothing is hidden indefinitely
        let scriptJob = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                        start: now.addingTimeInterval(-3600), cores: 2)
        let fooHelper = Evidence.sample(name: "Foo Helper", path: "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper",
                                     start: now, cores: 1)
        let system = Evidence.sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores", start: now, cores: 1)
        let keys = Trust.key(scriptJob) == "script:/Users/x/Photos/export.py" && Trust.key(fooHelper) == "app:/Applications/Foo.app" && Trust.key(system) == nil
        let limits = Trust.overLimit(state: .working, thermal: "fair", busyFor: 3600) == nil
            && Trust.overLimit(state: .unknown, thermal: "nominal", busyFor: 7 * 3600) == nil
            && Trust.overLimit(state: .stalled, thermal: "nominal", busyFor: 60) == "it looks stuck"
            && Trust.overLimit(state: .working, thermal: "serious", busyFor: 60) == "your Mac is hot"
            && Trust.overLimit(state: .working, thermal: "nominal", busyFor: 9 * 3600)?.contains("8 hours") == true
        var calm = LiveCard(id: "3-unknown", pid: 3, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: [])
        calm.trusted = true
        review.append(("trust-has-limits", keys && limits && !calm.needsLook && calm.severity == 0,
                       "keys \(keys), limits \(limits), trusted card calm \(!calm.needsLook)"))
        // Run it cooler, for real, on a child process of our own (problem report, 15 November 2026: it said "macOS
        // didn't apply it" because getpriority can't report the setting; it is confirmed by scheduling priority now)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["20"]
        if (try? child.run()) != nil {
            let cpid = child.processIdentifier
            usleep(200_000)
            let lc = LiveCard(id: "t", pid: cpid, start: Proc.bsd(cpid)?.start, card: Card(state: .working, headline: "", explanation: "", fixes: []), details: [])
            let w = Watcher()
            let on = w.setCooler(lc, on: true), down = Proc.schedulingPriority(cpid) ?? -1
            let off = w.setCooler(lc, on: false), up = Proc.schedulingPriority(cpid) ?? -1
            child.terminate()
            func ok(_ o: Watcher.Outcome) -> Bool { if case .done(_) = o { return true }; return false }
            review.append(("run-it-cooler-really-works", ok(on) && ok(off) && down <= 4 && up > 4,
                           "background priority \(down), back to \(up)"))
        }
        // each feature's own checks, from its own file (Fixtures+<Feature>.swift); see `suites`
        for suite in suites { review += suite(now) }
        return quit + privacy + review + all(now).map { f in
            let c = Card.make(f.evidence, now: now, busySince: now.addingTimeInterval(-f.busyFor))
            var problems: [String] = []
            if c.state != f.expectState { problems.append("state \(c.state.rawValue), expected \(f.expectState.rawValue)") }
            if !c.headline.contains(f.expectHeadline) { problems.append("headline \"\(c.headline)\" lacks \"\(f.expectHeadline)\"") }
            if let a = f.expectAction, !(c.recommended?.title.hasPrefix(a) ?? false) {
                problems.append("recommended \"\(c.recommended?.title ?? "none")\", expected \"\(a)…\"")
            }
            return (f.id, problems.isEmpty, problems.isEmpty ? c.headline : problems.joined(separator: "; "))
        }
    }

    static func all(_ now: Date) -> [Fixture] {
        let hour: TimeInterval = 3600
        func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
        return [
            Fixture(id: "job-with-progress", evidence: .sample(
                        name: "Python", path: "/opt/homebrew/bin/python3", args: ["python3", "build.py", "index"], cwd: "/Users/x/Photo Export",
                        start: ago(2 * hour), cores: 6,
                        progress: Progress(file: "/tmp/build.log", line: "25600/26512 passages, 178.4 min, about 6 min left",
                                           done: 25600, total: 26512, unit: "passages", minutesLeft: 6, lineTime: ago(60))),
                    busyFor: 2 * hour, expectState: .working, expectHeadline: "96% done", expectAction: nil),
            Fixture(id: "job-stalled", evidence: .sample(
                        name: "python3", path: "/usr/bin/python3", args: ["python3", "train.py"], cwd: "/Users/x/Model",
                        start: ago(5 * hour), cores: 1,
                        progress: Progress(file: "/tmp/train.log", line: "120/500 epochs", done: 120, total: 500, unit: "epochs",
                                           minutesLeft: nil, lineTime: ago(2 * hour))),
                    busyFor: 5 * hour, expectState: .stalled, expectHeadline: "looks stuck", expectAction: "Stop it"),
            Fixture(id: "job-waiting", evidence: .sample(
                        name: "python3", path: "/usr/bin/python3", args: ["python3", "sync.py"], cwd: "/Users/x/Sync",
                        start: ago(hour), cores: 0, lastLine: "waiting for the compute lock (pid 999)"),
                    busyFor: 0, expectState: .waiting, expectHeadline: "waiting for another job", expectAction: nil),
            Fixture(id: "job-no-signs", evidence: .sample(
                        name: "node", path: "/opt/homebrew/bin/node", args: ["node", "server.js"], cwd: "/Users/x/Site",
                        start: ago(3 * hour), cores: 1.2),
                    busyFor: 3 * hour, expectState: .unknown, expectHeadline: "can't tell why", expectAction: "Run it cooler"),
            Fixture(id: "spotlight-normal", evidence: .sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
                                                             start: ago(48 * hour), cores: 1.5),
                    busyFor: 0.5 * hour, expectState: .working, expectHeadline: "Spotlight is indexing", expectAction: nil),
            Fixture(id: "spotlight-long", evidence: .sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
                                                           start: ago(48 * hour), cores: 1.5),
                    busyFor: 5 * hour, expectState: .unknown, expectHeadline: "longer than usual", expectAction: "Look it up"),
            Fixture(id: "kernel-task-long", evidence: .sample(name: "kernel_task", path: nil, start: ago(72 * hour), cores: 2, pid: 0),
                    busyFor: 2 * hour, expectState: .unknown, expectHeadline: "keeping the chip cool",
                    expectAction: "Find what is heating the Mac"),
            Fixture(id: "browser-tab", evidence: .sample(
                        name: "Google Chrome Helper (Renderer)",
                        path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                        start: ago(4 * hour), cores: 1),
                    busyFor: hour, expectState: .unknown, expectHeadline: "A Google Chrome tab", expectAction: "Find the busy tab"),
            Fixture(id: "docker-vm", evidence: .sample(name: "com.docker.virtualization",
                                                      path: "/Applications/Docker.app/Contents/MacOS/com.docker.virtualization",
                                                      start: ago(10 * hour), cores: 1),
                    busyFor: 10 * hour, expectState: .working, expectHeadline: "Docker's virtual machine is running. That's normal.", expectAction: nil),
        ]
    }
}

extension Evidence {
    /// A made-up process for examples and tests.
    static func sample(name: String, path: String?, args: [String] = [], cwd: String? = nil, start: Date, cores: Double,
                       progress: Progress? = nil, lastLine: String? = nil, pid: pid_t = 99999) -> Evidence {
        Evidence(pid: pid, name: name, path: path, args: args, cwd: cwd, start: start, mine: true, coresNow: cores,
                 coresAverage: cores, performanceShare: nil, memoryBytes: 500_000_000, ancestors: [], writing: [], locks: [],
                 progress: progress, bytesWrittenDuringSample: 0, lastOutput: progress?.lineTime, lastLine: lastLine ?? progress?.line,
                 savesAsItGoes: false, workStart: start)
    }
}

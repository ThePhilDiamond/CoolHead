import Foundation

/// Recorded examples and the card each should produce. `coolhead selftest` runs them; CI runs it on every pull request.
/// Add one with every catalogue entry or rule you change (see docs/DIAGNOSIS.md).
public struct Fixture {
    public let id: String
    let evidence: Evidence
    let busyFor: TimeInterval
    let expectState: JobState
    let expectHeadline: String          // a phrase the headline must contain
    let expectAction: String?   // the start of the recommended fix's title

    /// Runs every example; returns (id, passed, what happened).
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
        review.append(("F18-name-needs-macos-path", Pattern.match(name: "bird", path: "/Users/x/bin/bird") == nil
                       && Pattern.match(name: "bird", path: "/System/Library/PrivateFrameworks/CloudDocsDaemon.framework/Versions/A/Support/bird") != nil,
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
        let browserCard = MemoryAdvice.card([MemGroup(key: "c", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 5_500_000_000, count: 41)], mac: tight, now: now)
        review.append(("memory-browser", browserCard.recommended?.title.hasPrefix("Close Google Chrome's heaviest tabs") == true
                       && browserCard.fixes.contains { $0.kind == .quitApp("/Applications/Google Chrome.app") && $0.consequence.contains("Closes all tabs") }
                       && browserCard.headline.contains("Google Chrome is using the most"), browserCard.headline))
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
            c.fixes.contains { f in if case .wait = f.kind { return false }; return f.kind != .info }
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
        // Phil (15 November 2026), the option order, locked in: recommended first; then options you can undo, most
        // helpful first; then options that close or lose something, least loss first; then sharing. Waiting is not
        // in the list (a clock in the card's corner instead).
        let shuffled = Card(state: .unknown, headline: "", explanation: "", fixes: [
            Fix(id: "share", title: "", consequence: "", kind: .share),
            Fix(id: "stop", title: "", consequence: "", kind: .stop),
            Fix(id: "wait", title: "", consequence: "", kind: .wait(now)),
            Fix(id: "quit", title: "", consequence: "", kind: .quitApp("/Applications/X.app")),
            Fix(id: "lookup", title: "", consequence: "", kind: .lookUp("x"), recommended: true),
            Fix(id: "cooler", title: "", consequence: "", kind: .cooler),
            Fix(id: "find", title: "", consequence: "", kind: .info)])
        let order = shuffled.fixes.map(\.id).joined(separator: " ")
        let everyCard = all(now).map { f in Card.make(f.evidence, now: now, busySince: now.addingTimeInterval(-f.busyFor), warm: true) }
        let allSorted = everyCard.allSatisfy { c in
            c.fixes.map(Card.rank) == c.fixes.map(Card.rank).sorted() && !c.fixes.contains { if case .wait = $0.kind { return true }; return false }
                && c.fixes.filter(\.recommended).count <= 1 }
        review.append(("option-order", order == "lookup cooler find quit stop share" && allSorted, order))
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
                    busyFor: 3 * hour, expectState: .unknown, expectHeadline: "can't tell why", expectAction: "Look it up"),
            Fixture(id: "spotlight-normal", evidence: .sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
                                                             start: ago(48 * hour), cores: 1.5),
                    busyFor: 0.5 * hour, expectState: .working, expectHeadline: "Spotlight is indexing", expectAction: nil),
            Fixture(id: "spotlight-long", evidence: .sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
                                                           start: ago(48 * hour), cores: 1.5),
                    busyFor: 5 * hour, expectState: .unknown, expectHeadline: "longer than usual", expectAction: "Look it up"),
            Fixture(id: "kernel-task-long", evidence: .sample(name: "kernel_task", path: nil, start: ago(72 * hour), cores: 2),
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
                       progress: Progress? = nil, lastLine: String? = nil) -> Evidence {
        Evidence(pid: 99999, name: name, path: path, args: args, cwd: cwd, start: start, mine: true, coresNow: cores,
                 coresAverage: cores, performanceShare: nil, memoryBytes: 500_000_000, ancestors: [], writing: [], locks: [],
                 progress: progress, bytesWrittenDuringSample: 0, lastOutput: progress?.lineTime, lastLine: lastLine ?? progress?.line,
                 savesAsItGoes: false, workStart: start)
    }
}

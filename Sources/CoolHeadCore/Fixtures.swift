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
        let privacy = [("case-report-leaks-nothing", found.isEmpty, found.isEmpty ? "no private detail in the report" : "leaked: \(found)"),
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
                    busyFor: 2 * hour, expectState: .working, expectHeadline: "96% done", expectAction: "Do nothing; check back"),
            Fixture(id: "job-stalled", evidence: .sample(
                        name: "python3", path: "/usr/bin/python3", args: ["python3", "train.py"], cwd: "/Users/x/Model",
                        start: ago(5 * hour), cores: 1,
                        progress: Progress(file: "/tmp/train.log", line: "120/500 epochs", done: 120, total: 500, unit: "epochs",
                                           minutesLeft: nil, lineTime: ago(2 * hour))),
                    busyFor: 5 * hour, expectState: .stalled, expectHeadline: "looks stuck", expectAction: "Stop it"),
            Fixture(id: "job-waiting", evidence: .sample(
                        name: "python3", path: "/usr/bin/python3", args: ["python3", "sync.py"], cwd: "/Users/x/Sync",
                        start: ago(hour), cores: 0, lastLine: "waiting for the compute lock (pid 999)"),
                    busyFor: 0, expectState: .waiting, expectHeadline: "waiting for another job", expectAction: "Do nothing"),
            Fixture(id: "job-no-signs", evidence: .sample(
                        name: "node", path: "/opt/homebrew/bin/node", args: ["node", "server.js"], cwd: "/Users/x/Site",
                        start: ago(3 * hour), cores: 1.2),
                    busyFor: 3 * hour, expectState: .unknown, expectHeadline: "Can't tell", expectAction: "Look it up"),
            Fixture(id: "spotlight-normal", evidence: .sample(name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
                                                             start: ago(48 * hour), cores: 1.5),
                    busyFor: 0.5 * hour, expectState: .working, expectHeadline: "Spotlight is indexing", expectAction: "Do nothing"),
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
                    busyFor: hour, expectState: .unknown, expectHeadline: "A tab or extension in Google Chrome", expectAction: "Find it"),
            Fixture(id: "docker-vm", evidence: .sample(name: "com.docker.virtualization",
                                                      path: "/Applications/Docker.app/Contents/MacOS/com.docker.virtualization",
                                                      start: ago(10 * hour), cores: 1),
                    busyFor: 10 * hour, expectState: .working, expectHeadline: "keeps running after they stop.", expectAction: "Do nothing"),
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

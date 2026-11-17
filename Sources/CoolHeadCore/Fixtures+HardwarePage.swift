import Foundation

/// Checks for the Hardware tool's page (see HardwarePage.swift): the verdict puts the worst finding first and never
/// mentions the battery (it has its own page), how it's running follows macOS's thermal state and the fans, the figures
/// cover each part that can be read, one crash restart is explained in plain words with what to do, and the status line
/// gives the time of the last crash restart this week, or the drive's wear when there was none.
extension Fixture {
    static func hardwarePageChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func report(_ change: (inout HardwareReport) -> Void) -> HardwareReport {
            var r = HardwarePage.sample(now: now); change(&r); return r
        }
        let dayAgo = now.addingTimeInterval(-86400)
        var serviceBattery = BatteryHealth(); serviceBattery.condition = "Service Recommended"

        // the verdict, worst first: a drive fault outranks crash restarts; a battery needing service isn't this page's
        let cases: [(String, HardwareReport)] = [
            ("Hardware looks healthy", report { $0.battery = serviceBattery }),
            ("Drive well worn", report { $0.drive?.percentUsed = 85 }),
            ("A port was overloaded", report { $0.ports = [PortErrors(name: "USB-C port 1", overCurrent: 2)] }),
            ("One crash restart", report { $0.crashes = CrashRestarts(lastDate: dayAgo, recent: [dayAgo]) }),
            ("Drive errors", report { $0.drive?.mediaErrors = 3 }),
            ("Crash restarts", report { $0.crashes = CrashRestarts(lastDate: dayAgo, recent: [dayAgo, dayAgo]) }),
            ("Drive needs a look", report { $0.drive?.criticalWarning = 1; $0.crashes = CrashRestarts(recent: [dayAgo, dayAgo]) }),
        ]
        let verdicts = cases.map { HardwarePage.verdict($0.1, now: now) }
        let issue = HardwarePage.verdict(HardwarePage.sample("issue", now: now), now: now).meaning
        let v1 = zip(cases, verdicts).allSatisfy { $0.0.0 == $0.1.title }
            && verdicts.map(\.level) == [0, 1, 1, 1, 1, 2, 2]
            && issue == "WindowServer, the part of macOS that draws the screen, stopped responding, so macOS restarted. That's usually software, not hardware. A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try."
            && !verdicts.contains { $0.meaning.lowercased().contains("battery") }
            && HardwarePage.verdict(report { $0.drive = nil }, now: now).meaning == "No warnings from the ports, and no crash restarts this week."
        review.append(("hardware-page-verdict", v1, verdicts.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // how it's running: macOS's four thermal states, the snowflake melting then burning; fans said in plain words
        let states = ["nominal", "fair", "serious", "critical"].map { HardwarePage.running(thermal: $0, fans: .rpm([1_200, 1_250])) }
        let r1 = states.map(\.icon) == [0, 1, 1, 2]
            && states.map(\.title) == ["Keeping its cool", "Warming up", "Running hot", "Too hot"]
            && states[0].fans == "Fans at 1,200 rpm and 1,250 rpm, barely audible."
            && HardwarePage.running(thermal: "nominal", fans: .rpm([4_800])).fans == "Fan at 4,800 rpm, working hard."
            && HardwarePage.running(thermal: "nominal", fans: HardwarePage.Fans.none).fans == "No fans: it slows itself down to stay cool, silently."
            && HardwarePage.running(thermal: "nominal", fans: nil).fans == nil
        review.append(("hardware-page-running", r1, states.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // the figures: drive, memory, crashes, ports; no battery; each part's level follows its own finding
        let tiles = HardwarePage.tiles(report { _ in }, memoryGB: 16, now: now)
        let worn = HardwarePage.tiles(report { $0.drive?.percentUsed = 85; $0.crashes = CrashRestarts(recent: [dayAgo]); $0.ports = [PortErrors(name: "the MagSafe port", overCurrent: 1)] }, memoryGB: 16, now: now)
        let t1 = tiles.map(\.part) == [.drive, .memory, .crashes, .ports]
            && tiles.map(\.value) == ["3%", "16 GB", "0", "0"] && tiles.allSatisfy { $0.level == 0 }
            && worn.map(\.level) == [1, 0, 1, 1]
            && HardwarePage.tiles(report { $0.drive = nil }, memoryGB: 8, now: now).count == 3
        review.append(("hardware-page-tiles", t1, worn.map { "\($0.value) \($0.unit)" }.joined(separator: ", ")))

        // the status line: when the last crash restart this week was (its cause is in the verdict), else the drive's wear
        let crashed = HardwarePage.status(HardwarePage.sample("issue", now: now), now: now)
        let calm = HardwarePage.status(report { _ in }, now: now)
        let noDrive = HardwarePage.status(report { $0.drive = nil }, now: now)
        let s1 = crashed.text.hasPrefix("Last crash restart") && crashed.detail == nil && crashed.level == 1
            && calm.text.hasPrefix("About ") && calm.text.hasSuffix(" written") && calm.detail == "on for 2,140 hours"
            && noDrive.text == "Cool Head can't read the drive's health"
        review.append(("hardware-page-status", s1, [crashed, calm, noDrive].map { $0.text + ($0.detail.map { " / " + $0 } ?? "") }.joined(separator: " | ")))
        return review
    }
}

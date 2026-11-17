import Foundation

/// Checks for the Hardware tool's page (see HardwarePage.swift): the verdict puts the worst finding first, the figures
/// cover each part that can be read (three on a Mac with no battery), and the status line names the last crash restart
/// this week, or the drive's wear when there was none.
extension Fixture {
    static func hardwarePageChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func report(_ change: (inout HardwareReport) -> Void) -> HardwareReport {
            var r = HardwarePage.sample(now: now); change(&r); return r
        }
        let dayAgo = now.addingTimeInterval(-86400)

        // the verdict, worst first: a drive fault outranks a battery needing service, which outranks crash restarts
        let cases: [(String, HardwareReport)] = [
            ("Hardware looks healthy", report { _ in }),
            ("Drive well worn", report { $0.drive?.percentUsed = 85 }),
            ("A port was overloaded", report { $0.ports = [PortErrors(name: "USB-C port 1", overCurrent: 2)] }),
            ("One crash restart", report { $0.crashes = CrashRestarts(lastDate: dayAgo, recent: [dayAgo]) }),
            ("Drive errors", report { $0.drive?.mediaErrors = 3 }),
            ("Crash restarts", report { $0.crashes = CrashRestarts(lastDate: dayAgo, recent: [dayAgo, dayAgo]) }),
            ("Battery needs service", report { $0.battery?.condition = "Service Recommended"; $0.crashes = CrashRestarts(recent: [dayAgo, dayAgo]) }),
            ("Drive needs a look", report { $0.drive?.criticalWarning = 1; $0.battery?.condition = "Service Recommended" }),
        ]
        let verdicts = cases.map { HardwarePage.verdict($0.1, now: now) }
        let v1 = zip(cases, verdicts).allSatisfy { $0.0.0 == $0.1.title }
            && verdicts.map(\.level) == [0, 1, 1, 1, 1, 2, 2, 2]
            && HardwarePage.verdict(report { $0.battery = nil }, now: now).meaning == "No warnings from the drive or the ports, and no crash restarts this week."
        review.append(("hardware-page-verdict", v1, verdicts.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // the figures: four with a battery, three without; each part's level follows its own finding
        let tiles = HardwarePage.tiles(report { _ in }, now: now)
        let worn = HardwarePage.tiles(report { $0.drive?.percentUsed = 85; $0.battery?.maxCapacity = 76; $0.crashes = CrashRestarts(recent: [dayAgo]); $0.ports = [PortErrors(name: "the MagSafe port", overCurrent: 1)] }, now: now)
        let t1 = tiles.map(\.part) == [.drive, .battery, .crashes, .ports]
            && tiles.map(\.value) == ["3%", "92%", "0", "0"] && tiles.allSatisfy { $0.level == 0 }
            && worn.map(\.level) == [1, 1, 1, 1]
            && HardwarePage.tiles(report { $0.battery = nil }, now: now).count == 3
        review.append(("hardware-page-tiles", t1, worn.map { "\($0.value) \($0.unit)" }.joined(separator: ", ")))

        // the status line: the last crash restart this week with its cause, else the drive's wear
        let crashed = HardwarePage.status(HardwarePage.sample("issue", now: now), now: now)
        let calm = HardwarePage.status(report { _ in }, now: now)
        let noDrive = HardwarePage.status(report { $0.drive = nil }, now: now)
        let s1 = crashed.text.hasPrefix("Last crash restart") && crashed.detail == "WindowServer stopped responding" && crashed.level == 1
            && calm.text.hasPrefix("About ") && calm.text.hasSuffix(" written") && calm.detail == "on for 2,140 hours"
            && noDrive.text == "Cool Head can't read the drive's health"
        review.append(("hardware-page-status", s1, [crashed, calm, noDrive].map { $0.text + ($0.detail.map { " / " + $0 } ?? "") }.joined(separator: " | ")))
        return review
    }
}

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
        let v1 = zip(cases, verdicts).allSatisfy { $0.0.0 == $0.1.title }
            && verdicts.map(\.level) == [0, 1, 1, 1, 1, 2, 2]
            && !verdicts.contains { $0.meaning.lowercased().contains("battery") }
            && HardwarePage.verdict(report { $0.drive = nil }, now: now).meaning == "No warnings from the ports, and no crash restarts this week."
        review.append(("hardware-page-verdict", v1, verdicts.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // each part with everything about it together: the drive's wear, writes, hours and temperature; a crash's time,
        // cause and what to do; which port and what happened
        let calm = HardwarePage.parts(report { _ in }, now: now)
        let issue = HardwarePage.parts(HardwarePage.sample("issue", now: now), now: now)
        let ported = HardwarePage.parts(report { $0.ports = [PortErrors(name: "the MagSafe port", overCurrent: 2)] }, now: now)
        let p1 = calm.map(\.kind) == [.drive, .crashes, .ports] && calm.map(\.level) == [0, 0, 0]
            && calm[0].value == "3% of its life used" && calm[0].lines == ["About 18 TB written over 2,140 hours, now at 34°C.", "Time Machine is set up to back it up."]
            && issue[0].lines.last == "Time Machine isn't set up, so nothing backs this drive up."
            && calm[1].value == "None this week" && calm[1].lines.isEmpty && calm[2].value == "No errors"
            && issue[0].level == 1 && issue[1].value == "1 this week" && issue[1].level == 1
            && issue[1].lines.count == 3 && issue[1].lines[0].hasPrefix("Last one ")
            && issue[1].lines[1] == "WindowServer, the part of macOS that draws the screen, stopped responding, so macOS restarted. That's usually software, not hardware."
            && issue[1].lines[2] == "A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try."
            && ported[2].value == "2 errors" && ported[2].lines == ["The MagSafe port: a device asked for too much power twice."] && ported[2].level == 1
            && HardwarePage.parts(report { $0.drive = nil }, now: now).count == 2
        review.append(("hardware-page-parts", p1, (calm + issue + ported).map { "\($0.name): \($0.value)" + ($0.lines.isEmpty ? "" : " / " + $0.lines.joined(separator: " ")) }.joined(separator: " | ")))

        // how it's running: macOS's four thermal states, the snowflake melting then burning; fans said in plain words
        let states = ["nominal", "fair", "serious", "critical"].map { HardwarePage.running(thermal: $0, fans: .rpm([1_200, 1_250])) }
        let r1 = states.map(\.icon) == [0, 1, 1, 2]
            && states.map(\.title) == ["Keeping its cool", "Warming up", "Running hot", "Too hot"]
            && states[0].fans == "Fans at 1,200 rpm and 1,250 rpm, barely audible."
            && HardwarePage.running(thermal: "nominal", fans: .rpm([4_800])).fans == "Fan at 4,800 rpm, working hard."
            && HardwarePage.running(thermal: "nominal", fans: HardwarePage.Fans.none).fans == "No fans: it slows itself down to stay cool, silently."
            && HardwarePage.running(thermal: "nominal", fans: nil).fans == nil
        review.append(("hardware-page-running", r1, states.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // the gauges: a percentage each, coloured by level; memory by macOS's own pressure, not "memory used"
        let g = [HardwarePage.chip(busy: 0.2), HardwarePage.chip(busy: 0.6), HardwarePage.chip(busy: 0.9),
                 HardwarePage.memory(freePercent: 58, pressure: "normal"), HardwarePage.memory(freePercent: 22, pressure: "warning"),
                 HardwarePage.memory(freePercent: 8, pressure: "critical")]
        let g1 = g.map(\.level) == [0, 1, 2, 0, 1, 2] && g.map(\.percent) == [20, 60, 90, 42, 78, 92]
        review.append(("hardware-page-gauges", g1, g.map { "\($0.name) \($0.percent)%" }.joined(separator: ", ")))
        return review
    }
}

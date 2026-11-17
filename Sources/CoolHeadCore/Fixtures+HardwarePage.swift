import Foundation

/// Checks for the Hardware tool's page (see HardwarePage.swift): the verdict puts the worst finding first and never
/// mentions the battery (it has its own page), how it's running follows the same level as the menu bar icon and names its worst cause, the figures
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
            ("Drive and ports look healthy", report { $0.battery = serviceBattery }),
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
            && HardwarePage.verdict(report { $0.drive = nil }, now: now).title == "Ports look healthy"
            && HardwarePage.verdict(report { $0.drive = nil }, now: now).meaning.hasSuffix("The drive's health couldn't be read.")
        review.append(("hardware-page-verdict", v1, verdicts.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // each part with everything about it together: the drive's wear, writes, hours and temperature; a crash's time,
        // cause and what to do; which port and what happened
        let calm = HardwarePage.parts(report { _ in }, now: now)
        let issue = HardwarePage.parts(HardwarePage.sample("issue", now: now), now: now)
        let ported = HardwarePage.parts(report { $0.ports = [PortErrors(name: "the MagSafe port", overCurrent: 2)] }, now: now)
        // in parts, so the compiler checks each quickly (one long chain timed out on GitHub's build machine)
        let tiles: [String] = calm[0].tiles.map { $0.value + " " + $0.unit }
        let noDrive: [String] = HardwarePage.parts(report { $0.drive = nil }, now: now).map(\.value)
        var p1 = calm.map(\.kind) == [.drive, .crashes, .ports, .temps] && calm.map(\.level) == [0, 0, 0, 0]
        p1 = p1 && calm[0].value == "Healthy" && calm[0].lines.isEmpty && calm[0].backup == "Time Machine is set up to back it up."
        p1 = p1 && tiles == ["3% life used", "18 TB written", "2,140 hours on"]
        let temps: [String] = calm[3].tiles.map { $0.value + " " + $0.unit }
        p1 = p1 && temps == ["55°C chip", "31°C battery", "34°C drive"] && calm[3].value == "Normal"
        var hot = HardwarePage.sample(now: now); hot.battery?.temperatureC = 46; hot.chipC = nil
        let hotTemps = HardwarePage.parts(hot, now: now).last
        p1 = p1 && hotTemps?.value == "Hot" && hotTemps?.tiles.map(\.unit) == ["battery", "drive"]
        p1 = p1 && issue[0].value == "Well worn" && issue[0].tiles.first?.level == 1
        p1 = p1 && issue[0].backup == "Time Machine isn't set up, so nothing backs this drive up."
        p1 = p1 && calm[1].value == "None this week" && calm[1].lines.isEmpty && calm[2].value == "No errors"
        p1 = p1 && issue[0].level == 1 && issue[1].value == "1 this week" && issue[1].level == 1
        p1 = p1 && issue[1].lines.count == 3 && issue[1].lines[0].hasPrefix("Last one ")
        p1 = p1 && issue[1].lines[1] == "WindowServer, the part of macOS that draws the screen, stopped responding, so macOS restarted. That's usually software, not hardware."
        p1 = p1 && issue[1].lines[2] == "A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try."
        p1 = p1 && ported[2].value == "2 errors" && ported[2].lines == ["The MagSafe port: a device asked for too much power twice."] && ported[2].level == 1
        p1 = p1 && noDrive == ["Not read", "None this week", "No errors", "Normal"]
        func describe(_ p: HardwarePage.Part) -> String {
            var t = "\(p.name): \(p.value)"
            if !p.tiles.isEmpty { t += " [" + p.tiles.map { $0.value + " " + $0.unit }.joined(separator: ", ") + "]" }
            if !p.lines.isEmpty { t += " / " + p.lines.joined(separator: " ") }
            if let b = p.backup { t += " / " + b }
            return t
        }
        review.append(("hardware-page-parts", p1, (calm + issue + ported).map(describe).joined(separator: " | ")))

        // how it's running: the same level as the menu bar icon. Whole while nothing slows it and nothing needs acting
        // on, even when warm; melting when macOS slows it a little, memory is tight, or something needs a look; in flames
        // when macOS slows it hard, memory is very tight, or something is stuck. The worst cause is named. Fans in words.
        typealias S = HardwarePage.Signs
        let cases2: [(String, S, Int, String)] = [
            ("nominal", S(), 0, "A normal temperature, at full speed."),
            ("fair", S(), 0, "Warm, but at full speed."),
            ("nominal", S(memoryTight: true), 1, "Memory is tight, so it's slower than it could be."),
            ("nominal", S(toWatch: 1), 1, "A normal temperature, at full speed. The card below needs a look."),
            ("fair", S(toWatch: 3), 1, "Warm, but at full speed. The cards below need a look."),
            ("fair", S(addingHeat: true), 1, "It's warm, and something below is adding to it."),
            ("serious", S(toWatch: 2), 1, "macOS is slowing it a little to cool it down."),
            ("nominal", S(resumeSync: true), 1, "It's time to resume syncing."),
            ("nominal", S(stuck: 1, memoryTight: true), 2, "It isn't making progress. Its card below says what to try."),
            ("serious", S(memoryCritical: true), 2, "Memory is very tight, so everything is slower. The card below says what's using it."),
            ("critical", S(), 2, "macOS is slowing it hard to cool it down. Give it a break on a hard surface, out of the sun."),
        ]
        let states = cases2.map { HardwarePage.running(thermal: $0.0, signs: $0.1, fans: .rpm([1_200, 1_250])) }
        let icons: [Int] = cases2.map { $0.2 }, meanings: [String] = cases2.map { $0.3 }
        var r1 = states.map(\.icon) == icons && states.map(\.meaning) == meanings
        r1 = r1 && states[0].fans == "Fans at 1,200 rpm and 1,250 rpm, barely audible."
            && HardwarePage.running(thermal: "nominal", fans: .rpm([4_800])).fans == "Fan at 4,800 rpm, working hard."
            && HardwarePage.running(thermal: "nominal", fans: HardwarePage.Fans.none).fans == "No fans: it slows itself down to stay cool, silently."
            && HardwarePage.running(thermal: "nominal", fans: nil).fans == nil
        review.append(("hardware-page-running", r1, zip(cases2, states).map { "\($0.0.0) \($0.1.icon): \($0.1.meaning)" }.joined(separator: " | ")))

        // the gauges: a percentage each, coloured by level; memory by macOS's own pressure, not "memory used"
        let g = [HardwarePage.chip(busy: 0.2), HardwarePage.chip(busy: 0.6), HardwarePage.chip(busy: 0.9),
                 HardwarePage.memory(freePercent: 58, pressure: "normal"), HardwarePage.memory(freePercent: 22, pressure: "warning"),
                 HardwarePage.memory(freePercent: 8, pressure: "critical")]
        let g1 = g.map(\.level) == [0, 1, 2, 0, 1, 2] && g.map(\.percent) == [20, 60, 90, 42, 78, 92]
        review.append(("hardware-page-gauges", g1, g.map { "\($0.name) \($0.percent)%" }.joined(separator: ", ")))
        return review
    }
}

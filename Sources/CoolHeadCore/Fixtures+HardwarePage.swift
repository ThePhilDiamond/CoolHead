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
        let calmAll = HardwarePage.parts(report { _ in }, now: now)
        // Temperatures comes first; the checks below by position are of the other parts
        let calm = calmAll.filter { $0.kind != .temps }
        let issue = HardwarePage.parts(HardwarePage.sample("issue", now: now), now: now).filter { $0.kind != .temps }
        let ported = HardwarePage.parts(report { $0.ports = [PortErrors(name: "the MagSafe port", overCurrent: 2)] }, now: now).filter { $0.kind != .temps }
        // in parts, so the compiler checks each quickly (one long chain timed out on GitHub's build machine)
        let tiles: [String] = calm[0].tiles.map { $0.value + " " + $0.unit }
        let noDrive: [String] = HardwarePage.parts(report { $0.drive = nil }, now: now).map(\.value)
        var p1 = calmAll.map(\.kind) == [.temps, .drive, .crashes, .ports] && calmAll.map(\.level) == [0, 0, 0, 0]
        p1 = p1 && calm[0].value == "Healthy" && calm[0].lines.isEmpty && calm[0].backup == "Time Machine is set up to back it up."
        p1 = p1 && tiles == ["3% life used", "18 TB written", "2,140 hours on"]
        let temps: [String] = calmAll[0].tiles.map { $0.value + " " + $0.unit }
        p1 = p1 && temps == ["\(Fmt.temperature(55)) chip", "\(Fmt.temperature(31)) battery", "\(Fmt.temperature(34)) drive"] && calmAll[0].value == "Normal" && calmAll[0].lines.isEmpty
        var hot = HardwarePage.sample(now: now); hot.battery?.temperatureC = 46; hot.chipC = nil
        let hotTemps = HardwarePage.parts(hot, now: now).first
        p1 = p1 && hotTemps?.value == "Hot" && hotTemps?.tiles.map(\.unit) == ["battery", "drive"]
        p1 = p1 && issue[0].value == "Well worn" && issue[0].tiles.first?.level == 1
        p1 = p1 && issue[0].backup == "Time Machine isn't set up, so nothing backs this drive up."
        p1 = p1 && calm[1].value == "None this week" && calm[1].lines.isEmpty && calm[2].value == "No errors"
        p1 = p1 && issue[0].level == 1 && issue[1].value == "1 this week" && issue[1].level == 1
        p1 = p1 && issue[1].lines.count == 3 && issue[1].lines[0].hasPrefix("Last one ")
        p1 = p1 && issue[1].lines[1] == "WindowServer, the part of macOS that draws the screen, stopped responding, so macOS restarted. Software usually causes this, not hardware."
        p1 = p1 && issue[1].lines[2] == "A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try."
        p1 = p1 && ported[2].value == "2 errors" && ported[2].lines == ["The MagSafe port: a device asked for too much power twice."] && ported[2].level == 1
        p1 = p1 && noDrive == ["Normal", "Not read", "None this week", "No errors"]
        // in the unit this Mac is set to, either way
        p1 = p1 && Fmt.temperature(55, fahrenheit: false) == "55°C" && Fmt.temperature(55, fahrenheit: true) == "131°F"
            && Fmt.temperature(-1.4, fahrenheit: false) == "-1°C" && Fmt.temperature(100, fahrenheit: true) == "212°F"
        func describe(_ p: HardwarePage.Part) -> String {
            var t = "\(p.name): \(p.value)"
            if !p.tiles.isEmpty { t += " [" + p.tiles.map { $0.value + " " + $0.unit }.joined(separator: ", ") + "]" }
            if !p.lines.isEmpty { t += " / " + p.lines.joined(separator: " ") }
            if let b = p.backup { t += " / " + b }
            return t
        }
        review.append(("hardware-page-parts", p1, (calmAll + issue + ported).map(describe).joined(separator: " | ")))

        // how it's running: the same level as the menu bar icon. Whole while nothing slows it and nothing needs acting
        // on, even when warm; melting when macOS slows it a little, memory is tight, or something needs a look; in flames
        // when macOS slows it hard, memory is very tight, or something is stuck. The worst cause is named. Fans in words.
        typealias S = HardwarePage.Signs
        let cases2: [(String, S, Int, String)] = [
            ("nominal", S(), 0, "A normal temperature, at full speed."),
            ("fair", S(), 0, "Warm, but at full speed."),
            ("nominal", S(memoryTight: true), 1, "Apps and programs are using almost all of your Mac's memory, so it is slower than it could be."),
            ("nominal", S(toWatch: 1), 1, "A normal temperature, at full speed."),
            ("fair", S(toWatch: 3), 1, "Warm, but at full speed."),
            ("fair", S(addingHeat: true), 1, "Your Mac is warm, and something running is adding to the heat."),
            ("serious", S(toWatch: 2), 1, "macOS is slowing your Mac a little to cool it."),
            ("nominal", S(resumeSync: true), 1, "It's time to resume syncing."),
            ("nominal", S(stuck: 1, memoryTight: true), 2, "A program isn't making progress."),
            ("serious", S(memoryCritical: true), 2, "Apps and programs are using all of your Mac's memory, so everything is slower."),
            ("critical", S(), 2, "macOS is slowing your Mac a lot to cool it. Give it a break on a hard surface, out of the sun."),
        ]
        let states = cases2.map { HardwarePage.running(thermal: $0.0, signs: $0.1, fans: .rpm([1_200, 1_250])) }
        let icons: [Int] = cases2.map { $0.2 }, meanings: [String] = cases2.map { $0.3 }
        var r1 = states.map(\.icon) == icons && states.map(\.meaning) == meanings
        r1 = r1 && states[0].fans == "Fans at 1,200 rpm and 1,250 rpm, barely audible."
            && HardwarePage.running(thermal: "nominal", fans: .rpm([4_800])).fans == "Fan at 4,800 rpm, working hard."
            && HardwarePage.running(thermal: "nominal", fans: HardwarePage.Fans.none).fans == "No fans: your Mac slows itself down to stay cool, silently."
            && HardwarePage.running(thermal: "nominal", fans: nil).fans == nil
        review.append(("hardware-page-running", r1, zip(cases2, states).map { "\($0.0.0) \($0.1.icon): \($0.1.meaning)" }.joined(separator: " | ")))

        // the dials: a step each, never an amount. Chip load by its share over about 30 seconds (Light, Medium from half,
        // Heavy from 80%; "…" and no needle before a reading), memory by macOS's own pressure (OK, Tight, Full); the needle
        // in the middle of its level's zone; the labels under them
        let chips = [0.2, 0.49, 0.5, 0.79, 0.8, 1.0].map { HardwarePage.chip(busy: $0) } + [HardwarePage.chip(busy: nil)]
        let mems = ["normal", "warning", "critical"].map { HardwarePage.memory(pressure: $0) }
        let dialTemps = [HardwarePage.heat(chipC: 55, thermal: "nominal"), HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 46),
                     HardwarePage.heat(chipC: 55, thermal: "nominal", driveC: 72)].compactMap { $0 }
        let chipLevels: [Int] = chips.map { $0.level }, chipWords: [String] = chips.map { $0.text }
        let memLevels: [Int] = mems.map { $0.level }, memWords: [String] = mems.map { $0.text }
        let needles: [Double?] = chips.map { $0.needle } + mems.map { $0.needle }
        let wantNeedles: [Double?] = [1.0 / 6, 1.0 / 6, 0.5, 0.5, 5.0 / 6, 5.0 / 6, nil, 1.0 / 6, 0.5, 5.0 / 6]
        let labels: [String] = ([chips[0], mems[0]] + dialTemps).map { $0.label }
        let dg1 = chipLevels == [0, 0, 1, 1, 2, 2, -1] && chipWords == ["Light", "Light", "Medium", "Medium", "Heavy", "Heavy", "…"]
        let dg2 = memLevels == [0, 1, 2] && memWords == ["OK", "Tight", "Full"] && needles == wantNeedles
        let dg3 = labels == ["Chip load", "Memory", "Chip temp", "Battery temp", "Drive temp"]
        review.append(("dial-steps", dg1 && dg2 && dg3, (chips + mems).map { "\($0.label) \($0.text) at \($0.needle.map { String(format: "%.2f", $0) } ?? "none")" }.joined(separator: ", ")))

        // chip load over the last ten readings: a moment's spike doesn't move the dial; a sustained load does; old readings
        // drop off; closing the panel forgets them
        var avg = HardwarePage.LoadAverage()
        let empty = avg.value == nil
        for _ in 0..<9 { avg.add(0.1) }
        avg.add(1.0)
        let spike = HardwarePage.chip(busy: avg.value).text
        for _ in 0..<12 { avg.add(0.9) }
        let sustained = HardwarePage.chip(busy: avg.value).text, kept = avg.readings.count
        avg.add(1.5)
        let clamped = avg.readings.last == 1.0
        avg.clear()
        let a1 = empty && spike == "Light" && sustained == "Heavy" && kept == HardwarePage.LoadAverage.span && clamped && avg.value == nil
        review.append(("chip-load-average", a1, "spike \(spike), sustained \(sustained), kept \(kept), cleared \(avg.value == nil)"))

        // the battery's or drive's own heat counts toward the snowflake, the title, and the menu bar icon, whatever the
        // chip says and whether or not its card is on the list; warmth while charging is expected; the battery on a tie
        let ph = [HardwarePage.partHeat(batteryC: 42, charging: false, driveC: nil), HardwarePage.partHeat(batteryC: 42, charging: true, driveC: nil),
                  HardwarePage.partHeat(batteryC: 46, charging: true, driveC: nil), HardwarePage.partHeat(batteryC: 31, charging: false, driveC: 72),
                  HardwarePage.partHeat(batteryC: 42, charging: false, driveC: 72), HardwarePage.partHeat(batteryC: nil, charging: false, driveC: nil)]
        let ph1 = ph.map { $0?.title ?? "none" } == ["Battery warm", "none", "Battery hot", "Drive warm", "Battery warm", "none"]
        var hotSigns = HardwarePage.Signs(); hotSigns.partHeat = ph[2]
        var warmSigns = HardwarePage.Signs(); warmSigns.partHeat = ph[0]
        var warmAndTight = HardwarePage.Signs(memoryTight: true); warmAndTight.partHeat = ph[0]
        let runs = [HardwarePage.running(thermal: "nominal", signs: hotSigns, fans: nil), HardwarePage.running(thermal: "nominal", signs: warmSigns, fans: nil),
                 HardwarePage.running(thermal: "critical", signs: hotSigns, fans: nil), HardwarePage.running(thermal: "nominal", signs: warmAndTight, fans: nil),
                 HardwarePage.running(thermal: "nominal", signs: HardwarePage.Signs(), fans: nil)]
        let hw = Watcher()
        let calmLevel = hw.level([], thermal: "nominal")
        hw.partHeat = ph[2]
        let hotLevel = hw.level([], thermal: "nominal")
        hw.partHeat = ph[3]
        let driveLevel = hw.level([], thermal: "nominal")
        let heatIcons: [Int] = runs.map { $0.icon }
        let ph2 = heatIcons == [2, 1, 2, 1, 0] && runs[0].meaning == "The battery is hot." && runs[1].meaning == "The battery is warm."
            && runs[2].meaning.hasPrefix("macOS is slowing your Mac a lot") && runs[3].meaning.hasPrefix("Apps and programs are using almost all")
            && calmLevel == .good && hotLevel == .issue && driveLevel == .warning
        review.append(("part-heat-counts", ph1 && ph2, ph.map { $0?.title ?? "none" }.joined(separator: ", ") + "; icons \(heatIcons); levels \(calmLevel) \(hotLevel) \(driveLevel)"))

        // a card set aside at yellow comes back at red: a warm battery card waited on stays hidden while warm and shows the
        // moment it's hot; a hot battery card can't be set aside at all; the drive's warm card can
        let reports = Fixture.hardwareReports(now)
        func heatCard(_ name: String, _ id: String) -> LiveCard? { reports.first { $0.0 == name }?.1.cards(now: now).first { $0.id == id } }
        if let warmCard = heatCard("battery-warm", "hardware-battery-heat"), let hotCard = heatCard("battery-hot", "hardware-battery-heat") {
            let wait = Watcher()
            wait.snooze(warmCard, until: now.addingTimeInterval(3600))
            let hiddenWarm = wait.isWaitedOn(warmCard, now: now), shownHot = !wait.isWaitedOn(hotCard, now: now)
            let backLater = !wait.isWaitedOn(warmCard, now: now.addingTimeInterval(7200))
            wait.snooze(hotCard, until: now.addingTimeInterval(3600))                 // refused: still waiting at yellow only
            let refused = !wait.isWaitedOn(hotCard, now: now) && wait.snoozed[hotCard.cause]?.severity == 1
            let fresh = Watcher(); fresh.snooze(hotCard, until: now.addingTimeInterval(3600))
            let neverWaited = fresh.snoozed[hotCard.cause] == nil
            var drive = HardwareReport(); var d = DriveHealth(); d.temperatureC = 72; drive.drive = d
            let driveCard = drive.cards(now: now).first { $0.id == "hardware-drive-heat" }
            let wr1 = warmCard.severity == 1 && hotCard.severity == 2 && warmCard.cause == hotCard.cause && hiddenWarm && shownHot && backLater
                && refused && neverWaited && Watcher.canWait(warmCard) && !Watcher.canWait(hotCard)
                && driveCard.map { $0.safety && Watcher.canWait($0) } == true
            review.append(("heat-card-returns-at-red", wr1, "warm \(warmCard.severity), hot \(hotCard.severity); hidden warm \(hiddenWarm), shown hot \(shownHot), hot refused \(refused && neverWaited)"))
        } else {
            review.append(("heat-card-returns-at-red", false, "no battery heat card in the samples"))
        }
        // from the independent review (25 November 2026): the memory dial gives the memory card's verdict (heavy swapping
        // while macOS says normal is Tight, not OK) and "…" when pressure can't be read; the title takes the worse heat,
        // the chip on a tie; the battery's heat follows its live reading; VoiceOver hears the heat dial's step
        var swapping = MacState(); swapping.memoryPressure = "normal"; swapping.swappedOutMB = 2000
        var unread = MacState(); unread.memoryPressure = "unknown"
        var calmMac = MacState(); calmMac.memoryPressure = "normal"
        let reviewMem = [HardwarePage.memory(swapping).text, HardwarePage.memory(unread).text, HardwarePage.memory(calmMac).text]
        let hotPart = HardwarePage.PartHeat(part: "battery", level: 2), warmPart = HardwarePage.PartHeat(part: "battery", level: 1)
        let titles = [HardwarePage.heatTitle(thermal: "fair", partHeat: hotPart), HardwarePage.heatTitle(thermal: "serious", partHeat: hotPart),
                      HardwarePage.heatTitle(thermal: "nominal", partHeat: warmPart), HardwarePage.heatTitle(thermal: "fair", partHeat: warmPart),
                      HardwarePage.heatTitle(thermal: "fair", partHeat: nil), HardwarePage.heatTitle(thermal: "nominal", partHeat: nil)].map { $0 ?? "none" }
        var coolBattery = BatteryHealth(); coolBattery.temperatureC = 38
        var hotBattery = BatteryHealth(); hotBattery.temperatureC = 46
        var liveHot = MacState(); liveHot.batteryTempC = 46
        var liveCool = MacState(); liveCool.batteryTempC = 35
        let readCool = HardwareReport(battery: coolBattery), readHot = HardwareReport(battery: hotBattery)
        let followedUp = readCool.followingLive(liveHot), followedDown = readHot.followingLive(liveCool)
        let live1 = HardwarePage.partHeat(report: readCool, mac: liveHot)?.title == "Battery hot"
            && HardwarePage.partHeat(report: readHot, mac: MacState())?.title == "Battery hot"
            && followedUp?.cards(now: now).contains { $0.id == "hardware-battery-heat" && $0.serious } == true
            && followedDown.map { r in !r.cards(now: now).contains { $0.id == "hardware-battery-heat" } } == true
            && readCool.followingLive(liveCool) == nil && readCool.followingLive(MacState()) == nil
        let spoken = [HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 46)?.spoken ?? "", HardwarePage.chip(busy: 0.9).spoken,
                      HardwarePage.chip(busy: nil).spoken]
        let rv = reviewMem == ["Tight", "…", "OK"]
            && titles == ["Battery hot", "Running hot", "Battery warm", "Running warm", "Running warm", "none"] && live1
            && spoken[0].hasPrefix("Battery temp ") && spoken[0].hasSuffix(", hot") && spoken[1] == "Chip load Heavy" && spoken[2] == "Chip load not read yet"
        review.append(("dials-review-fixes", rv, "memory \(reviewMem); titles \(titles); live \(live1); spoken \(spoken)"))

        // the heat dial: the part nearest its own limit, the chip on a tie; a battery warm while charging is expected
        let h = [HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 31, driveC: 34),          // all calm: chip
                 HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 46, driveC: 34),          // hot battery
                 HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 42, charging: true),      // warm, charging: chip
                 HardwarePage.heat(chipC: 55, thermal: "nominal", batteryC: 42),                      // warm, not charging
                 HardwarePage.heat(chipC: 90, thermal: "serious", batteryC: 42),                      // a tie: chip
                 HardwarePage.heat(chipC: 55, thermal: "nominal", driveC: 72),                        // warm drive
                 HardwarePage.heat(chipC: nil, thermal: "nominal", batteryC: 31)]                     // no chip reading
        let h1 = h.map { $0?.name ?? "none" } == ["Chip temperature", "Battery temperature", "Chip temperature", "Battery temperature", "Chip temperature", "Drive temperature", "Battery temperature"]
            && h.map { $0?.level ?? -1 } == [0, 2, 0, 1, 1, 1, 0]
        review.append(("heat-ring-part", h1, h.map { "\($0?.name ?? "none") \($0?.text ?? "") level \($0?.level ?? -1)" }.joined(separator: ", ")))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func hardwarePageSamples(_ now: Date) -> [(String, Card)] { [] }
}

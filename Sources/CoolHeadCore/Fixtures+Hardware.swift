import Foundation

/// Checks for the hardware checks (see Hardware.swift), and made-up reports that show every hardware card, for
/// `coolhead wording` and for screenshots (COOLHEAD_SNAPSHOT_HARDWARE), so no one's own Mac appears in either.
extension Fixture {
    static func hardwareChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func headlines(_ r: HardwareReport) -> [String] { r.cards(now: now).map(\.card.headline) }

        // the drive's 512-byte health record, read the way the NVMe specification lays it out (little-endian)
        var bytes = [UInt8](repeating: 0, count: 512)
        bytes[0] = 0b0000_0101; bytes[1] = 0x32; bytes[2] = 0x01   // spare and reliability flags; 306 K
        bytes[3] = 100; bytes[4] = 99; bytes[5] = 4
        func put(_ v: UInt64, at o: Int) { for i in 0..<8 { bytes[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xFF) } }
        put(133_444_097, at: 48); put(2280, at: 128); put(16, at: 144); put(3, at: 160)
        let parsed = DriveHealth.parse(bytes)
        let parseOK = parsed?.temperatureC == 33 && parsed?.percentUsed == 4 && parsed?.spare == 100 && parsed?.spareThreshold == 99
            && parsed?.dataUnitsWritten == 133_444_097 && parsed?.powerOnHours == 2280 && parsed?.unsafeShutdowns == 16 && parsed?.mediaErrors == 3
            && parsed?.warnings == ["running out of spare space", "less reliable than it should be"] && parsed?.fault == true
            && parsed?.lines.contains("Written so far: about 68 TB") == true && DriveHealth.parse([0, 1]) == nil
        review.append(("hardware-drive-record", parseOK, parsed.map { $0.lines.joined(separator: "; ") } ?? "not parsed"))

        // drive cards: a fault and uncorrected errors need a look and recommend backing up; wear is a note; a healthy
        // drive has no card
        let samples = Fixture.hardwareReports(now)
        func sample(_ id: String) -> HardwareReport { samples.first { $0.0 == id }!.1 }
        let fault = sample("drive-fault").cards(now: now).first
        let errors = sample("drive-errors").cards(now: now).first
        let worn = sample("drive-worn").cards(now: now).first
        let driveOK = fault?.card.headline == "The Mac's internal drive is reporting a fault." && fault?.needsLook == true
            && fault?.card.recommended?.id == "backup" && fault?.card.fixes.contains { $0.id == "diagnostics" } == true
            && errors?.card.headline == "The Mac's internal drive has found errors it couldn't correct." && errors?.needsLook == true
            && worn?.card.headline == "The Mac's internal drive has used 85% of its rated life." && worn?.needsLook == false
            && headlines(HardwareReport(drive: DriveHealth())).isEmpty
        review.append(("hardware-drive-cards", driveOK, [fault, errors, worn].map { $0?.card.headline ?? "none" }.joined(separator: " | ")))

        // System Information's battery report: its JSON says "Good" where Settings says "Normal"
        let profile = #"{"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":{"sppower_battery_cycle_count":579,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"81%"}}]}"#
        let (condition, cap) = BatteryHealth.parseProfile(Data(profile.utf8))
        var good = BatteryHealth(); good.condition = condition; good.maxCapacity = cap
        let profileOK = condition == "Good" && cap == 81 && good.conditionNormal && good.lines.first == "Condition: Normal"
            && BatteryHealth.parseProfile(Data("not json".utf8)).condition == nil
        review.append(("hardware-battery-report", profileOK, "condition \(condition ?? "none"), Maximum Capacity \(cap.map { "\($0)%" } ?? "none")"))

        // battery cards: service needs a look; wear below 80% is a note; a healthy battery has none
        let service = sample("battery-service").cards(now: now).first
        let wornBattery = sample("battery-worn").cards(now: now).first
        let failed = sample("battery-fault").cards(now: now).first
        let batteryOK = service?.card.headline == "The battery needs service." && service?.needsLook == true && service?.card.recommended?.id == "battery"
            && service?.card.fixes.contains { if case .guide(let s) = $0.kind { return s.contains { $0.contains("swollen battery is a fire risk") } }; return false } == true
            && wornBattery?.card.headline == "The battery holds 76% of its original charge." && wornBattery?.needsLook == false
            && wornBattery?.card.explanation.contains("Apple rates it to keep 80% for 1,000 cycles, and it has done 840") == true
            && failed?.card.headline == "The battery has recorded a fault." && failed?.needsLook == true
            && headlines(HardwareReport(battery: good)).isEmpty
        review.append(("hardware-battery-cards", batteryOK, [service, wornBattery, failed].map { $0?.card.headline ?? "none" }.joined(separator: " | ")))

        // plugged in but not charging: why, best guess first; nothing when charging, full, or unplugged
        func plugged(_ pct: Int, temp: Double = 30, watts: Double = 0) -> BatteryHealth {
            var b = good; b.onPower = true; b.percent = pct; b.temperatureC = temp; b.batteryWatts = watts; b.adapterWatts = 30; return b
        }
        var charging = plugged(50); charging.charging = true
        var unplugged = plugged(50); unplugged.onPower = false
        var full = plugged(100); full.fullyCharged = true
        let why = [plugged(80).notCharging, plugged(60, temp: 42).notCharging, plugged(60, watts: -8).notCharging, plugged(60).notCharging]
        let chargeOK = why == [.onHold(80), .tooWarm(42), .chargerTooWeak(30), .unknown]
            && charging.notCharging == nil && unplugged.notCharging == nil && full.notCharging == nil
            && headlines(HardwareReport(battery: plugged(80))) == ["Charging is on hold at 80%."]
            && headlines(HardwareReport(battery: plugged(60, watts: -8))) == ["The charger isn't keeping up."]
            && HardwareReport(battery: plugged(60)).cards(now: now).first?.card.explanation.contains("no SMC to reset") == true
            && HardwareReport(battery: plugged(60), appleSilicon: false).cards(now: now).first?.card.explanation.contains("SMC") == false
        review.append(("hardware-not-charging", chargeOK, why.map { "\($0.map { "\($0)" } ?? "none")" }.joined(separator: ", ")))

        // crash restarts: what the report says, read the way Howard Oakley reads them
        let watchdog = "panic(cpu 3 caller 0xfffffe004c620574): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds\nservice: logd"
        let driver = "panic(cpu 0 caller 0x1): Kernel data abort.\nKernel Extensions in backtrace:\n         com.example.dockdriver(1.2)[ABC]@0xfffffe0012345678\n"
        let causes = [CrashRestarts.cause(watchdog), CrashRestarts.cause("panic(cpu 1 caller 0x2): zone map exhausted"), CrashRestarts.cause(driver),
                      CrashRestarts.cause("panic(cpu 2 caller 0x3): Kernel data abort.\nKernel Extensions in backtrace:\n com.apple.driver.AppleT8112(1)[X]@0x1\n")]
        let causeOK = causes == [.stoppedResponding("WindowServer"), .kernelMemory, .driver("com.example.dockdriver"), .unclear]
        review.append(("hardware-crash-cause", causeOK, causes.map { "\($0)" }.joined(separator: ", ")))
        let afterCrash = sample("crash-this-start").cards(now: now).first
        let repeated = sample("crash-repeated").cards(now: now).first
        let old = CrashRestarts(lastText: watchdog, lastDate: now.addingTimeInterval(-20 * 86400), thisStartFollowedCrash: false, recent: [])
        let crashOK = afterCrash?.card.headline == "Your Mac restarted because of a crash." && afterCrash?.needsLook == true
            && afterCrash?.card.explanation.hasPrefix("WindowServer, the part of macOS that draws the screen, stopped responding, so macOS restarted") == true
            && afterCrash?.card.explanation.contains("Cool Head can't test the memory") == true
            && repeated?.card.headline == "Your Mac has crashed and restarted 3 times this week."
            && headlines(HardwareReport(crashes: old)).isEmpty
            && CrashRestarts(lastDate: now.addingTimeInterval(-3600), recent: nil).countThisWeek(now: now) == 1
        review.append(("hardware-crash-cards", crashOK, [afterCrash, repeated].map { $0?.card.headline ?? "none" }.joined(separator: " | ")))

        // ports: too much power needs a look, with Apple's steps first; failures to connect are a note
        let power = sample("port-power").cards(now: now).first
        let drops = sample("port-drops").cards(now: now).first
        let portOK = power?.card.headline == "A device asked USB-C port 1 for more power than it can give." && power?.needsLook == true
            && power?.card.recommended?.id == "power"
            && drops?.card.headline == "A device on USB-C port 2 has failed to connect 3 times." && drops?.needsLook == false
        review.append(("hardware-port-cards", portOK, [power, drops].map { $0?.card.headline ?? "none" }.joined(separator: " | ")))

        // Phil's style, on every hardware card: no em dashes or exclamation marks, the Apple Diagnostics steps right for
        // the kind of Mac, and the worst first
        let all = samples.flatMap { $0.1.cards(now: now) }
        let text = all.flatMap { c in [c.card.headline, c.card.explanation] + c.card.fixes.flatMap { f -> [String] in
            if case .guide(let s) = f.kind { return [f.title, f.consequence] + s }; return [f.title, f.consequence] } }
        let styleOK = !text.contains { $0.contains("—") || $0.contains("!") }
        func steps(_ f: Fix?) -> [String] { if case .guide(let s)? = f?.kind { return s }; return [] }
        let intel = HardwareReport(drive: sample("drive-fault").drive, appleSilicon: false).cards(now: now).first?.card.fixes.first { $0.id == "diagnostics" }
        let silicon = fault?.card.fixes.first { $0.id == "diagnostics" }
        let stepsOK = steps(silicon).contains { $0.contains("Command-D") } && steps(intel).contains { $0.contains("hold D") }
            && !steps(intel).contains { $0.contains("Command-D") }
        let mixed = HardwareReport(drive: sample("drive-worn").drive, ports: sample("port-power").ports).cards(now: now)
        let orderOK = mixed.first?.needsLook == true && mixed.last?.needsLook == false
        review.append(("hardware-wording", styleOK && stepsOK && orderOK, "\(all.count) cards: style \(styleOK), Diagnostics steps \(stepsOK), worst first \(orderOK)"))

        // and on this Mac: every check runs with no password, quickly, and gives sane figures. A Mac without a battery,
        // or a virtual Mac with no NVMe drive (as on GitHub's build machines), has nothing to read, which is fine.
        let t = Date()
        let live = HardwareReport.read(now: now)
        let took = Date().timeIntervalSince(t)
        let sane = (live.drive.map { $0.spare <= 100 && $0.percentUsed <= 255 } ?? true)
            && (live.battery?.maxCapacity.map { (1...150).contains($0) } ?? true) && took < 5
        review.append(("hardware-live-read", sane,
                       String(format: "%.2f s; drive %@; battery %@; crash restarts this week %d; ports with errors %d", took,
                              live.drive.map { "\($0.percentUsed)% used, \($0.mediaErrors) errors" } ?? "not readable",
                              live.battery.map { "\($0.condition ?? "condition unknown"), \($0.maxCapacity.map { "\($0)%" } ?? "?")" } ?? "none",
                              live.crashes.countThisWeek(now: now), live.ports.count)))

        // the drive's record is closed after each read: the drive lets one program open it at a time, so a record left
        // open makes every later read fail (as in 0.8.0, until Cool Head quit). Read it twice more; if it could be read
        // once, it must be read both times. Not readable at all (another program has it open, or no NVMe drive) passes.
        let again = (DriveHealth.read(), DriveHealth.read())
        let closes = live.drive == nil || (again.0 != nil && again.1 != nil)
        review.append(("hardware-drive-closes", closes, live.drive == nil
            ? "not readable on this Mac now (another program may have it open), so not tested"
            : "read 3 times in a row: " + [live.drive, again.0, again.1].map { $0 == nil ? "failed" : "ok" }.joined(separator: ", ")))

        // the chip's temperature: the hottest "tdie" sensor, ignoring sensors that aren't fitted (they read below zero),
        // and on this Mac quickly, within what a chip can read, or nil where macOS doesn't offer the sensors
        let fitted = ChipTemperature.hottest([("PMU tdie1", 54.9), ("PMU2 tdie3", 50.4), ("PMU tdev1", 70), ("PMU tdie9", -1.4), ("NAND CH0 temp", 42)]) == 54.9
            && ChipTemperature.hottest([("gas gauge battery", 34)]) == nil
        let t0 = Date()
        let chip = ChipTemperature.read()
        let tookChip = Date().timeIntervalSince(t0)
        review.append(("chip-temperature", fitted && tookChip < 0.5 && (chip.map { (20...130).contains($0) } ?? true),
                       String(format: "%.3f s; %@", tookChip, chip.map { String(format: "hottest chip sensor %.0f°C", $0) } ?? "not readable on this Mac")))
        return review
    }

    /// Made-up reports, one per hardware card, for `coolhead wording` and screenshots.
    public static func hardwareReports(_ now: Date) -> [(String, HardwareReport)] {
        var d = DriveHealth(); d.spare = 100; d.spareThreshold = 99; d.percentUsed = 12; d.dataUnitsWritten = 40_000_000; d.powerOnHours = 3100
        d.temperatureC = 31
        var fault = d; fault.criticalWarning = 0b100; fault.mediaErrors = 41
        var errors = d; errors.mediaErrors = 6
        var worn = d; worn.percentUsed = 85; worn.dataUnitsWritten = 900_000_000
        var b = BatteryHealth(); b.condition = "Normal"; b.maxCapacity = 88; b.cycles = 412; b.designCycles = 1000; b.temperatureC = 29; b.percent = 64
        var service = b; service.condition = "Service Recommended"; service.maxCapacity = 74; service.cycles = 1103
        var wornBattery = b; wornBattery.maxCapacity = 76; wornBattery.cycles = 840
        var failed = b; failed.permanentFailure = 1
        var onHold = b; onHold.onPower = true; onHold.percent = 80; onHold.adapterWatts = 70
        var warm = b; warm.onPower = true; warm.percent = 55; warm.temperatureC = 43; warm.adapterWatts = 70
        var weak = b; weak.onPower = true; weak.percent = 41; weak.adapterWatts = 30; weak.batteryWatts = -9
        var unknown = b; unknown.onPower = true; unknown.percent = 52; unknown.adapterWatts = 70
        let watchdog = "panic(cpu 3 caller 0xfffffe004c620574): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds"
        let thisStart = CrashRestarts(lastText: watchdog, lastDate: now.addingTimeInterval(-2 * 3600), thisStartFollowedCrash: true, recent: [now.addingTimeInterval(-2 * 3600)])
        let repeated = CrashRestarts(lastText: "panic(cpu 0 caller 0x1): Kernel data abort.", lastDate: now.addingTimeInterval(-3600), thisStartFollowedCrash: true,
                                     recent: ([-3600, -86400, -3 * 86400] as [TimeInterval]).map { now.addingTimeInterval($0) })
        return [("drive-fault", HardwareReport(drive: fault)),
                ("drive-errors", HardwareReport(drive: errors)),
                ("drive-worn", HardwareReport(drive: worn)),
                ("battery-fault", HardwareReport(battery: failed)),
                ("battery-service", HardwareReport(battery: service)),
                ("battery-worn", HardwareReport(battery: wornBattery)),
                ("charging-on-hold", HardwareReport(battery: onHold)),
                ("charging-too-warm", HardwareReport(battery: warm)),
                ("charging-charger-too-weak", HardwareReport(battery: weak)),
                ("charging-unknown", HardwareReport(battery: unknown)),
                ("crash-this-start", HardwareReport(crashes: thisStart)),
                ("crash-repeated", HardwareReport(crashes: repeated)),
                ("port-power", HardwareReport(ports: [PortErrors(name: "USB-C port 1", overCurrent: 2)])),
                ("port-drops", HardwareReport(ports: [PortErrors(name: "USB-C port 2", failedToConnect: 3)]))]
    }

    /// No sample cards of its own for `coolhead wording`.
    static func hardwareSamples(_ now: Date) -> [(String, Card)] { [] }
}

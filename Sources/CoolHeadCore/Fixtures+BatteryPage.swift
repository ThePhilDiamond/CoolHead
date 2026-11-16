import Foundation

/// Checks for the Battery tool's page (see BatteryPage.swift): every state reads as a sentence, and a Mac with no
/// battery has no page.
extension Fixture {
    static func batteryPageChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func battery(_ change: (inout BatteryHealth) -> Void) -> BatteryHealth {
            var b = BatteryHealth(); b.condition = "Normal"; b.maxCapacity = 81; b.cycles = 579; b.designCycles = 1000; b.percent = 64
            change(&b); return b
        }
        let worn = battery { $0.condition = "Service Recommended"; $0.maxCapacity = 76 }
        let fault = battery { $0.permanentFailure = 1 }
        let h1 = BatteryPage.health(battery { _ in }) == "It holds 81% of its original charge, after 579 of the 1,000 charge cycles Apple rates it for. macOS rates its condition Normal."
            && BatteryPage.health(worn).hasSuffix("macOS rates its condition Service Recommended: it needs service.")
            && BatteryPage.health(fault).contains("recorded a fault")
            && BatteryPage.health(BatteryHealth()) == "macOS doesn't say how worn it is."
        review.append(("battery-page-health", h1, BatteryPage.health(battery { _ in })))

        let onBattery = battery { $0.batteryWatts = -8.4 }
        let charging = battery { $0.onPower = true; $0.charging = true; $0.batteryWatts = 45; $0.adapterWatts = 96 }
        let held = battery { $0.onPower = true; $0.percent = 80 }
        let warm = battery { $0.onPower = true; $0.percent = 50; $0.temperatureC = 42 }
        let weak = battery { $0.onPower = true; $0.percent = 50; $0.batteryWatts = -6; $0.adapterWatts = 30 }
        let full = battery { $0.onPower = true; $0.percent = 100; $0.fullyCharged = true; $0.adapterWatts = 96 }
        let lines = [onBattery, charging, held, warm, weak, full].map(BatteryPage.now)
        let n1 = lines == [
            "On battery at 64%, using about 8 W.",
            "Charging at 64%, taking about 45 W from a 96 W charger.",
            "Plugged in, holding at 80%. That's most likely on purpose: Optimized Battery Charging or a Charge Limit slows battery wear.",
            "Plugged in, but not charging while the battery is warm (42°C). It starts again as it cools.",
            "Plugged in, but draining: the Mac is using more than the 30 W charger gives.",
            "Plugged in and full from a 96 W charger.",
        ] && BatteryPage.temperature(warm) == "The battery is at 42°C, which is warm." && BatteryPage.temperature(onBattery) == nil
        review.append(("battery-page-now", n1, lines.joined(separator: " | ")))

        // the page merges the hourly report with this moment's state, and a Mac with no battery gets no page
        var mac = MacState(); mac.batteryPercent = 30; mac.onPower = true; mac.charging = true; mac.batteryWatts = 20
        let merged = BatteryPage.merge(report: battery { $0.percent = 90; $0.onPower = false }, mac: mac)
        let m1 = merged?.percent == 30 && merged?.charging == true && merged?.maxCapacity == 81
            && BatteryPage.merge(report: nil, mac: MacState()) == nil
            && BatteryPage.sample.maxCapacity == 92 && BatteryPage.sample.cycles == 214
        review.append(("battery-page-merge", m1, merged.map(BatteryPage.now) ?? "no battery"))
        return review
    }
}

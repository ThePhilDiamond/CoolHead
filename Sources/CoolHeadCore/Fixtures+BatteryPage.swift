import Foundation

/// Checks for the Battery tool's page (see BatteryPage.swift): the verdict, the three figures and the status line read
/// right in every state, and a Mac with no battery has no page.
extension Fixture {
    static func batteryPageChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func battery(_ change: (inout BatteryHealth) -> Void) -> BatteryHealth {
            var b = BatteryHealth(); b.condition = "Normal"; b.maxCapacity = 81; b.cycles = 579; b.designCycles = 1000; b.percent = 64
            change(&b); return b
        }
        // the verdict: healthy, worn below 80%, needs service, or a fault, worst first
        let verdicts = [battery { _ in }, battery { $0.maxCapacity = 76 }, battery { $0.condition = "Service Recommended" }, battery { $0.permanentFailure = 1 }]
            .map(BatteryPage.verdict)
        let v1 = verdicts.map(\.title) == ["Battery healthy", "Battery worn", "Battery needs service", "Battery fault"]
            && verdicts.map(\.level) == [0, 1, 2, 2]
        review.append(("battery-page-verdict", v1, verdicts.map { "\($0.title): \($0.meaning)" }.joined(separator: " | ")))

        // the figures: how much it holds (orange below 80%), cycles against Apple's rating, and temperature (warm from 40°C)
        let tiles = BatteryPage.tiles(battery { $0.temperatureC = 42 })
        let worn = BatteryPage.tiles(battery { $0.maxCapacity = 76; $0.cycles = 1100 })
        let t1 = tiles.map(\.value) == ["81%", "579", Fmt.temperature(42)] && tiles.map(\.unit) == ["of its first charge", "of 1,000 rated cycles", "temperature"]
            && tiles.map(\.level) == [0, 0, 1] && worn.map(\.level) == [2, 1]
            && BatteryPage.tiles(BatteryHealth()).isEmpty
        review.append(("battery-page-tiles", t1, tiles.map { "\($0.value) \($0.unit)" }.joined(separator: ", ")))

        // the status line in each state, with the same reasons for not charging as the charging card
        let states = [battery { $0.batteryWatts = -8.4 },
                      battery { $0.onPower = true; $0.charging = true; $0.batteryWatts = 45; $0.adapterWatts = 96 },
                      battery { $0.onPower = true; $0.percent = 80 },
                      battery { $0.onPower = true; $0.percent = 50; $0.temperatureC = 42 },
                      battery { $0.onPower = true; $0.percent = 50; $0.batteryWatts = -6; $0.adapterWatts = 30 },
                      battery { $0.onPower = true; $0.percent = 100; $0.fullyCharged = true; $0.adapterWatts = 96 }].map(BatteryPage.status)
        let s1 = states.map { $0.text + " / " + ($0.detail ?? "-") } == [
            "On battery · 64% / using 8 W",
            "Charging · 64% / 45 W from a 96 W charger",
            "Holding at 80% / on purpose, to slow wear",
            "Not charging · 50% / too warm (\(Fmt.temperature(42))); it starts as it cools",
            "Draining while plugged in / the 30 W charger can't keep up",
            "Plugged in · full / 96 W charger",
        ] && states.map(\.level) == [0, 0, 0, 1, 2, 0] && states[0].symbol == "battery.75percent"
        review.append(("battery-page-status", s1, states.map { $0.text + " / " + ($0.detail ?? "-") }.joined(separator: " | ")))

        // the page merges the hourly report with this moment's state, and a Mac with no battery gets no page
        var mac = MacState(); mac.batteryPercent = 30; mac.onPower = true; mac.charging = true; mac.batteryWatts = 20
        let merged = BatteryPage.merge(report: battery { $0.percent = 90; $0.onPower = false }, mac: mac)
        let m1 = merged?.percent == 30 && merged?.charging == true && merged?.maxCapacity == 81
            && BatteryPage.merge(report: nil, mac: MacState()) == nil
            && BatteryPage.sample.maxCapacity == 92 && BatteryPage.sample.cycles == 214
        review.append(("battery-page-merge", m1, merged.map { BatteryPage.status($0).text } ?? "no battery"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func batteryPageSamples(_ now: Date) -> [(String, Card)] { [] }
}

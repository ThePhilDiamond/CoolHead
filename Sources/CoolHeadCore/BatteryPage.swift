import Foundation

/// The Battery tool's page (Phil, 16 November 2026: "when you click on the battery, what it gives you is the insights
/// into the battery health, the ability to toggle on and off the setting, and any other optimizations we choose to
/// include"): its health and what it's doing now, in sentences, from what the hardware checks already read.
public enum BatteryPage {
    /// The hardware report's battery (condition and Maximum Capacity, read at most hourly) with this moment's charge,
    /// power and temperature from the Mac's state (read every few seconds). Nil on a Mac with no battery.
    public static func merge(report: BatteryHealth?, mac: MacState) -> BatteryHealth? {
        guard report != nil || mac.batteryPercent != nil else { return nil }
        var b = report ?? BatteryHealth()
        if let p = mac.batteryPercent { b.percent = p }
        b.onPower = mac.onPower
        b.charging = mac.charging
        if mac.batteryWatts != nil { b.batteryWatts = mac.batteryWatts }
        if mac.batteryTempC != nil { b.temperatureC = mac.batteryTempC }
        if b.maxCapacity == nil { b.maxCapacity = mac.healthPercent }
        if b.cycles == nil { b.cycles = mac.cycles }
        b.fullyCharged = b.fullyCharged || (mac.onPower && (mac.batteryPercent ?? 0) >= 100)
        return b
    }

    /// Its health, in a sentence or two: how much it holds, its cycles against what Apple rates it for, and macOS's
    /// own word for its condition.
    public static func health(_ b: BatteryHealth) -> String {
        var s = ""
        if let m = b.maxCapacity {
            s = "It holds \(m)% of its original charge"
            if let c = b.cycles {
                s += b.designCycles.map { ", after \(Hardware.count(UInt64(c))) of the \(Hardware.count(UInt64($0))) charge cycles Apple rates it for" }
                    ?? ", after \(Hardware.count(UInt64(c))) charge cycles"
            }
            s += "."
        } else if let c = b.cycles {
            s = "It has done \(Hardware.count(UInt64(c))) charge cycles."
        }
        if b.permanentFailure != 0 {
            s += (s.isEmpty ? "" : " ") + "Its controller has recorded a fault: have Apple check it."
        } else if let c = b.condition {
            s += (s.isEmpty ? "" : " ") + (b.conditionNormal ? "macOS rates its condition Normal." : "macOS rates its condition \(c): it needs service.")
        }
        return s.isEmpty ? "macOS doesn't say how worn it is." : s
    }

    /// What it's doing now: on battery and how fast it's draining, charging and how fast, full, or plugged in but not
    /// charging and why (the same reasons the charging card gives).
    public static func now(_ b: BatteryHealth) -> String {
        let pct = b.percent.map { "\($0)%" } ?? "an unknown charge"
        let charger = b.adapterWatts.map { " from a \($0) W charger" } ?? ""
        if !b.onPower {
            return "On battery at \(pct)" + (b.batteryWatts.flatMap { $0 < -0.5 ? String(format: ", using about %.0f W.", -$0) : nil } ?? ".")
        }
        if b.charging {
            return "Charging at \(pct)" + (b.batteryWatts.flatMap { $0 > 0.5 ? String(format: ", taking about %.0f W", $0) : nil } ?? "") + charger + "."
        }
        if let why = b.notCharging {
            switch why {
            case .onHold(let p): return "Plugged in, holding at \(p)%. That's most likely on purpose: Optimized Battery Charging or a Charge Limit slows battery wear."
            case .tooWarm(let t): return String(format: "Plugged in, but not charging while the battery is warm (%.0f°C). It starts again as it cools.", t)
            case .chargerTooWeak(let w): return "Plugged in, but draining: the Mac is using more than " + (w.map { "the \($0) W charger" } ?? "the charger") + " gives."
            case .unknown: return "Plugged in at \(pct), but not charging, and macOS doesn't say why."
            }
        }
        return "Plugged in and full" + charger + "."
    }

    /// The temperature, when it's known, as a short line.
    public static func temperature(_ b: BatteryHealth) -> String? {
        b.temperatureC.map { String(format: "The battery is at %.0f°C", $0) + ($0 >= 40 ? ", which is warm." : ".") }
    }

    /// For screenshots: a made-up battery, never this Mac's.
    public static let sample: BatteryHealth = {
        var b = BatteryHealth()
        b.condition = "Normal"; b.maxCapacity = 92; b.cycles = 214; b.designCycles = 1000
        b.temperatureC = 31; b.percent = 64; b.onPower = false; b.batteryWatts = -8.4; b.adapterWatts = 96
        return b
    }()
}

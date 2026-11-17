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

    // Shown the way Test my network shows its result (Phil, 16 November 2026: "The battery tool isn't as visual as the
    // network tool, it's a bit too much of a wall of text"): a verdict in a few words, three figures, and a status line.
    // Levels: 0 fine (green), 1 worth knowing (yellow), 2 needs a look (orange).

    /// The answer in a few words, and what it means in one short sentence.
    public struct Verdict: Equatable { public let level: Int; public let title: String; public let meaning: String }
    public static func verdict(_ b: BatteryHealth) -> Verdict {
        if b.permanentFailure != 0 {
            return Verdict(level: 2, title: "Battery fault", meaning: "Its controller has recorded a fault. Have Apple check it.")
        }
        if !b.conditionNormal {
            return Verdict(level: 2, title: "Battery needs service", meaning: "macOS rates its condition \(b.condition ?? "Service Recommended"). The Mac is safe to keep using.")
        }
        if let m = b.maxCapacity, m < 80 {
            return Verdict(level: 1, title: "Battery worn", meaning: "You get less time unplugged. Below 80%, AppleCare replaces it.")
        }
        return Verdict(level: 0, title: "Battery healthy", meaning: b.condition == nil ? "macOS doesn't rate its condition." : "macOS rates its condition Normal.")
    }

    /// Three figures, each with its level: how much it holds, its cycles against Apple's rating, and its temperature.
    public struct Tile: Equatable { public let symbol: String; public let value: String; public let unit: String; public let level: Int }
    public static func tiles(_ b: BatteryHealth) -> [Tile] {
        var t: [Tile] = []
        if let m = b.maxCapacity { t.append(Tile(symbol: "heart", value: "\(m)%", unit: "of its first charge", level: m < 80 ? 2 : 0)) }
        if let c = b.cycles {
            let unit = b.designCycles.map { "of \(Hardware.count(UInt64($0))) rated cycles" } ?? "charge cycles"
            t.append(Tile(symbol: "arrow.triangle.2.circlepath", value: Hardware.count(UInt64(c)), unit: unit, level: c >= (b.designCycles ?? .max) ? 1 : 0))
        }
        if let c = b.temperatureC {
            t.append(Tile(symbol: "thermometer.medium", value: String(format: "%.0f°C", c), unit: "temperature", level: c >= 45 ? 2 : c >= 40 ? 1 : 0))
        }
        return t
    }

    /// What it's doing now, as an icon, a few words and a detail: on battery, charging, full, or plugged in but not
    /// charging and why (the same reasons the charging card gives).
    public struct Status: Equatable { public let symbol: String; public let text: String; public let detail: String?; public let level: Int }
    public static func status(_ b: BatteryHealth) -> Status {
        let pct = b.percent ?? 0
        let level = pct >= 88 ? 100 : pct >= 63 ? 75 : pct >= 38 ? 50 : pct >= 13 ? 25 : 0
        let gauge = "battery.\(level)percent"
        let charger = b.adapterWatts.map { "\($0) W charger" }
        if !b.onPower {
            return Status(symbol: gauge, text: "On battery · \(pct)%",
                          detail: b.batteryWatts.flatMap { $0 < -0.5 ? String(format: "using %.0f W", -$0) : nil }, level: 0)
        }
        if b.charging {
            let rate = b.batteryWatts.flatMap { $0 > 0.5 ? String(format: "%.0f W", $0) : nil }
            let detail = [rate, charger.map { "from a \($0)" }].compactMap { $0 }.joined(separator: " ")
            return Status(symbol: "battery.100percent.bolt", text: "Charging · \(pct)%", detail: detail.isEmpty ? nil : detail, level: 0)
        }
        if let why = b.notCharging {
            switch why {
            case .onHold(let p): return Status(symbol: gauge, text: "Holding at \(p)%", detail: "on purpose, to slow wear", level: 0)
            case .tooWarm(let t): return Status(symbol: gauge, text: "Not charging · \(pct)%", detail: String(format: "too warm (%.0f°C); it starts as it cools", t), level: 1)
            case .chargerTooWeak(let w): return Status(symbol: gauge, text: "Draining while plugged in", detail: (w.map { "the \($0) W charger" } ?? "the charger") + " can't keep up", level: 2)
            case .unknown: return Status(symbol: gauge, text: "Not charging · \(pct)%", detail: "macOS doesn't say why", level: 1)
            }
        }
        return Status(symbol: "battery.100percent.bolt", text: "Plugged in · full", detail: charger, level: 0)
    }

    /// For screenshots: a made-up battery, never this Mac's.
    public static let sample: BatteryHealth = {
        var b = BatteryHealth()
        b.condition = "Normal"; b.maxCapacity = 92; b.cycles = 214; b.designCycles = 1000
        b.temperatureC = 31; b.percent = 64; b.onPower = false; b.batteryWatts = -8.4; b.adapterWatts = 96
        return b
    }()
}

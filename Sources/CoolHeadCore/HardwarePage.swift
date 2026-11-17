import Foundation

/// The Hardware tool's page (Phil, 16 November 2026: "Yes build the hardware tool page"): the hardware checks Cool Head
/// already makes (the internal drive, the battery, crash restarts and the ports), shown the way Test my network and
/// Battery show theirs: a verdict in a few words, a figure for each part, and a status line. A problem still gets its
/// own card in the list as well. Levels: 0 fine (green), 1 worth knowing (yellow), 2 needs a look (orange).
public enum HardwarePage {
    /// The answer in a few words, and what it means in one short sentence. The worst finding leads.
    public struct Verdict: Equatable { public let level: Int; public let title: String; public let meaning: String }
    public static func verdict(_ r: HardwareReport, now: Date = Date()) -> Verdict {
        let crashes = r.crashes.countThisWeek(now: now)
        if let d = r.drive, d.fault {
            return Verdict(level: 2, title: "Drive needs a look", meaning: "The internal drive reports a problem. Back up now, then run Apple Diagnostics.")
        }
        if let b = r.battery, b.permanentFailure != 0 || !b.conditionNormal {
            return Verdict(level: 2, title: "Battery needs service", meaning: "The Battery page says what macOS reports and what to do.")
        }
        if crashes >= 2 {
            return Verdict(level: 2, title: "Crash restarts", meaning: "The Mac restarted after a crash \(Hardware.times(crashes)) this week. Its card says what that means and what to try.")
        }
        if let d = r.drive, d.mediaErrors > 0 {
            return Verdict(level: 1, title: "Drive errors", meaning: "The drive couldn't correct some reads. Keep your backups current.")
        }
        if crashes == 1 {
            // what it means and what to do, never a bare cause (Phil, 16 November 2026: "Otherwise this is scary and
            // intimidating to a lay person with no clear path forward"); a second crash this week brings its card
            let cause = CrashRestarts.plainCause(r.crashes.lastText.map(CrashRestarts.cause) ?? .unclear)
            return Verdict(level: 1, title: "One crash restart", meaning: cause + " Once needs nothing from you. If it happens again, Cool Head shows a card with what to try.")
        }
        if r.ports.contains(where: { $0.overCurrent > 0 }) {
            return Verdict(level: 1, title: "A port was overloaded", meaning: "A device asked a port for more power than it can give.")
        }
        if let d = r.drive, d.percentUsed >= 80 {
            return Verdict(level: 1, title: "Drive well worn", meaning: "It has used \(d.percentUsed)% of its rated life. It still works; keep your backups current.")
        }
        if let b = r.battery, let m = b.maxCapacity, m < 80 {
            return Verdict(level: 1, title: "Battery worn", meaning: "It holds \(m)% of its first charge. The Battery page says more.")
        }
        let parts = [r.drive != nil ? "the drive" : nil, r.battery != nil ? "the battery" : nil, "the ports"].compactMap { $0 }
        return Verdict(level: 0, title: "Hardware looks healthy", meaning: "No warnings from \(list(parts)), and no crash restarts this week.")
    }

    /// One figure for each part Cool Head can read: drive life used, battery health, crash restarts this week, port
    /// errors. A Mac with no battery shows three.
    public struct Tile: Equatable {
        public enum Part: String { case drive, battery, crashes, ports }
        public let part: Part; public let symbol: String; public let value: String; public let unit: String; public let level: Int
    }
    public static func tiles(_ r: HardwareReport, now: Date = Date()) -> [Tile] {
        var t: [Tile] = []
        if let d = r.drive {
            t.append(Tile(part: .drive, symbol: "internaldrive", value: "\(d.percentUsed)%", unit: "drive life used",
                          level: d.fault ? 2 : (d.percentUsed >= 80 || d.mediaErrors > 0) ? 1 : 0))
        }
        if let b = r.battery, let m = b.maxCapacity {
            t.append(Tile(part: .battery, symbol: "battery.75percent", value: "\(m)%", unit: "battery health",
                          level: (b.permanentFailure != 0 || !b.conditionNormal) ? 2 : m < 80 ? 1 : 0))
        }
        let crashes = r.crashes.countThisWeek(now: now)
        t.append(Tile(part: .crashes, symbol: "arrow.clockwise", value: "\(crashes)", unit: crashes == 1 ? "crash this week" : "crashes this week",
                      level: crashes >= 2 ? 2 : crashes == 1 ? 1 : 0))
        let portErrors = r.ports.reduce(0) { $0 + $1.overCurrent + $1.failedToConnect + $1.linkErrors }
        t.append(Tile(part: .ports, symbol: "cable.connector", value: "\(portErrors)", unit: portErrors == 1 ? "port error" : "port errors",
                      level: r.ports.contains(where: { $0.overCurrent > 0 }) ? 1 : 0))
        return t
    }

    /// One line under the figures: when the last crash restart this week was, if there was one; otherwise the
    /// drive's wear in plain terms (how much has been written, and for how long it has been on).
    public struct Status: Equatable { public let symbol: String; public let text: String; public let detail: String?; public let level: Int }
    public static func status(_ r: HardwareReport, now: Date = Date()) -> Status {
        // when, not why: the cause, in plain words with what to do, is in the verdict or on the crash card
        if let last = r.crashes.lastDate, now.timeIntervalSince(last) < 7 * 86400 {
            return Status(symbol: "arrow.clockwise", text: "Last crash restart \(Fmt.time(last))", detail: nil, level: 1)
        }
        if let d = r.drive {
            return Status(symbol: "internaldrive", text: "About \(Hardware.size(d.bytesWritten)) written",
                          detail: "on for \(Hardware.count(d.powerOnHours)) hours", level: 0)
        }
        return Status(symbol: "internaldrive", text: "Cool Head can't read the drive's health", detail: nil, level: 0)
    }

    static func list(_ parts: [String]) -> String {
        parts.count <= 2 ? parts.joined(separator: " or ") : parts.dropLast().joined(separator: ", ") + ", or " + parts.last!
    }

    /// For screenshots: made-up hardware, never this Mac's. "issue" shows a worn drive and one crash restart.
    public static func sample(_ kind: String = "healthy", now: Date = Date()) -> HardwareReport {
        var d = DriveHealth()
        d.spare = 100; d.spareThreshold = 10; d.percentUsed = 3; d.powerOnHours = 2_140; d.dataUnitsWritten = 35_000_000
        var r = HardwareReport(drive: d, battery: BatteryPage.sample, crashes: CrashRestarts(recent: []), ports: [], appleSilicon: true)
        if kind == "issue" {
            r.drive?.percentUsed = 84
            r.crashes = CrashRestarts(lastText: "panic(cpu 2 caller 0xfffffe0012345678): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds",
                                      lastDate: now.addingTimeInterval(-26 * 3600), recent: [now.addingTimeInterval(-26 * 3600)])
        }
        return r
    }
}

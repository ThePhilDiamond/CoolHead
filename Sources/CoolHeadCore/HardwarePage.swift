import Foundation

/// The Hardware tool's page (Phil, 16 November 2026: "Yes build the hardware tool page"): the parts of the Mac other than
/// the battery, which has its own page (Phil, 16 November 2026: "let's omit the battery health from the hardware test
/// screen. It should be focused on drive, fans (if applicable), memory, and any other hardware we can test"). Shown the
/// way Test my network and Battery show theirs: a verdict in a few words, how it's running now, a figure for each part,
/// and a status line. A problem still gets its own card in the list as well.
/// Levels: 0 fine (green), 1 worth knowing (yellow), 2 needs a look (orange).
public enum HardwarePage {
    /// The answer in a few words, and what it means in a sentence or two. The worst finding leads.
    public struct Verdict: Equatable { public let level: Int; public let title: String; public let meaning: String }
    public static func verdict(_ r: HardwareReport, now: Date = Date()) -> Verdict {
        let crashes = r.crashes.countThisWeek(now: now)
        if let d = r.drive, d.fault {
            return Verdict(level: 2, title: "Drive needs a look", meaning: "The internal drive reports a problem. Back up now, then run Apple Diagnostics.")
        }
        if crashes >= 2 {
            return Verdict(level: 2, title: "Crash restarts", meaning: "The Mac restarted after a crash \(Hardware.times(crashes)) this week. Its card says what that means and what to try.")
        }
        if let d = r.drive, d.mediaErrors > 0 {
            return Verdict(level: 1, title: "Drive errors", meaning: "The drive couldn't correct some reads. Keep your backups current.")
        }
        if crashes == 1 {
            // what it means and what to do, never a bare cause, and short (Phil, 16 November 2026: "Otherwise this is
            // scary and intimidating to a lay person with no clear path forward"; "A one-off crash like this isn't of
            // concern. If it happens again... in the next week"; "be careful about a wall of text"); a second crash
            // within the week brings its card
            let cause = CrashRestarts.plainCause(r.crashes.lastText.map(CrashRestarts.cause) ?? .unclear)
            return Verdict(level: 1, title: "One crash restart", meaning: cause + " A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try.")
        }
        if r.ports.contains(where: { $0.overCurrent > 0 }) {
            return Verdict(level: 1, title: "A port was overloaded", meaning: "A device asked a port for more power than it can give.")
        }
        if let d = r.drive, d.percentUsed >= 80 {
            return Verdict(level: 1, title: "Drive well worn", meaning: "It has used \(d.percentUsed)% of its rated life. It still works; keep your backups current.")
        }
        return Verdict(level: 0, title: "Hardware looks healthy", meaning: r.drive != nil
            ? "No warnings from the drive or the ports, and no crash restarts this week."
            : "No warnings from the ports, and no crash restarts this week.")
    }

    /// The fans, where the Mac has any: their speeds; a fanless Mac (every Apple silicon MacBook Air) says so, since it
    /// slows itself instead of spinning up. Nil: not known.
    public enum Fans: Equatable { case none, rpm([Int]) }

    /// How it's running now, drawn with the menu bar icon's melting snowflake (Phil, 16 November 2026: "explain how
    /// it's running and what it means in a fun visual way that mirrors our menu icon and the spirit of the app").
    /// From macOS's own thermal state: nominal, fair, serious, critical. `icon`: 0 a whole snowflake, 1 melting, 2 in flames.
    public struct Running: Equatable { public let icon: Int; public let title: String; public let meaning: String; public let fans: String? }
    public static func running(thermal: String, fans: Fans?) -> Running {
        let fanText: String? = {
            switch fans {
            case .none?: return "No fans: it slows itself down to stay cool, silently."
            case .rpm(let r)?:
                let fast = r.max() ?? 0
                let speeds = r.map { Hardware.count(UInt64($0)) + " rpm" }.joined(separator: " and ")
                return (r.count == 1 ? "Fan at " : "Fans at ") + speeds + (fast < 1500 ? ", barely audible." : fast < 3500 ? ", working a little." : ", working hard.")
            case nil: return nil
            }
        }()
        switch thermal {
        case "fair":
            return Running(icon: 1, title: "Warming up", meaning: "It's warm, but still running at full speed.", fans: fanText)
        case "serious":
            return Running(icon: 1, title: "Running hot", meaning: "macOS is slowing it a little to cool it down.", fans: fanText)
        case "critical":
            return Running(icon: 2, title: "Too hot", meaning: "macOS is slowing it hard. Give it a break on a hard surface, out of the sun.", fans: fanText)
        default:
            return Running(icon: 0, title: "Keeping its cool", meaning: "A normal temperature, at full speed.", fans: fanText)
        }
    }

    /// One figure for each part Cool Head can read: drive life used, memory, crash restarts this week, port errors.
    public struct Tile: Equatable {
        public enum Part: String { case drive, memory, crashes, ports }
        public let part: Part; public let symbol: String; public let value: String; public let unit: String; public let level: Int
    }
    public static func tiles(_ r: HardwareReport, memoryGB: Double, now: Date = Date()) -> [Tile] {
        var t: [Tile] = []
        if let d = r.drive {
            t.append(Tile(part: .drive, symbol: "internaldrive", value: "\(d.percentUsed)%", unit: "drive life used",
                          level: d.fault ? 2 : (d.percentUsed >= 80 || d.mediaErrors > 0) ? 1 : 0))
        }
        if memoryGB > 0 {
            t.append(Tile(part: .memory, symbol: "memorychip", value: "\(Int(memoryGB.rounded())) GB", unit: "memory", level: 0))
        }
        let crashes = r.crashes.countThisWeek(now: now)
        t.append(Tile(part: .crashes, symbol: "arrow.clockwise", value: "\(crashes)", unit: crashes == 1 ? "crash this week" : "crashes this week",
                      level: crashes >= 2 ? 2 : crashes == 1 ? 1 : 0))
        let portErrors = r.ports.reduce(0) { $0 + $1.overCurrent + $1.failedToConnect + $1.linkErrors }
        t.append(Tile(part: .ports, symbol: "cable.connector", value: "\(portErrors)", unit: portErrors == 1 ? "port error" : "port errors",
                      level: r.ports.contains(where: { $0.overCurrent > 0 }) ? 1 : 0))
        return t
    }

    /// One line under the figures: when the last crash restart this week was, if there was one; otherwise the drive's
    /// wear in plain terms (how much has been written, and for how long it has been on).
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

    /// For screenshots: made-up hardware, never this Mac's. "issue" shows a worn drive and one crash restart.
    public static func sample(_ kind: String = "healthy", now: Date = Date()) -> HardwareReport {
        var d = DriveHealth()
        d.spare = 100; d.spareThreshold = 10; d.percentUsed = 3; d.powerOnHours = 2_140; d.dataUnitsWritten = 35_000_000; d.temperatureC = 34
        var r = HardwareReport(drive: d, battery: nil, crashes: CrashRestarts(recent: []), ports: [], appleSilicon: true)
        if kind == "issue" {
            r.drive?.percentUsed = 84
            r.crashes = CrashRestarts(lastText: "panic(cpu 2 caller 0xfffffe0012345678): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds",
                                      lastDate: now.addingTimeInterval(-26 * 3600), recent: [now.addingTimeInterval(-26 * 3600)])
        }
        return r
    }
}

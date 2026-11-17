import Foundation

/// The Hardware tool's page (Phil, 16 November 2026: "Yes build the hardware tool page"): the parts of the Mac other than
/// the battery, which has its own page (Phil, 16 November 2026: "let's omit the battery health from the hardware test
/// screen. It should be focused on drive, fans (if applicable), memory, and any other hardware we can test"). A verdict
/// in a few words, then each part with everything about it together (Phil, 16 November 2026: "we should keep related
/// info together"). A problem still gets its own card in the list as well.
/// Levels: 0 fine (green), 1 worth knowing (yellow), 2 needs a look (orange).
public enum HardwarePage {
    /// The answer in a few words, and what it means in one short sentence. The worst finding leads; its details are
    /// under its part.
    public struct Verdict: Equatable { public let level: Int; public let title: String; public let meaning: String }
    public static func verdict(_ r: HardwareReport, now: Date = Date()) -> Verdict {
        let crashes = r.crashes.countThisWeek(now: now)
        if let d = r.drive, d.fault {
            return Verdict(level: 2, title: "Drive needs a look", meaning: "The internal drive reports a problem. Back up now, then run Apple Diagnostics.")
        }
        if crashes >= 2 {
            return Verdict(level: 2, title: "Crash restarts", meaning: "The Mac restarted after a crash \(Hardware.times(crashes)) this week. What to try is below.")
        }
        if let d = r.drive, d.mediaErrors > 0 {
            return Verdict(level: 1, title: "Drive errors", meaning: "The drive couldn't correct some reads. Keep your backups current.")
        }
        if crashes == 1 {
            return Verdict(level: 1, title: "One crash restart", meaning: "Nothing to worry about yet. What happened is below.")
        }
        if r.ports.contains(where: { $0.overCurrent > 0 }) {
            return Verdict(level: 1, title: "A port was overloaded", meaning: "A device asked a port for more power than it can give.")
        }
        if let d = r.drive, d.percentUsed >= 80 {
            return Verdict(level: 1, title: "Drive well worn", meaning: "It still works; keep your backups current.")
        }
        return Verdict(level: 0, title: "Hardware looks healthy", meaning: r.drive != nil
            ? "No warnings from the drive or the ports, and no crash restarts this week."
            : "No warnings from the ports, and no crash restarts this week.")
    }

    /// One part of the Mac, with everything about it together: its name, a few words for how it is, and a line or two
    /// of detail.
    public struct Part: Equatable {
        public enum Kind: String { case drive, crashes, ports }
        public let kind: Kind; public let symbol: String; public let name: String; public let value: String; public let level: Int
        public let lines: [String]
    }
    public static func parts(_ r: HardwareReport, now: Date = Date()) -> [Part] {
        var out: [Part] = []
        if let d = r.drive {
            // the drive's wear and what wears it (writing, and time on), its temperature, and any errors, in one place
            var lines = ["About \(Hardware.size(d.bytesWritten)) written over \(Hardware.count(d.powerOnHours)) hours"
                + (d.temperatureC.map { ", now at \($0)°C" } ?? "") + "."]
            if !d.warnings.isEmpty { lines.append("It reports: " + d.warnings.joined(separator: ", ") + ". Back up now.") }
            if d.mediaErrors > 0 { lines.append("It couldn't correct \(Hardware.count(d.mediaErrors)) reads. Keep your backups current.") }
            out.append(Part(kind: .drive, symbol: "internaldrive", name: "Drive", value: "\(d.percentUsed)% of its life used",
                            level: d.fault ? 2 : (d.percentUsed >= 80 || d.mediaErrors > 0) ? 1 : 0, lines: lines))
        }
        // crash restarts: the count, when the last one was, and what it means with what to do, together (Phil, 16
        // November 2026: "The crash time is at the bottom but the crash description is at the top"); short, in plain
        // words ("A one-off crash like this isn't of concern. If it happens again... in the next week")
        let crashes = r.crashes.countThisWeek(now: now)
        var crashLines: [String] = []
        if crashes > 0, let last = r.crashes.lastDate {
            crashLines.append("Last one \(Fmt.time(last)).")
        }
        if crashes == 1 {
            crashLines.append(CrashRestarts.plainCause(r.crashes.lastText.map(CrashRestarts.cause) ?? .unclear))
            crashLines.append("A one-off crash like this isn't a concern. If it happens again in the next week, Cool Head will show you what to try.")
        } else if crashes >= 2 {
            crashLines.append("Its card, in the list, says what that means and what to try.")
        }
        out.append(Part(kind: .crashes, symbol: "arrow.clockwise", name: "Crash restarts",
                        value: crashes == 0 ? "None this week" : "\(crashes) this week",
                        level: crashes >= 2 ? 2 : crashes == 1 ? 1 : 0, lines: crashLines))
        // the ports: errors, and on which port
        let errors = r.ports.reduce(0) { $0 + $1.overCurrent + $1.failedToConnect + $1.linkErrors }
        let portLines = r.ports.map { p -> String in
            var what: [String] = []
            if p.overCurrent > 0 { what.append("asked for too much power \(Hardware.times(p.overCurrent))") }
            if p.failedToConnect > 0 { what.append("failed to connect \(Hardware.times(p.failedToConnect))") }
            if p.linkErrors > 0 { what.append("lost its link \(Hardware.times(p.linkErrors))") }
            return (p.name.prefix(1).uppercased() + p.name.dropFirst()) + ": a device " + what.joined(separator: ", ") + "."
        }
        out.append(Part(kind: .ports, symbol: "cable.connector", name: "Ports",
                        value: errors == 0 ? "No errors" : errors == 1 ? "1 error" : "\(Hardware.count(UInt64(errors))) errors",
                        level: r.ports.contains(where: { $0.overCurrent > 0 }) ? 1 : 0, lines: portLines))
        return out
    }

    /// The fans, where the Mac has any: their speeds; a fanless Mac (every Apple silicon MacBook Air) says so, since it
    /// slows itself instead of spinning up. Nil: not known.
    public enum Fans: Equatable { case none, rpm([Int]) }

    /// How it's running now, drawn with the menu bar icon's melting snowflake (Phil, 16 November 2026: "explain how
    /// it's running and what it means in a fun visual way that mirrors our menu icon and the spirit of the app"), at the
    /// top of the panel. From macOS's own thermal state: nominal, fair, serious, critical. `icon`: 0 a whole snowflake,
    /// 1 melting, 2 in flames.
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

    /// How busy the chip and memory are, for the gauges beside it: a share from 0 to 1 and a level. The chip is the share
    /// of all its cores in use; memory is macOS's memory pressure (normal, warning, critical), never "memory used",
    /// which is high on any healthy Mac (rule 10 in the research).
    public struct Gauge: Equatable { public let name: String; public let fill: Double; public let level: Int; public let words: String }
    public static func chip(busy: Double) -> Gauge {
        let b = min(max(busy, 0), 1)
        return Gauge(name: "Chip", fill: b, level: b >= 0.8 ? 2 : b >= 0.5 ? 1 : 0,
                     words: "The chip is \(Int((b * 100).rounded()))% busy" + (b >= 0.8 ? ": working hard." : b >= 0.5 ? "." : ", with room to spare."))
    }
    public static func memory(pressure: String, swappingNow: Bool) -> Gauge {
        switch pressure {
        case "critical": return Gauge(name: "Memory", fill: 1, level: 2, words: "Memory is tight: macOS is short of memory and moving some to disk, which is slow.")
        case "warning": return Gauge(name: "Memory", fill: 0.66, level: 1, words: "Memory is getting full" + (swappingNow ? ", and macOS is moving some to disk." : "."))
        default: return Gauge(name: "Memory", fill: 0.33, level: 0, words: "Memory is fine: there's room for what's open.")
        }
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

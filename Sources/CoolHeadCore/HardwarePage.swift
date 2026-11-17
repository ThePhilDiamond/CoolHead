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
        // names what was checked (Phil, 17 November 2026: "the hardware tool says "hardware looks healthy" but doesn't
        // say WHAT hardware")
        return r.drive != nil
            ? Verdict(level: 0, title: "Drive and ports look healthy", meaning: "No warnings from either, and no crash restarts this week.")
            : Verdict(level: 0, title: "Ports look healthy", meaning: "No warnings from them and no crash restarts this week. The drive's health couldn't be read.")
    }

    /// One part of the Mac, with everything about it together: its name, a few words for how it is, and a line or two
    /// of detail.
    public struct Part: Equatable {
        public enum Kind: String { case drive, crashes, ports, temps }
        public let kind: Kind; public let symbol: String; public let name: String; public let value: String; public let level: Int
        public let lines: [String]
        /// Figures shown as tiles, above the lines.
        public var tiles: [Tile] = []
        /// Whether anything backs the drive up: its own row, with Set up Time Machine at the right when it isn't.
        public var backup: String? = nil
    }
    public typealias Tile = BatteryPage.Tile
    public static func parts(_ r: HardwareReport, now: Date = Date()) -> [Part] {
        var out: [Part] = []
        if let d = r.drive {
            // the drive's wear and what wears it (writing, and time on), its temperature, and any errors, in one place
            var lines: [String] = []
            if !d.warnings.isEmpty { lines.append("It reports: " + d.warnings.joined(separator: ", ") + ". Back up now.") }
            if d.mediaErrors > 0 { lines.append("It couldn't correct \(Hardware.count(d.mediaErrors)) reads. Keep your backups current.") }
            // whether anything backs it up, since every drive warning ends in "back up" (Phil, 16 November 2026: "we can
            // possibly mention time machine/icloud/google drive/dropbox/box backup state?"); sync apps aren't backups
            let backup: String? = switch r.timeMachine {
            case .notSetUp?: "Time Machine isn't set up, so nothing backs this drive up."
            case .setUp?: "Time Machine is set up to back it up."
            case nil: nil
            }
            let level = d.fault ? 2 : (d.percentUsed >= 80 || d.mediaErrors > 0) ? 1 : 0
            // the figures as tiles, as Test my network shows its own (Phil, 17 November 2026: "maybe we want boxes like
            // we have for the network test with life used, amount written, hours of writing, and temperature?")
            // three, in one row: its temperature is with the others under Temperatures (Phil, 17 November 2026: "By
            // having temps separated out, we could do only three boxes for drive")
            let tiles = [Tile(symbol: "gauge.with.dots.needle.33percent", value: "\(d.percentUsed)%", unit: "life used", level: d.percentUsed >= 80 ? 1 : 0),
                         Tile(symbol: "square.and.pencil", value: Hardware.size(d.bytesWritten), unit: "written", level: 0),
                         Tile(symbol: "clock", value: Hardware.count(d.powerOnHours), unit: "hours on", level: 0)]
            out.append(Part(kind: .drive, symbol: "internaldrive", name: "Drive",
                            value: ["Healthy", d.fault ? "Needs a look" : d.mediaErrors > 0 ? "Errors" : "Well worn", "Needs a look"][level],
                            level: level, lines: lines, tiles: tiles, backup: backup))
        } else {
            // never left out without a word: an Intel Mac's drive, or a read that failed
            out.append(Part(kind: .drive, symbol: "internaldrive", name: "Drive", value: "Not read",
                            level: 0, lines: ["Cool Head couldn't read its health record. It tries again every 10 minutes."]))
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
        // every temperature Cool Head reads, together, and what each affects (Phil, 17 November 2026: "Might be worth
        // including on the hardware page as a "Temps" section"). The chip's heat is what macOS slows it for; a warm
        // battery pauses charging (see BatteryHealth.notCharging); a drive only matters when very hot. Battery levels as
        // on the Battery page; the drive's 70°C is Cool Head's own, not from a source.
        var temps: [Tile] = []
        if let c = r.chipC { temps.append(Tile(symbol: "cpu", value: "\(Int(c.rounded()))°C", unit: "chip", level: 0)) }
        if let b = r.battery?.temperatureC {
            temps.append(Tile(symbol: "battery.75percent", value: "\(Int(b.rounded()))°C", unit: "battery", level: b >= 45 ? 2 : b >= 40 ? 1 : 0))
        }
        if let t = r.drive?.temperatureC { temps.append(Tile(symbol: "internaldrive", value: "\(t)°C", unit: "drive", level: t >= 70 ? 1 : 0)) }
        if !temps.isEmpty {
            let worst = temps.map(\.level).max() ?? 0
            out.append(Part(kind: .temps, symbol: "thermometer.medium", name: "Temperatures", value: ["Normal", "Warm", "Hot"][worst],
                            level: worst, lines: ["macOS slows the chip when it gets too hot, and pauses charging while the battery is warm."],
                            tiles: temps))
        }
        return out
    }

    /// The fans, where the Mac has any: their speeds; a fanless Mac (every Apple silicon MacBook Air) says so, since it
    /// slows itself instead of spinning up. Nil: not known.
    public enum Fans: Equatable { case none, rpm([Int]) }

    /// How it's running now, drawn with the menu bar icon's snowflake (Phil, 16 November 2026: "explain how it's running
    /// and what it means in a fun visual way that mirrors our menu icon and the spirit of the app"), at the top of the
    /// panel. The snowflake is the Mac keeping a cool head, so it shows the same level as the menu bar icon, worked out
    /// here once for both (Phil, 17 November 2026: "The snowflake is meant to represent the Mac keeping a cool head,
    /// whether temperature or speed. So if anything is slowing it down, we want to show the snowflake melting. If there
    /// are issues requiring action that are only moderate in impact, that's melting. If severe, that's the 'on fire'
    /// icon."). `icon`: 0 a whole snowflake, 1 melting, 2 in flames. The meaning names the worst cause.
    /// No title of its own: the panel's status ("1 to watch", "All calm") is the title, since the icon is a picture, not
    /// a word for what's wrong (Phil, 17 November 2026: "The text shouldn't say "Starting to melt" - that's an
    /// abstraction taking the icon too far.").
    public struct Running: Equatable { public let icon: Int; public let meaning: String; public let fans: String? }

    /// What the cards on screen say, for the snowflake: what's stuck, memory, heat with a cause, and anything else that
    /// needs a look.
    public struct Signs: Equatable {
        public var stuck = 0
        public var memoryCritical = false
        public var memoryTight = false
        public var addingHeat = false
        public var toWatch = 0
        public var resumeSync = false
        public init(stuck: Int = 0, memoryCritical: Bool = false, memoryTight: Bool = false, addingHeat: Bool = false,
                    toWatch: Int = 0, resumeSync: Bool = false) {
            self.stuck = stuck; self.memoryCritical = memoryCritical; self.memoryTight = memoryTight
            self.addingHeat = addingHeat; self.toWatch = toWatch; self.resumeSync = resumeSync
        }
    }

    public static func running(thermal: String, signs: Signs = Signs(), fans: Fans?) -> Running {
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
        let speed = thermal == "fair" ? "Warm, but at full speed" : "A normal temperature, at full speed"
        // severe first: in flames
        let (icon, meaning): (Int, String) = {
            if thermal == "critical" { return (2, "macOS is slowing it hard to cool it down. Give it a break on a hard surface, out of the sun.") }
            if signs.memoryCritical { return (2, "Memory is very tight, so everything is slower. The card below says what's using it.") }
            if signs.stuck > 0 { return (2, signs.stuck == 1 ? "It isn't making progress. Its card below says what to try." : "They aren't making progress. Their cards below say what to try.") }
            // moderate: melting
            if thermal == "serious" { return (1, "macOS is slowing it a little to cool it down.") }
            if signs.memoryTight { return (1, "Memory is tight, so it's slower than it could be.") }
            if signs.addingHeat { return (1, "It's warm, and something below is adding to it.") }
            if signs.toWatch > 0 { return (1, speed + (signs.toWatch == 1 ? ". The card below needs a look." : ". The cards below need a look.")) }
            if signs.resumeSync { return (1, "It's time to resume syncing.") }
            // nothing slowing it and nothing to act on: whole, even when it's warm
            return (0, speed + ".")
        }()
        return Running(icon: icon, meaning: meaning, fans: fanText)
    }

    /// How busy the chip and memory are, for the gauges beside it: a percentage, and a level for its colour (Phil, 16
    /// November 2026: "If we just display the percentage as well, we don't need mouse-over text"). The chip is the share
    /// of all its cores in use. Memory is the share macOS itself counts as in use when it judges memory pressure (100
    /// minus kern.memorystatus_level, the "free percentage" memory_pressure reports), coloured by that pressure; never
    /// Activity Monitor's "Memory Used", which is high on any healthy Mac (rule 10 in the research).
    public struct Gauge: Equatable {
        public let name: String; public let percent: Int; public let level: Int
        /// What's written inside, when it isn't the percentage.
        public var text: String? = nil
    }
    /// The chip's heat, beside the chip and memory (Phil, 17 November 2026: "include temperature in the top bar for temps
    /// that impact speed/performance"): its temperature written inside, the ring filled by macOS's own four steps, since
    /// those, not the number, decide when it's slowed. Nil when the chip's temperature isn't known.
    public static func heat(chipC: Double?, thermal: String) -> Gauge? {
        guard let c = chipC else { return nil }
        let step = ["nominal": 0, "fair": 1, "serious": 2, "critical": 3][thermal] ?? 0
        return Gauge(name: "Heat", percent: (step + 1) * 25, level: [0, 0, 1, 2][step], text: "\(Int(c.rounded()))°")
    }
    public static func chip(busy: Double) -> Gauge {
        let b = min(max(busy, 0), 1)
        return Gauge(name: "Chip", percent: Int((b * 100).rounded()), level: b >= 0.8 ? 2 : b >= 0.5 ? 1 : 0)
    }
    public static func memory(freePercent: Int, pressure: String) -> Gauge {
        Gauge(name: "Memory", percent: min(max(100 - freePercent, 0), 100),
              level: pressure == "critical" ? 2 : pressure == "warning" ? 1 : 0)
    }

    /// For screenshots: made-up hardware, never this Mac's. "issue" shows a worn drive and one crash restart.
    public static func sample(_ kind: String = "healthy", now: Date = Date()) -> HardwareReport {
        var d = DriveHealth()
        d.spare = 100; d.spareThreshold = 10; d.percentUsed = 3; d.powerOnHours = 2_140; d.dataUnitsWritten = 35_000_000; d.temperatureC = 34
        var b = BatteryHealth(); b.temperatureC = 31
        var r = HardwareReport(drive: d, battery: b, crashes: CrashRestarts(recent: []), ports: [], appleSilicon: true)
        r.timeMachine = .setUp
        r.chipC = 55
        if kind == "issue" {
            r.timeMachine = .notSetUp
            r.drive?.percentUsed = 84
            r.crashes = CrashRestarts(lastText: "panic(cpu 2 caller 0xfffffe0012345678): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds",
                                      lastDate: now.addingTimeInterval(-26 * 3600), recent: [now.addingTimeInterval(-26 * 3600)])
        }
        return r
    }
}

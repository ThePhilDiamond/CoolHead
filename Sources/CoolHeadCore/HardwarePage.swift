import Foundation

/// The Hardware tool's page: the parts of the Mac other than the battery, which has its own page, so this one stays on the
/// drive, fans (if any), memory, and any other hardware Cool Head can test. A verdict in a few words, then each part with
/// everything about it together. A problem still gets its own card in the list as well.
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
        // names what was checked, since "Hardware looks healthy" wouldn't say which hardware
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
            // whether anything backs it up, since every drive warning ends in "back up"; only Time Machine counts, since
            // sync apps (iCloud Drive, Google Drive, Dropbox, Box) aren't backups
            let backup: String? = switch r.timeMachine {
            case .notSetUp?: "Time Machine isn't set up, so nothing backs this drive up."
            case .setUp?: "Time Machine is set up to back it up."
            case nil: nil
            }
            let level = d.fault ? 2 : (d.percentUsed >= 80 || d.mediaErrors > 0) ? 1 : 0
            // the figures as tiles, as Test my network shows its own: three, in one row, since its temperature is with
            // the others under Temperatures
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
        // crash restarts: the count, when the last one was, and what it means with what to do, together, not the time at
        // one end of the part and the meaning at the other; short, in plain words ("A one-off crash like this isn't a
        // concern.")
        let crashes = r.crashes.countThisWeek(now: now)
        var crashLines: [String] = []
        if crashes > 0, let last = r.crashes.lastDate {
            crashLines.append("Last one \(Fmt.time(last)).")
        }
        if crashes == 1 {
            crashLines.append(CrashRestarts.plainCause(r.crashes.lastText.map(CrashRestarts.cause) ?? .unclear).joined(separator: " "))
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
        // every temperature Cool Head reads, together in one section, and what each affects. The chip's heat is what
        // macOS slows it for; a warm battery pauses charging (see BatteryHealth.notCharging); a drive only matters when
        // very hot. Battery levels as on the Battery page; the drive's 70°C is Cool Head's own, not from a source.
        var temps: [Tile] = []
        if let c = r.chipC { temps.append(Tile(symbol: "cpu", value: Fmt.temperature(c), unit: "chip", level: 0)) }
        if let b = r.battery?.temperatureC {
            temps.append(Tile(symbol: "battery.75percent", value: Fmt.temperature(b), unit: "battery", level: b >= 45 ? 2 : b >= 40 ? 1 : 0))
        }
        if let t = r.drive?.temperatureC { temps.append(Tile(symbol: "internaldrive", value: Fmt.temperature(Double(t)), unit: "drive", level: t >= 70 ? 1 : 0)) }
        if !temps.isEmpty {
            let worst = temps.map(\.level).max() ?? 0
            out.insert(Part(kind: .temps, symbol: "thermometer.medium", name: "Temperatures", value: ["Normal", "Warm", "Hot"][worst],
                            level: worst, lines: [],
                            // no lines under the tiles: the heat dial at the top names its part, the dial and the chip tile share
                            // one reading, and a heat card says what heat means when it matters, so text here would
                            // only repeat them
                            tiles: temps), at: 0)            // first: heat is what slows a Mac
        }
        return out
    }

    /// The fans, where the Mac has any: their speeds; a fanless Mac (every Apple silicon MacBook Air) says so, since it
    /// slows itself instead of spinning up. Nil: not known.
    public enum Fans: Equatable { case none, rpm([Int]) }

    /// How it's running now, drawn with the menu bar icon's snowflake at the top of the panel: a playful picture of how the
    /// Mac is and what it means, in the spirit of the app. The snowflake is the Mac keeping a cool head, in temperature or
    /// speed, so it shows the same level as the menu bar icon, worked out here once for both: anything slowing the Mac, or
    /// needing action of moderate impact, melts it; anything severe sets it on fire. `icon`: 0 a whole snowflake, 1
    /// melting, 2 in flames. The meaning names the worst cause.
    /// No title of its own: the panel's status ("1 to watch", "All calm") is the title, since the icon is a picture, not
    /// a word for what's wrong; a title such as "Starting to melt" would take the picture too far.
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
        /// The battery's or drive's own heat, warm or hot (see `partHeat(batteryC:charging:driveC:)`). Heat is a safety
        /// matter, so it counts whether or not its card is on the list.
        public var partHeat: PartHeat? = nil
        public init(stuck: Int = 0, memoryCritical: Bool = false, memoryTight: Bool = false, addingHeat: Bool = false,
                    toWatch: Int = 0, resumeSync: Bool = false) {
            self.stuck = stuck; self.memoryCritical = memoryCritical; self.memoryTight = memoryTight
            self.addingHeat = addingHeat; self.toWatch = toWatch; self.resumeSync = resumeSync
        }
    }

    public static func running(thermal: String, signs: Signs = Signs(), fans: Fans?) -> Running {
        let fanText: String? = {
            switch fans {
            case .none?: return "No fans: your Mac slows itself down to stay cool, silently."
            case .rpm(let r)?:
                let fast = r.max() ?? 0
                let speeds = r.map { Hardware.count(UInt64($0)) + " rpm" }.joined(separator: " and ")
                return (r.count == 1 ? "Fan at " : "Fans at ") + speeds + (fast < 1500 ? ", barely audible." : fast < 3500 ? ", working a little." : ", working hard.")
            case nil: return nil
            }
        }()
        let speed = thermal == "fair" ? "Warm, but at full speed" : "A normal temperature, at full speed"
        // each sentence names what it's about: "your Mac", never a bare "it", which left "macOS is slowing it" unclear
        // severe first: in flames. Each says the cause, never where the cards are: the title counts them, and with a
        // tool open the pill goes back to them
        let (icon, meaning): (Int, String) = {
            if thermal == "critical" { return (2, "macOS is slowing your Mac a lot to cool it. Give it a break on a hard surface, out of the sun.") }
            if signs.memoryCritical { return (2, "Apps and programs are using all of your Mac's memory, so everything is slower.") }
            if signs.stuck > 0 { return (2, signs.stuck == 1 ? "A program isn't making progress." : "\(signs.stuck) programs aren't making progress.") }
            if let p = signs.partHeat, p.level >= 2 { return (2, "The \(p.part) is hot.") }
            // moderate: melting
            if thermal == "serious" { return (1, "macOS is slowing your Mac a little to cool it.") }
            if signs.memoryTight { return (1, "Apps and programs are using almost all of your Mac's memory, so it is slower than it could be.") }
            if let p = signs.partHeat, p.level == 1 { return (1, "The \(p.part) is warm.") }
            if signs.addingHeat { return (1, "Your Mac is warm, and something running is adding to the heat.") }
            // cards to watch melt the snowflake, but the row doesn't point at them: the title already counts them, and with
            // a tool open the pill ("2 fixes recommended") goes back to them, so saying it here too would repeat the pill
            if signs.toWatch > 0 { return (1, speed + ".") }
            if signs.resumeSync { return (1, "It's time to resume syncing.") }
            // nothing slowing it and nothing to act on: whole, even when it's warm
            return (0, speed + ".")
        }()
        return Running(icon: icon, meaning: meaning, fans: fanText)
    }

    /// A dial at the top of the panel: green, yellow, and red zones, the needle in the middle of the zone for its level,
    /// a word or value under it, and a label. Each dial shows a step, never an amount: the zone is the step, so no
    /// position inside it is claimed. Chip load (Light, Medium, Heavy), memory as macOS itself judges its pressure (OK,
    /// Tight, Full), never Activity Monitor's "Memory Used", which is high on any healthy Mac (rule 10 in the research),
    /// and the heat of the part nearest its own limit, with its temperature.
    public struct Gauge: Equatable {
        /// "Chip", "Memory", or the part and " temperature".
        public let name: String
        /// 0 green, 1 yellow, 2 red; -1 before the first reading, drawn with no needle.
        public let level: Int
        /// Under the needle: the word for the step, or the temperature.
        public var text: String
        /// The part it's about, drawn beside its label.
        public var symbol: String? = nil
        public var isTemperature: Bool { name.hasSuffix(" temperature") }
        /// Under the dial: "Chip load", "Memory", "Chip temp", "Battery temp", or "Drive temp".
        public var label: String { isTemperature ? String(name.dropLast(" temperature".count)) + " temp" : name == "Chip" ? "Chip load" : name }
        /// What VoiceOver says: the label and the word, and for a temperature its step too, since the needle carries it
        /// ("Battery temp 115°F, hot").
        public var spoken: String {
            if level < 0 { return "\(label) not read yet" }
            return isTemperature ? "\(label) \(text), \(["normal", "warm", "hot"][level])" : "\(label) \(text)"
        }
        /// Where the needle points, 0 at the left to 1 at the right: the middle of its level's zone; nil with no reading.
        public var needle: Double? { (0...2).contains(level) ? (Double(level) + 0.5) / 3 : nil }
    }
    /// The heat dial: the part nearest its own limit, with its temperature under the needle; the chip's level by macOS's
    /// own four steps, since those, not the number, decide when it's slowed. Nil when the chip's temperature isn't known.
    ///
    /// The part furthest toward its own limit, the most worrying, named with its icon, the chip on a tie. Not the highest
    /// number: a chip runs at 40 to 100°C, so it would nearly always win, while a battery is warm at 40°C and hot at 45°C.
    /// Each part on its own scale: the chip by macOS's four steps; the battery as the Battery page judges it, its warmth
    /// while charging (after being run down, say) expected until 45°C; the drive warm at 70°C, as the Hardware page judges
    /// it.
    /// Memory is inside the chip on Apple silicon, so the chip's reading covers it.
    public static func heat(chipC: Double?, thermal: String, batteryC: Double? = nil, charging: Bool = false, driveC: Double? = nil) -> Gauge? {
        let step = ["nominal": 0, "fair": 1, "serious": 2, "critical": 3][thermal] ?? 0
        let chipLevel = chipC == nil ? -1 : [0, 0, 1, 2][step]
        let batteryLevel = batteryC.map { batteryHeatLevel($0, charging: charging) } ?? -1
        let driveLevel = driveC.map(driveHeatLevel) ?? -1
        if let b = batteryC, batteryLevel > chipLevel, batteryLevel >= driveLevel, batteryLevel > 0 || chipC == nil {
            return Gauge(name: "Battery temperature", level: batteryLevel, text: Fmt.temperature(b), symbol: "battery.75percent")
        }
        if let d = driveC, driveLevel > chipLevel, driveLevel > 0 {
            return Gauge(name: "Drive temperature", level: driveLevel, text: Fmt.temperature(d), symbol: "internaldrive")
        }
        guard let c = chipC else { return nil }
        return Gauge(name: "Chip temperature", level: chipLevel, text: Fmt.temperature(c), symbol: "cpu")
    }
    /// The battery's or drive's own heat, warm (1) or hot (2), for the snowflake, the panel's title, and the menu bar
    /// icon: heat is a safety matter (a laptop warming on a bed), so it counts even when the chip is calm and even when its
    /// card was set aside. The battery on a tie. Nil when both are normal.
    public struct PartHeat: Equatable {
        /// "battery" or "drive".
        public let part: String
        public let level: Int
        /// For the panel's title: "Battery hot", "Battery warm", "Drive warm".
        public var title: String { part.prefix(1).uppercased() + part.dropFirst() + (level >= 2 ? " hot" : " warm") }
    }
    /// Part heat for this Mac: the battery's live reading (every 10 seconds, the one the Power page shows) when there is
    /// one, else the hardware report's; the drive's from the report (it changes slowly).
    public static func partHeat(report: HardwareReport?, mac: MacState) -> PartHeat? {
        let live = mac.batteryTempC != nil
        return partHeat(batteryC: mac.batteryTempC ?? report?.battery?.temperatureC,
                        charging: live ? mac.charging : report?.battery?.charging ?? false,
                        driveC: report?.drive?.temperatureC.map(Double.init))
    }
    /// The heat word for the panel's title: the chip's as macOS judges it ("Running warm" for fair, "Running hot" for
    /// serious or critical) or the battery's or drive's own ("Battery hot"), whichever is worse, the chip on a tie, so a
    /// hot battery never sits under a calmer word than its red row. Nil when neither is above normal.
    public static func heatTitle(thermal: String, partHeat: PartHeat?) -> String? {
        let chip = ["fair": 1, "serious": 2, "critical": 2][thermal] ?? 0
        if let p = partHeat, p.level > chip { return p.title }
        return chip == 0 ? nil : chip == 1 ? "Running warm" : "Running hot"
    }
    public static func partHeat(batteryC: Double?, charging: Bool, driveC: Double?) -> PartHeat? {
        let b = batteryC.map { batteryHeatLevel($0, charging: charging) } ?? 0
        let d = driveC.map(driveHeatLevel) ?? 0
        guard max(b, d) > 0 else { return nil }
        return b >= d ? PartHeat(part: "battery", level: b) : PartHeat(part: "drive", level: d)
    }
    /// How warm the battery is on its own scale: 0 normal, 1 warm, 2 hot. Warm from 40°C (where macOS starts pausing
    /// charging, see BatteryHealth.notCharging), except while it charges, when warmth is expected; hot from 45°C always.
    /// The heat dial, part heat, and the battery temperature card both use it, so they never disagree.
    public static func batteryHeatLevel(_ c: Double, charging: Bool) -> Int { c >= 45 ? 2 : c >= 40 && !charging ? 1 : 0 }
    /// The drive's: warm from 70°C (Cool Head's own line, as on the Hardware page); never "hot", with no source for one.
    public static func driveHeatLevel(_ c: Double) -> Int { c >= 70 ? 1 : 0 }

    /// What the heat dial is showing, when pointed at.
    public static func heatHelp(_ name: String) -> String {
        switch name {
        case "Chip temperature": return "The hottest of the chip's sensors, read every 3 seconds. The battery's or the drive's shows here instead when one is nearer its own limit."
        case "Battery temperature": return "The battery is nearer its limit than the chip: a battery is warm from \(Fmt.temperature(40)) and hot from \(Fmt.temperature(45)). Warmth while it charges is expected."
        case "Drive temperature": return "The drive is nearer its limit than the chip: it's warm from \(Fmt.temperature(70))."
        default: return ""
        }
    }
    /// Chip load from the share of all its cores in use over about the last 30 seconds (see `LoadAverage`): Light under
    /// half, Medium from half, Heavy from 80%. Nil busy (no reading yet) has no needle and "…" under it. A word for a
    /// load, never a verdict: Heavy on a cool Mac is just work, so it doesn't count toward the snowflake.
    public static func chip(busy: Double?) -> Gauge {
        guard let busy else { return Gauge(name: "Chip", level: -1, text: "…", symbol: "cpu") }
        let b = min(max(busy, 0), 1), level = b >= 0.8 ? 2 : b >= 0.5 ? 1 : 0
        return Gauge(name: "Chip", level: level, text: ["Light", "Medium", "Heavy"][level], symbol: "cpu")
    }
    /// Memory by macOS's own pressure: OK (normal), Tight (warning), Full (critical); "…" with no needle when it
    /// couldn't be read, rather than claiming OK.
    public static func memory(pressure: String) -> Gauge {
        let level = ["normal": 0, "warning": 1, "critical": 2][pressure] ?? -1
        return Gauge(name: "Memory", level: level, text: level < 0 ? "…" : ["OK", "Tight", "Full"][level], symbol: "memorychip")
    }
    /// The memory dial for this Mac: the same verdict as the memory card and the snowflake (MacState.memoryLevel, which
    /// counts heavy swapping as tight even while macOS says normal), so "Memory is tight" never sits beside "OK".
    public static func memory(_ mac: MacState) -> Gauge { memory(pressure: mac.memoryLevel ?? mac.memoryPressure) }
    /// What a dial shows, when pointed at.
    public static func help(_ g: Gauge) -> String {
        switch g.name {
        case "Chip": return "How busy the chip has been over about the last 30 seconds: Light under half its capacity, Medium from half, Heavy from 80%. Activity Monitor shows what's using it."
        case "Memory": return "How tight memory is, as macOS itself judges it: OK, Tight, or Full. When it's tight, your Mac uses its disk as extra memory, which is slower."
        default: return heatHelp(g.name)
        }
    }

    /// Chip load over about the last 30 seconds: the last ten readings, taken 3 seconds apart while the panel is open, so
    /// a moment's spike doesn't move the dial. Emptied when the panel closes, so an old reading never stands for now.
    public struct LoadAverage: Equatable {
        public static let span = 10
        public private(set) var readings: [Double] = []
        public init() {}
        public mutating func add(_ busy: Double) {
            readings.append(min(max(busy, 0), 1))
            if readings.count > Self.span { readings.removeFirst(readings.count - Self.span) }
        }
        public mutating func clear() { readings = [] }
        /// Nil before the first reading.
        public var value: Double? { readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count) }
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

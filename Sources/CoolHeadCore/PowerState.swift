import Foundation

/// The Mac's power state, as `pmset` reports it to any user (tested 16 November 2026, macOS 26.6.2, an administrator
/// account without sudo): Low Power Mode for each power source, what is holding the Mac awake, and what happened while
/// it slept. Each makes a card only when it explains something a person would notice: a slow Mac, a Mac that won't
/// sleep, or a battery that drained overnight (rules 7 and 12 in the research). The text gives the verdict and the
/// evidence; the option carries the action (Phil, 16 November 2026: "You included the action in the description, which
/// then repeats in the one-click. That's not ideal.").
public enum PowerState {
    // MARK: Low Power Mode

    /// Whether Low Power Mode is set for battery and for the power adapter (`pmset -g custom`).
    public struct LowPower: Equatable { public var battery: Bool; public var adapter: Bool }
    public static func parseCustom(_ text: String) -> LowPower? {
        var section = "", battery: Bool?, adapter: Bool?
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasSuffix("Power:") { section = l; continue }
            let parts = l.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2, parts[0] == "lowpowermode" else { continue }
            if section.hasPrefix("Battery") { battery = parts[1] == "1" } else if section.hasPrefix("AC") { adapter = parts[1] == "1" }
        }
        guard battery != nil || adapter != nil else { return nil }
        return LowPower(battery: battery ?? false, adapter: adapter ?? false)
    }

    // MARK: Held awake

    /// One program holding the Mac awake (`pmset -g assertions`, "Listed by owning process"): who, for how long, and
    /// whether it keeps the screen on or only the Mac. `forPID` is the app macOS's own service holds it for (macOS's
    /// sound service, for an app with sound open). The assertion's own name isn't kept: it can hold a page title.
    public struct Hold: Equatable {
        public var pid: Int32; public var name: String; public var seconds: Int; public var display: Bool; public var forPID: Int32?
        public init(pid: Int32, name: String, seconds: Int, display: Bool, forPID: Int32? = nil) {
            self.pid = pid; self.name = name; self.seconds = seconds; self.display = display; self.forPID = forPID
        }
    }
    /// How long a program holding the Mac awake must have done almost nothing before Cool Head says it forgot to let
    /// go, and what "almost nothing" is: under this share of one core, it and the programs it started together. Not
    /// from a source: an open app waiting for you uses a few percent at most; one at work uses far more.
    public static let idleMinimum: TimeInterval = 30 * 60
    public static let idleShare = 0.05
    static let keepsAwake = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
    static let keepsScreenOn = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    public static func parseAssertions(_ text: String) -> [Hold] {
        var out: [Hold] = []
        var inList = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("Listed by owning process") { inList = true; continue }
            guard inList else { continue }
            if line.hasPrefix("No kernel assertions") || line.hasPrefix("Kernel Assertions") { break }
            // "   pid 642(Claude): [0x0000002a00018180] 38:44:59 NoIdleSleepAssertion named: "…""
            if let m = line.firstMatch(of: #/pid (\d+)\(([^)]*)\): \[[^\]]*\] (\d+):(\d\d):(\d\d) (\w+)/#) {
                let type = String(m.6)
                guard keepsAwake.contains(type) || keepsScreenOn.contains(type) else { continue }
                let secs = (Int(m.3) ?? 0) * 3600 + (Int(m.4) ?? 0) * 60 + (Int(m.5) ?? 0)
                out.append(Hold(pid: Int32(m.1) ?? 0, name: String(m.2), seconds: secs, display: keepsScreenOn.contains(type)))
            } else if let m = line.firstMatch(of: #/Created for PID: (\d+)/#), !out.isEmpty {
                out[out.count - 1].forPID = Int32(m.1)
            }
        }
        return out
    }

    // MARK: While it slept

    /// The last sleep that ended in someone waking the Mac (`pmset -g log`, about a week of it): when it began and
    /// ended, the charge at each end and whether it was on battery throughout, and the wakes macOS made while it slept
    /// ("DarkWake"), by what woke it.
    public struct Night: Equatable {
        public var from: Date; public var to: Date
        public var chargeFrom: Int?; public var chargeTo: Int?
        public var onBattery: Bool
        public var wakes: [String: Int]          // reason class: count
        public var total: Int { wakes.values.reduce(0, +) }
        public var drop: Int? { chargeFrom.flatMap { f in chargeTo.map { f - $0 } } }
    }

    /// What woke it, in a few plain words (classes from the reasons `pmset -g log` gives).
    public static func wakeClass(_ line: String) -> String {
        let l = line.lowercased()
        if l.contains("rtc") || l.contains("maintenance") { return "macOS's own upkeep" }
        if l.contains("wifi") || l.contains("wlan") || l.contains("arpt") || l.contains("network") || l.contains("wow") || l.contains(" en0") { return "the network" }
        if l.contains("bluetooth") || l.contains("hid") { return "Bluetooth devices" }
        if l.contains("usb") || l.contains("xhc") { return "something plugged in" }
        if l.contains("notification") || l.contains("smc") { return "notifications" }
        return "other things"
    }

    /// What each class of wake is, for the card's sentence. Upkeep is macOS's own timer ("rtc/SleepService" and
    /// "rtc/Maintenance"); on Phil's Mac (19 November 2026) the tasks that asked for it were Spotlight, Calendar's travel
    /// times, widgets, and keeping the network address.
    static let whyWoke: [String: String] = [
        "macOS's own upkeep": "Most wakes were macOS waking itself for background tasks, such as indexing files, refreshing widgets, and checking calendars for travel time. Each is short, but they add up.",
        "the network": "Most wakes were for the network, which lets it receive messages and Find My while asleep, at a cost in battery.",
        "Bluetooth devices": "Most wakes were Bluetooth devices, such as a mouse, keyboard, or headphones, asking it to wake.",
        "something plugged in": "Most wakes were something plugged in, such as a drive or hub, asking it to wake.",
        "notifications": "Most wakes were for notifications, which macOS wakes to deliver.",
    ]

    static let logDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; return f
    }()

    public static func parseLog(_ text: String) -> Night? {
        var night: Night?, last: Night?
        func charge(_ line: String) -> (Int?, Bool) {
            let c = line.firstMatch(of: #/Charge:(\d+)%/#).flatMap { Int($0.1) }
            return (c, line.contains("Using Batt") || line.contains("Using BATT"))
        }
        for line in text.split(separator: "\n").map(String.init) {
            guard line.count > 26, let date = logDate.date(from: String(line.prefix(25))) else { continue }
            let rest = line.dropFirst(26)
            if rest.hasPrefix("Sleep ") && line.contains("Entering Sleep") {
                if night == nil {
                    let (c, batt) = charge(line)
                    night = Night(from: date, to: date, chargeFrom: c, chargeTo: nil, onBattery: batt, wakes: [:])
                }
            } else if rest.hasPrefix("DarkWake "), night != nil {
                night!.wakes[wakeClass(line), default: 0] += 1
                if !charge(line).1 { night!.onBattery = false }
            // every "Wake" line is the Mac fully awake (dark wakes are "DarkWake"; "Wake Requests" only schedules one).
            // Opening the lid reads "due to smc.sysState.Wake ... lid ... HID Activity", with no "UserActivity", so a
            // test for particular reasons merged a day of use into one long sleep (Phil's Mac, 19 November 2026)
            } else if rest.hasPrefix("Wake "), !rest.hasPrefix("Wake Requests"), var n = night {
                let (c, batt) = charge(line)
                n.to = date; n.chargeTo = c
                if !batt { n.onBattery = false }
                last = n; night = nil
            }
        }
        return last
    }

    // MARK: Cards

    /// What the cards need to know about a process involved: its name, its app's bundle path, and whether it's
    /// security software.
    public struct Who: Equatable {
        public var name: String; public var bundle: String?; public var protected: Bool
        public init(name: String, bundle: String? = nil, protected: Bool = false) { self.name = name; self.bundle = bundle; self.protected = protected }
    }

    /// The cards: Low Power Mode left on with the power adapter while the Mac is busy; one program holding the Mac awake
    /// for 2 hours or more; a battery that drained 10% or more overnight while it kept waking.
    /// `idleFor`: how long the program a hold is for, and the programs it started, have done almost nothing (see
    /// `PowerState.idleShare`); nil while that isn't known yet.
    public static func cards(lowPower: LowPower?, lowPowerNow: Bool, onPower: Bool, busy: Bool,
                             holds: [Hold], who: (Int32) -> Who?, idleFor: (Int32) -> TimeInterval? = { _ in nil },
                             night: Night?, now: Date) -> [LiveCard] {
        var out: [LiveCard] = []
        let settings = "/System/Applications/System Settings.app"
        let batterySettings = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

        // Low Power Mode with the adapter: people forget it, and a busy Mac is then slow by design (rule 7)
        if onPower, lowPowerNow, lowPower?.adapter == true, busy {
            var lc = LiveCard(id: "low-power-adapter", pid: nil, card: Card(
                state: .quiet,
                headline: "Low Power Mode is on, even plugged in.",
                explanation: "It's set for the power adapter as well as battery, so heavy work runs slower by design, and the screen is a little dimmer.",
                fixes: [Fix(id: "battery-settings", title: "Open Battery settings",
                            consequence: "Change Low Power Mode to Only on Battery, or Never. It needs your password.",
                            kind: .openPage(settings, batterySettings), recommended: true)]),
                details: ["Low Power Mode: on, set for battery " + (lowPower?.battery == true ? "and" : "not") + " the power adapter"],
                reportSubject: "Low Power Mode on with the power adapter")
            lc.causeKey = "low-power-adapter"
            out.append(lc)
        }

        // one program keeping the Mac awake for hours: named, with the app it does it for (rule 12; rule 4 for the
        // sound service). Normal for a call, a download or a backup, so it says so and stays calm unless on battery
        let me = getpid()
        // an app keeping the Mac awake while it works is doing what it should: only one that has done almost nothing for
        // half an hour is shown, with how long, since that's the evidence it forgot to let go (Phil, 17 November 2026:
        // "the card for Claude is obviously wrong as it's been open working on projects, which is why it prevented sleep")
        let long = holds.filter { h in
            h.seconds >= 2 * 3600 && h.pid != me && h.name != "powerd" && h.name != "WindowServer"
                && (idleFor(h.forPID ?? h.pid) ?? 0) >= idleMinimum
        }
        if let h = long.max(by: { $0.seconds < $1.seconds }) {
            let idle = idleFor(h.forPID ?? h.pid) ?? 0
            let owner = h.forPID.flatMap(who) ?? who(h.pid)
            let name = owner?.name ?? h.name
            let sound = h.forPID != nil && h.name == "coreaudiod"
            let hours = h.seconds / 3600
            let what = h.display ? "kept your screen on" : "kept your Mac from sleeping"
            var fixes: [Fix] = []
            if let o = owner, let b = o.bundle, !o.protected {
                fixes.append(Fix(id: "quit", title: "Quit \(o.name)", consequence: "Lets your Mac sleep again. Reopening it starts fresh.", kind: .quitApp(b)).losingWork())   // Caution, so never the recommended one
            }
            var lc = LiveCard(id: "held-awake-\(h.forPID ?? h.pid)", pid: h.forPID ?? h.pid, card: Card(
                state: onPower ? .quiet : .working,
                headline: "\(name) has \(what) for \(hours) hours.",
                explanation: (sound ? "It has sound open, so macOS's sound service is holding the Mac awake for it" : "macOS lists it as asking the Mac to stay awake")
                    + ", but it has done almost nothing for \(Fmt.duration(idle)), so it has likely forgotten to let go."
                    + (onPower ? "" : " On battery, a Mac that can't sleep keeps draining."),
                fixes: fixes),
                details: ["Held awake by: \(h.name), process \(h.pid)" + (h.forPID.map { ", for process \($0)" } ?? ""),
                          "For: \(Fmt.duration(TimeInterval(h.seconds)))", h.display ? "Keeps the screen on" : "Keeps the Mac awake",
                          "Almost idle (it and what it started under \(Int(idleShare * 100))% of one core) for: \(Fmt.duration(idle))"],
                reportSubject: "a program holding the Mac awake for \(hours) hours")
            lc.causeKey = "held-awake"
            lc.displaySubject = name
            out.append(lc)
        }

        // a battery that drained overnight while the Mac kept waking (rule 12): shown for the morning after
        if let n = night, n.onBattery, let drop = n.drop, drop >= 10, n.to.timeIntervalSince(n.from) >= 4 * 3600,
           now.timeIntervalSince(n.to) < 6 * 3600, n.total >= 10 {
            let top = n.wakes.max { $0.value < $1.value }!
            let network = top.key == "the network"
            var lc = LiveCard(id: "night-wakes", pid: nil, card: Card(
                state: .quiet,
                headline: "Your Mac lost \(drop)% of its battery while asleep, waking \(n.total) times.",
                // what woke it most, in words that say what it is (Phil, 19 November 2026: "the explanation about wakes isn't clear")
                explanation: "It slept from \(Fmt.time(n.from)) to \(Fmt.time(n.to)). " + (whyWoke[top.key] ?? "Most wakes were for \(top.key).")
                    + " A sleeping Mac usually loses only a few percent overnight.",
                fixes: [Fix(id: "battery-options", title: "Open Battery settings",
                            consequence: network ? "Under Options, Wake for network access can be set to Only on Power Adapter." : "Under Options, Power Nap and waking for the network can be turned down.",
                            kind: .openPage(settings, batterySettings), recommended: true)]),
                details: ["Slept: \(Fmt.time(n.from)) to \(Fmt.time(n.to))", "Charge: \(n.chargeFrom ?? 0)% to \(n.chargeTo ?? 0)%"]
                    + n.wakes.sorted { $0.value > $1.value }.map { "Woke for \($0.key): \($0.value)" },
                reportSubject: "battery drained overnight while asleep")
            lc.causeKey = "night-wakes"
            out.append(lc)
        }
        return out
    }

    /// Reads all three, off the main thread. The log is the slow one (about 2 seconds), so `log` is false between wakes.
    public static func read(log: Bool) -> (LowPower?, [Hold], Night?) {
        func run(_ args: [String]) -> String? { Hardware.run("/usr/bin/pmset", args).map { String(decoding: $0, as: UTF8.self) } }
        return (run(["-g", "custom"]).flatMap(parseCustom), run(["-g", "assertions"]).map(parseAssertions) ?? [],
                log ? run(["-g", "log"]).flatMap(parseLog) : nil)
    }
}

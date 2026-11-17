import Foundation

/// Checks for the power cards (see PowerState.swift): `pmset`'s three reports read right, each card appears only when
/// it explains something (a busy Mac in Low Power Mode on the adapter, hours held awake, a battery drained overnight),
/// names the app it's about, and leaves the action to its option.
extension Fixture {
    static let customText = """
    Battery Power:
     lowpowermode         1
     powernap             1
    AC Power:
     lowpowermode         1
     womp                 1
    """
    static let assertionsText = """
    Assertion status system-wide:
       PreventUserIdleSystemSleep     1
    Listed by owning process:
       pid 642(zoom.us): [0x0000002a00018180] 38:44:59 NoIdleSleepAssertion named: "Electron"
       pid 300(coreaudiod): [0x0001af2f00018c5c] 05:12:03 PreventUserIdleSystemSleep named: "com.apple.audio.context"
    \tCreated for PID: 812.
       pid 400(WindowServer): [0x0001b1b200098cc0] 00:00:01 UserIsActive named: "com.apple.iohideventsystem.queue.tickle"
    \tTimeout will fire in 118 secs Action=TimeoutActionRelease
       pid 341(powerd): [0x0001b1b200018cc1] 03:04:04 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
    No kernel assertions.
    """
    /// A night on battery, 11:40pm to 7:15am: 85% to 66%, 23 wakes for the network and 7 for upkeep.
    static func logText() -> String {
        var lines = ["2026-11-15 23:40:02 -0500 Sleep               \tEntering Sleep state due to 'Clamshell Sleep': Using Batt (Charge:85%) 900 secs"]
        for i in 0..<30 {
            let reason = i % 4 == 3 ? "NUB.SPMI0.SW3 nub-spmi0.0x02 rtc/Maintenance" : "wifibt"
            lines.append(String(format: "2026-11-16 %02d:%02d:10 -0500 DarkWake            \tDarkWake from Deep Idle [CDNPB] : due to %@ Using BATT (Charge:%d%%) 45 secs", 0 + i / 5, (i * 11) % 60, reason, 84 - i / 2))
        }
        lines.append("2026-11-16 07:15:40 -0500 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion Using BATT (Charge:66%) 4 secs")
        return lines.joined(separator: "\n")
    }
    static func who(_ pid: Int32) -> PowerState.Who? {
        switch pid {
        case 642: return PowerState.Who(name: "Zoom", bundle: "/Applications/zoom.us.app")
        case 812: return PowerState.Who(name: "Safari", bundle: "/Applications/Safari.app")
        case 900: return PowerState.Who(name: "Falcon", bundle: "/Applications/Falcon.app", protected: true)
        default: return nil
        }
    }

    static func powerStateChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let morning = PowerState.logDate.date(from: "2026-11-16 08:00:00 -0500")!

        // the three reports read right
        let lp = PowerState.parseCustom(customText)
        let holds = PowerState.parseAssertions(assertionsText)
        let night = PowerState.parseLog(logText())
        let r1 = lp == PowerState.LowPower(battery: true, adapter: true)
            && holds.map(\.name) == ["zoom.us", "coreaudiod", "powerd"] && holds[0].seconds == 38 * 3600 + 44 * 60 + 59
            && holds[1].forPID == 812 && holds[0].forPID == nil
            && night?.chargeFrom == 85 && night?.chargeTo == 66 && night?.drop == 19 && night?.onBattery == true
            && night?.wakes["the network"] == 23 && night?.wakes["macOS's own upkeep"] == 7
        review.append(("power-reads", r1, "Low Power Mode \(lp.map { "\($0)" } ?? "none"); holds \(holds.map { "\($0.name) \($0.seconds)s" }); night \(night.map { "\($0.total) wakes, \($0.drop ?? 0)%" } ?? "none")"))

        // Low Power Mode on the adapter: only plugged in, busy, and set for the adapter
        func cards(onPower: Bool = true, busy: Bool = true, lowPower: PowerState.LowPower? = lp, holds h: [PowerState.Hold] = [],
                   night n: PowerState.Night? = nil) -> [LiveCard] {
            PowerState.cards(lowPower: lowPower, lowPowerNow: true, onPower: onPower, busy: busy, holds: h, who: who, night: n, now: morning)
        }
        let low = cards()
        let l1 = low.map(\.id) == ["low-power-adapter"] && cards(busy: false).isEmpty && cards(onPower: false).isEmpty
            && cards(lowPower: PowerState.LowPower(battery: true, adapter: false)).isEmpty
        review.append(("power-low-adapter", l1, low.first.map { $0.card.headline + " " + $0.card.explanation } ?? "none"))

        // held awake for hours: the app named, the sound service credited to the app it works for, a quit option
        // (never for security software), calm when plugged in
        let held = cards(busy: false, lowPower: nil, holds: holds)
        let sound = cards(busy: false, lowPower: nil, holds: [holds[1]])
        let guarded = cards(busy: false, lowPower: nil, holds: [PowerState.Hold(pid: 900, name: "falcond", seconds: 9000, display: false)])
        let short = cards(busy: false, lowPower: nil, holds: [PowerState.Hold(pid: 642, name: "zoom.us", seconds: 3600, display: false)])
        let onBattery = cards(onPower: false, busy: false, lowPower: nil, holds: holds)
        let h1 = held.first?.card.headline == "Zoom has kept your Mac from sleeping for 38 hours." && held.first?.card.state == .quiet
            && held.first?.card.fixes.first?.title == "Quit Zoom" && held.first?.card.fixes.first?.caution == true
            && sound.first?.card.headline == "Safari has kept your Mac from sleeping for 5 hours."
            && sound.first?.card.explanation.hasPrefix("It has sound open") == true
            && guarded.first?.card.fixes.isEmpty == true && short.isEmpty
            && onBattery.first?.card.state == .working && (held + sound + onBattery).allSatisfy { $0.card.fixes.allSatisfy { !$0.recommended } }
        review.append(("power-held-awake", h1, (held + sound).map(\.card.headline).joined(separator: " | ")))

        // overnight: shown the morning after a 10%+ drop on battery with 10+ wakes, naming what woke it most
        let nightCards = cards(busy: false, lowPower: nil, night: night)
        var plugged = night!; plugged.onBattery = false
        var small = night!; small.chargeTo = 80
        let n1 = nightCards.first?.card.headline == "Your Mac lost 19% of its battery while asleep, waking 30 times."
            && nightCards.first?.card.explanation.contains("Most wakes were for the network") == true
            && cards(busy: false, lowPower: nil, night: plugged).isEmpty && cards(busy: false, lowPower: nil, night: small).isEmpty
            && PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: true, busy: false, holds: [], who: who, night: night,
                                now: morning.addingTimeInterval(8 * 3600)).isEmpty
        review.append(("power-night-wakes", n1, nightCards.first.map { $0.card.headline + " " + $0.card.explanation } ?? "none"))

        // the text gives the verdict and the evidence; the option carries the action, never repeated in the text
        let all = low + held + sound + onBattery + nightCards
        let w1 = all.allSatisfy { c in c.card.fixes.allSatisfy { !(c.card.headline + " " + c.card.explanation).contains($0.title) } }
        review.append(("power-wording", w1, "\(all.count) cards: no option title in the text"))

        // this Mac, as any user, quickly. Low Power Mode isn't listed on every Mac (none on GitHub's virtual build Mac,
        // which has no battery), so only the time is checked; the parsing is checked above
        let t = Date()
        let (live, liveHolds, _) = PowerState.read(log: false)
        let took = Date().timeIntervalSince(t)
        review.append(("power-live-read", took < 2, String(format: "%.2f s; Low Power Mode read: %@; %d programs holding the Mac awake", took, live == nil ? "no" : "yes", liveHolds.count)))
        return review
    }

    /// For `coolhead wording` and screenshots: each power card, from the made-up readings above.
    static func powerStateSamples(_ now: Date) -> [(String, Card)] {
        let morning = PowerState.logDate.date(from: "2026-11-16 08:00:00 -0500")!
        let holds = PowerState.parseAssertions(assertionsText)
        func one(_ c: [LiveCard]) -> Card? { c.first?.card }
        return [
            ("power-low-adapter", one(PowerState.cards(lowPower: PowerState.parseCustom(customText), lowPowerNow: true, onPower: true, busy: true, holds: [], who: who, night: nil, now: morning))),
            ("power-held-awake", one(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: true, busy: false, holds: [holds[0]], who: who, night: nil, now: morning))),
            ("power-held-awake-sound", one(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: false, busy: false, holds: [holds[1]], who: who, night: nil, now: morning))),
            ("power-night-wakes", one(PowerState.cards(lowPower: nil, lowPowerNow: false, onPower: false, busy: false, holds: [], who: who, night: PowerState.parseLog(logText()), now: morning))),
        ].compactMap { k, c in c.map { (k, $0) } }
    }
}

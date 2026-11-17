import AppKit
import CoolHeadCore
import Observation

/// Keeps the power cards (see PowerState.swift) current: Low Power Mode and what's holding the Mac awake every 5
/// minutes and when the panel opens (at most once a minute), each under a hundredth of a second; the sleep log, about 2
/// seconds of work, at launch and after each wake only.
@MainActor @Observable
final class PowerWatch {
    static let shared = PowerWatch()

    private(set) var cards: [LiveCard] = []
    @ObservationIgnored private var lowPower: PowerState.LowPower?
    @ObservationIgnored private var holds: [PowerState.Hold] = []
    @ObservationIgnored private var night: PowerState.Night?
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private weak var watcher: Watcher?

    private var snapshot: Bool { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil }

    func start(_ watcher: Watcher) {
        self.watcher = watcher
        guard !snapshot else { return }
        refresh(force: true, log: true)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in Task { @MainActor in PowerWatch.shared.refresh(force: true) } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PowerWatch.shared.refresh(force: true, log: true) }
        }
    }

    func refresh(force: Bool = false, log: Bool = false) {
        guard !reading, !snapshot else { return }
        let now = Date()
        if !force, let last = lastRead, now.timeIntervalSince(last) < 60 { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let (lp, holds, night) = PowerState.read(log: log)
            DispatchQueue.main.async {
                let w = PowerWatch.shared
                w.lowPower = lp; w.holds = holds
                if log { w.night = night }
                w.lastRead = now
                w.reading = false
                w.rebuild(now: now)
            }
        }
    }

    /// The cards, from the last readings and the watcher's view of the Mac now.
    func rebuild(now: Date = Date()) {
        guard let watcher else { return }
        let mac = watcher.mac
        // busy: something is working hard, or the Mac is warm; that's when Low Power Mode explains slowness
        let busy = mac.thermal != "nominal" || watcher.cards.contains { $0.pid != nil && $0.card.state != .quiet }
        cards = PowerState.cards(lowPower: lowPower, lowPowerNow: ProcessInfo.processInfo.isLowPowerModeEnabled, onPower: mac.onPower,
                                 busy: busy, holds: holds, who: PowerWatch.who, night: night, now: now)
    }

    /// A process's app name and bundle, as the cards name it: the app's own name where it's an installed app.
    nonisolated static func who(_ pid: Int32) -> PowerState.Who? {
        guard let path = Proc.path(pid) else { return nil }
        var bundle: String?
        if let r = path.range(of: ".app/") {
            let b = String(path[..<r.lowerBound]) + ".app"
            if b.hasPrefix("/Applications/") || b.hasPrefix(NSHomeDirectory() + "/Applications/") { bundle = b }
        }
        let name = bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? (path as NSString).lastPathComponent
        return PowerState.Who(name: name, bundle: bundle, protected: SecuritySoftware.product(path: path, name: name) != nil)
    }

    /// The cards to show: those the person hasn't chosen to wait on (the clock in a card's corner).
    func visible(_ watcher: Watcher, now: Date = Date()) -> [LiveCard] {
        cards.filter { c in watcher.snoozed[c.cause].map { $0.until <= now || c.severity > $0.severity } ?? true }
    }
}

extension PowerWatch: CardSource {
    func panelOpened() { refresh() }       // at most once a minute
    func cards(for watcher: Watcher) -> [LiveCard] { visible(watcher) }
}

import AppKit
import CoolHeadCore
import Observation

/// Keeps the hardware checks (see Hardware.swift) current and turns them into cards for the panel, drawn like any other
/// card. The checks are cheap (under a third of a second on the Mac it was built on), so they run at launch, after
/// each wake, when the panel opens (at most once a minute), and every 10 minutes; System Information's battery report,
/// the slowest part, at most once an hour.
@MainActor @Observable
final class HardwareWatch {
    static let shared = HardwareWatch()

    private(set) var report: HardwareReport?
    private(set) var cards: [LiveCard] = []
    /// Called with a short line, once per finding that needs a look, so the person hears about it without opening the
    /// panel. It never names a project or file; macOS keeps notification text.
    @ObservationIgnored var onAlert: ((String) -> Void)?

    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var lastProfile: Date?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var alerted: Set<String> = []

    /// Screenshots show made-up cards (COOLHEAD_SNAPSHOT_SAMPLES, which includes every hardware card as "hardware-…")
    /// or only some cards (COOLHEAD_SNAPSHOT_ONLY), never this Mac's own hardware findings.
    private var snapshot: Bool { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil }

    func start() {
        refresh(force: true)
        guard !snapshot else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in Task { @MainActor in HardwareWatch.shared.refresh(force: true) } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in HardwareWatch.shared.refresh(force: true) }
        }
    }

    /// Reads the checks again, off the main thread. Without `force`, at most once a minute (for the panel opening).
    func refresh(force: Bool = false) {
        guard !reading else { return }
        let now = Date()
        if !force, let last = lastRead, now.timeIntervalSince(last) < 60 { return }
        let profile = lastProfile.map { now.timeIntervalSince($0) > 3600 } ?? true
        reading = true
        DispatchQueue.global(qos: .utility).async {
            var fresh = HardwareReport.read(profile: profile, now: now)
            DispatchQueue.main.async {
                let watch = HardwareWatch.shared
                // between System Information reads, keep the condition and Maximum Capacity it last gave
                if !profile, var b = fresh.battery, let old = watch.report?.battery {
                    b.condition = old.condition; b.maxCapacity = old.maxCapacity; fresh.battery = b
                }
                if profile { watch.lastProfile = now }
                watch.report = fresh
                watch.cards = watch.snapshot ? [] : fresh.cards(now: now)
                watch.lastRead = now
                watch.reading = false
                for c in watch.cards where c.needsLook && !watch.alerted.contains(c.id) {
                    watch.alerted.insert(c.id)
                    watch.onAlert?("Cool Head found something about this Mac's hardware worth a look.")
                }
            }
        }
    }

    /// The cards to show: those the person hasn't chosen to wait on (the clock in a card's corner).
    func visible(_ watcher: Watcher, now: Date = Date()) -> [LiveCard] {
        cards.filter { c in watcher.snoozed[c.cause].map { $0.until <= now || c.severity > $0.severity } ?? true }
    }

    /// Whether a hardware finding should turn the menu bar badge yellow.
    func needsLook(_ watcher: Watcher) -> Bool { visible(watcher).contains { $0.needsLook } }
}

extension HardwareWatch: CardSource {
    func start(_ watcher: Watcher) { start() }
    func panelOpened() { refresh() }       // at most once a minute
    func cards(for watcher: Watcher) -> [LiveCard] { visible(watcher) }
}

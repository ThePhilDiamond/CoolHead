import AppKit
import CoolHeadCore
import Observation

/// Keeps the crash-loop cards (see CrashLoops.swift) current: at launch, every 10 minutes, after each wake, and when the
/// panel opens (at most once a minute). Listing the two crash folders and reading the first line of the day's reports
/// takes a few hundredths of a second.
@MainActor @Observable
final class CrashWatch {
    static let shared = CrashWatch()

    private(set) var cards: [LiveCard] = []
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var timer: Timer?

    private var snapshot: Bool { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil }

    func start() {
        guard !snapshot else { return }
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in Task { @MainActor in CrashWatch.shared.refresh(force: true) } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CrashWatch.shared.refresh(force: true) }
        }
    }

    func refresh(force: Bool = false) {
        guard !reading, !snapshot else { return }
        let now = Date()
        if !force, let last = lastRead, now.timeIntervalSince(last) < 60 { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let cards = CrashLoops.cards(CrashLoops.loops(CrashLoops.read(now: now).crashes, now: now))
            DispatchQueue.main.async {
                let w = CrashWatch.shared
                w.cards = cards; w.lastRead = now; w.reading = false
            }
        }
    }

    /// The cards to show: those the person hasn't chosen to wait on (the clock in a card's corner).
    func visible(_ watcher: Watcher, now: Date = Date()) -> [LiveCard] {
        cards.filter { c in watcher.snoozed[c.cause].map { $0.until <= now || c.severity > $0.severity } ?? true }
    }
}

extension CrashWatch: CardSource {
    func start(_ watcher: Watcher) { start() }
    func panelOpened() { refresh() }       // at most once a minute
    func cards(for watcher: Watcher) -> [LiveCard] { visible(watcher) }
}

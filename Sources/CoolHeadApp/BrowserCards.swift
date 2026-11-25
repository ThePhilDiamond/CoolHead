import AppKit
import CoolHeadCore
import Observation

/// Keeps the browser cards (see BrowserTampering.swift) current: every 10 minutes and when the panel opens (at most once
/// a minute). Reading three browsers' policy names, the enrollment status and the browsers' arguments takes a few
/// hundredths of a second.
@MainActor @Observable
final class BrowserWatch {
    static let shared = BrowserWatch()

    private(set) var cards: [LiveCard] = []
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var timer: Timer?

    private var snapshot: Bool { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil }

    func start() {
        guard !snapshot else { return }
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in Task { @MainActor in BrowserWatch.shared.refresh(force: true) } }
    }

    func refresh(force: Bool = false) {
        guard !reading, !snapshot else { return }
        let now = Date()
        if !force, let last = lastRead, now.timeIntervalSince(last) < 60 { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let r = BrowserTampering.read()
            let cards = BrowserTampering.cards(policies: r.policies, managed: r.managed, scripted: r.scripted)
            DispatchQueue.main.async {
                let w = BrowserWatch.shared
                w.cards = cards; w.lastRead = now; w.reading = false
            }
        }
    }

    /// The cards to show: those the person hasn't chosen to wait on (the clock in a card's corner).
    func visible(_ watcher: Watcher, now: Date = Date()) -> [LiveCard] {
        cards.filter { !watcher.isWaitedOn($0, now: now) }
    }

}

extension BrowserWatch: CardSource {
    func start(_ watcher: Watcher) { start() }
    func panelOpened() { refresh() }       // at most once a minute
    func cards(for watcher: Watcher) -> [LiveCard] { visible(watcher) }
}

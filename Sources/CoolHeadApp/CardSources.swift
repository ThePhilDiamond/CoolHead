import CoolHeadCore

/// A source of cards about the Mac as a whole, beside the watcher's own process cards: the hardware checks, the power
/// state, and so on. Each keeps its own readings and timers; the app only starts them, tells them when the panel
/// opens, and shows their cards.
@MainActor
protocol CardSource: AnyObject {
    /// Starts its readings (a screenshot copy reads nothing of this Mac's own).
    func start(_ watcher: Watcher)
    /// The panel is opening: read again if the last reading is more than a minute old.
    func panelOpened()
    /// Its cards, less those the person has chosen to wait on.
    func cards(for watcher: Watcher) -> [LiveCard]
    /// Whether one of them should turn the menu bar badge yellow.
    func needsLook(_ watcher: Watcher) -> Bool
}

extension CardSource {
    func needsLook(_ watcher: Watcher) -> Bool { cards(for: watcher).contains { $0.needsLook } }
}

/// Every card source, in one place, so a new kind of card is one line here and nowhere else (Phil, 17 November 2026:
/// "we need to make sure it doesn't compromise the architecture/security of the app"). The list is fixed when the app
/// is built: nothing is loaded or chosen while it runs. One per line, alphabetical, so changes made at the same time
/// add their lines in different places. Each source says it's a CardSource in its own file. To see what starts at
/// launch, read this list.
@MainActor
enum CardSources {
    static let all: [any CardSource] = [
        BrowserWatch.shared,
        HardwareWatch.shared,
        PowerWatch.shared,
    ]
}

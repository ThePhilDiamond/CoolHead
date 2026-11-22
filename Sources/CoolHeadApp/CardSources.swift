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
}

extension Watcher {
    /// The level the menu bar icon shows: every card on screen, the watcher's and every source's, by the same rule as
    /// the snowflake at the top of the panel (`Watcher.level(_:)`).
    @MainActor var screenLevel: Level { level(cards + CardSources.all.flatMap { $0.cards(for: self) }) }
}

// Every card source is listed in `CardSources.all`, which the build writes from the file names (Plugins/Lists): each
// <Name>Cards.swift file declares `<Name>Watch.shared`, a CardSource, so a new kind of card is one new file and no
// edit anywhere else. That ease costs nothing in the app's architecture or security: the list is fixed when the app is
// built, and nothing is loaded or chosen while it runs. To see what starts at launch, list the *Cards.swift files, or
// read the generated file in .build/plugins/outputs.

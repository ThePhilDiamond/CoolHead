import Foundation

/// Whether a busy process is doing its job, and how we know.
public enum JobState: String {
    case working      // progress advancing, or output still being written
    case waiting      // queued behind another job
    case stalled      // no progress for a long time: the only state where stopping is offered
    case unknown      // busy for a long time, with no sign either way
    case starting     // busy, but only just started
    case quiet        // not busy
}

public enum Health {
    /// Minutes without progress before a job counts as stalled (COOLHEAD_STALL_MINUTES overrides it, for testing).
    public static var stallMinutes: Double {
        Double(ProcessInfo.processInfo.environment["COOLHEAD_STALL_MINUTES"] ?? "") ?? 30
    }

    /// `busySince`: when the watcher first saw it busy; without it, the process's start time is used.
    public static func assess(_ e: Evidence, now: Date = Date(), busySince: Date? = nil) -> JobState {
        let busy = e.coresNow >= 0.25 || e.gpuBusy             // on the CPU or the graphics chip
        let ran = now.timeIntervalSince(busySince ?? e.start ?? now)
        if let l = e.lastLine?.lowercased(), l.contains("waiting"), e.coresNow < 0.1, (e.gpuShare ?? 0) < 0.1 { return .waiting }
        if let p = e.progress {
            // stalled: quiet for longer than the limit and than three of its own usual gaps between progress lines,
            // and not writing anything now. A job that reports itself done, or is still writing (saving a large
            // result, say), is working, however long ago its last progress line was.
            let limit = max(stallMinutes, 3 * (p.typicalGapMinutes ?? 0))
            let writingNow = e.bytesWrittenDuringSample > 0 || (e.lastOutput.map { now.timeIntervalSince($0) < limit * 60 } ?? false)
                && e.lastOutput != p.lineTime
            if p.fraction == 1 || writingNow { return .working }
            return now.timeIntervalSince(p.lineTime) > limit * 60 ? .stalled : .working
        }
        if e.bytesWrittenDuringSample > 0 || (e.lastOutput.map { now.timeIntervalSince($0) < 600 } ?? false) {
            return busy || ran < 600 ? .working : .quiet
        }
        if busy && ran < 20 * 60 { return .starting }
        return busy ? .unknown : .quiet
    }
}

/// One thing the user can do about a card, with what it would cause.
public struct Fix: Identifiable {
    public enum Kind: Equatable {
        case wait(Date)          // hide the card until then; it comes back if the cause is still there
        case stop                // SIGTERM, after asking; only the user's own processes
        case cooler              // background priority: slower CPU and disk access, less heat
        case cpuCap(CPUCap.Offer)   // stopped and continued many times a second to hold it to a fixed share of one core: a fifth, a half, or one whole (see CPUCap.Level)
        case lookUp(String)      // a web search for this process name only
        case quitApp(String)     // a normal quit of the app at this bundle path, so it can ask to save
        // Every option is a button, since a mix of buttons and plain text is confusing: even an option that only leads
        // to a guide, or explains how to do the task, is something to click. What Cool Head can't do itself, it takes
        // you to, or shows how:
        case openApp(String, String)    // bring this app (bundle path) forward, then say these steps
        case reveal(String, String)     // show this folder in Finder, then say these steps
        case guide([String])            // a mini-guide: these steps, numbered, under the option
        case share               // show the anonymised case report, then offer to open it as a GitHub issue
        case openPage(String, String)   // open a page of an app's own settings in that app: bundle path, address
        case pauseJob            // SIGSTOP until the Mac is plugged in; resumed then, or on request, or when Cool Head quits
        case pauseSync(String, String)  // open a sync app (bundle path, name) to pause it, with a reminder to resume
        case resume              // SIGCONT for a process something other than Cool Head paused
        case forceQuit           // SIGKILL for an app that isn't responding, after asking: what Force Quit in the Apple menu does
        case restartBrowser(String)   // a normal quit of the browser at this bundle path, then reopen it with its last session
        case stopAgent(String, String)   // turn off another app's background helper (launchd label, its plist path): stopped now and at every login; undo any time
        case keepOutOfBackup(String)     // keep this folder out of Time Machine backups (a sticky exclusion, as tmutil addexclusion); undo any time
        case stopAndTrash([String], String?)  // a program pretending to be macOS's (see Disguise): turn off its launch item (this plist), stop it, and move these files to the Trash
        case restartApp(String)          // a normal quit of the app at this bundle path, then open it again (a leak: see Leaks)
        case unloadModels([String])      // ask Ollama to unload these models now (see Leftovers); the next question loads one again
        case chromeCompanion(String)     // ask Cool Head for Chrome to do this: a ChromeLink.Action's name, or "setup" (see ChromeCompanion)
        case deleteBuildData(String)     // delete the contents of Xcode's DerivedData folder, after asking; Xcode rebuilds what it needs
    }
    public let id: String
    public let title: String
    /// What the option does, in its own words, as it was made.
    public let own: String
    /// Set by the card while a restart of the same app sits beside this quit (see `Card.marked`).
    public internal(set) var whenDone = false
    /// What the option does: its own words, after "Use this only if you are no longer using it." while a restart of the
    /// same app is beside it on the card, so the two don't read as the same choice. Worked out from the options the card
    /// holds now, so the words go when the restart does.
    public var consequence: String { whenDone ? [Card.whenDoneWords, own].filter { !$0.isEmpty }.joined(separator: " ") : own }
    public let kind: Kind
    public var recommended = false
    /// Set where the option is made when it differs from its kind's usual result (see `result`).
    public var resultOverride: Result? = nil
    /// Offered, but never made the recommendation by the one-click rule (see `Card.init`): set where the option is made,
    /// for a reason that place knows (slowing the tab you're using, for one).
    public var holdBack = false
    /// Set where the option is made when what it loses differs from its kind's usual (see `caution`).
    public var cautionOverride: Bool? = nil

    public init(id: String, title: String, consequence: String, kind: Kind, recommended: Bool = false,
                resultOverride: Result? = nil, holdBack: Bool = false, cautionOverride: Bool? = nil) {
        self.id = id; self.title = title; self.own = consequence; self.kind = kind; self.recommended = recommended
        self.resultOverride = resultOverride; self.holdBack = holdBack; self.cautionOverride = cautionOverride
    }

    /// The app (bundle path) this option quits and opens again, if it is a restart.
    public var restarts: String? {
        switch kind {
        case .restartBrowser(let b), .restartApp(let b): return b
        default: return nil
        }
    }

    /// An option that opens an app and says what to do there.
    public static func openApp(_ id: String, _ title: String, bundle: String, steps: String, recommended: Bool = false) -> Fix {
        let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return Fix(id: id, title: title, consequence: "This opens \(app). \(steps)", kind: .openApp(bundle, steps), recommended: recommended)
    }

    /// An option that shows how to do something Cool Head can't do itself: `steps` appear under it when pressed.
    public static func guide(_ id: String, _ title: String, _ consequence: String, steps: [String], recommended: Bool = false) -> Fix {
        Fix(id: id, title: title, consequence: consequence, kind: .guide(steps), recommended: recommended)
    }

    static let activityMonitor = "/System/Applications/Utilities/Activity Monitor.app"

    /// Who does the work when this option is pressed: Cool Head itself, or you, with Cool Head opening the place or
    /// showing the steps. The two look different in the panel, so it's clear at a glance which options are a task for
    /// you and which Cool Head does itself.
    public enum Doer { case coolHead, you }
    public var doer: Doer {
        // one kind per line, with no default, so a new kind can't be added without saying who does it
        switch kind {
        case .wait: return .coolHead
        case .stop: return .coolHead
        case .cooler, .cpuCap: return .coolHead
        case .quitApp: return .coolHead
        case .pauseJob: return .coolHead
        case .resume: return .coolHead
        case .forceQuit: return .coolHead
        case .restartBrowser: return .coolHead
        case .stopAgent: return .coolHead
        case .keepOutOfBackup: return .coolHead
        case .stopAndTrash: return .coolHead
        case .restartApp: return .coolHead
        case .unloadModels: return .coolHead
        case .chromeCompanion: return .coolHead
        case .deleteBuildData: return .coolHead
        case .lookUp: return .you          // opens a web search for you to read
        case .openApp: return .you         // opens the app; you do the steps there
        case .reveal: return .you          // shows the folder in Finder; you do the steps there
        case .guide: return .you           // shows the steps
        case .openPage: return .you        // opens the settings page; you change it
        case .pauseSync: return .you       // opens the sync app; you pause it there (Cool Head only reminds you)
        case .share: return .you           // shows the report; you choose whether to send it
        }
    }

    /// What pressing it does about the problem: ends the cause, eases it, or only tells you more. Options are ordered
    /// by this within their group, and a task that fixes the cause says so beside a one-click recommendation that
    /// doesn't, so it's clear when doing something yourself would work better.
    public enum Result: Int, Comparable {
        case informs = 0, eases = 1, fixesCause = 2
        public static func < (a: Result, b: Result) -> Bool { a.rawValue < b.rawValue }
    }
    public var result: Result {
        if let resultOverride { return resultOverride }
        switch kind {
        case .wait: return .informs
        case .stop: return .fixesCause
        case .cooler, .cpuCap: return .eases
        case .lookUp: return .informs
        case .quitApp: return .fixesCause
        case .openApp: return .eases
        case .reveal: return .eases
        case .guide: return .eases
        case .share: return .informs
        case .openPage: return .eases
        case .pauseJob: return .eases
        case .pauseSync: return .eases
        case .resume: return .fixesCause
        case .forceQuit: return .fixesCause
        case .restartBrowser: return .fixesCause
        case .stopAgent: return .fixesCause        // it can't start again by itself
        case .keepOutOfBackup: return .fixesCause  // later backups skip what the job keeps rewriting
        case .stopAndTrash: return .fixesCause     // it can't run or start again unless put back from the Trash
        case .restartApp: return .fixesCause       // the memory it had built up is given back
        case .unloadModels: return .fixesCause     // the model's memory is free at once
        case .chromeCompanion(let a): return a == "setup" ? .informs : .fixesCause   // setting up the extension helps later, not now, so it's never promoted
        case .deleteBuildData: return .fixesCause  // the space is free at once
        }
    }
    /// What it does about the problem, as the tag every option shows: one of `impacts`, so each word means one thing on
    /// every card (docs/CARD-TEMPLATE.md, Option cues).
    public var impact: String {
        // setting up the extension does nothing now, but makes later cards able to do more
        if case .chromeCompanion("setup") = kind, resultOverride == nil { return "Helps later" }
        switch result {
        case .fixesCause: return "Fixes the cause"
        case .eases: return "Helps"
        case .informs: return "Tells you more"
        }
    }
    public static let impacts = ["Fixes the cause", "Helps", "Helps later", "Tells you more"]
    /// The same option, marked as one that ends the cause.
    public func fixingTheCause() -> Fix { var f = self; f.resultOverride = .fixesCause; return f }
    /// The same option, marked as losing something reopening can't bring back (see `caution`).
    public func losingWork() -> Fix { var f = self; f.cautionOverride = true; return f }

    /// Closes something you can see: ends it (`interrupts`), or closes tabs (duplicates, hidden groups). What the
    /// recommendation's line calls "without closing anything" is read from this.
    public var closesSomething: Bool {
        if interrupts { return true }
        if case .chromeCompanion(let a) = kind { return a == "closeDuplicates" || a == "hideUnusedGroups" }
        return false
    }
    /// What marks an option as done on a card (see `Card.after`): its id and what it acts on, so an id the card reuses
    /// for another target (Quit Slack, then Quit Xcode, both "quit") isn't taken as done.
    public var doneKey: String { id + "|" + String(describing: kind) }
    /// Ends or closes something (a process, an app, a browser), whether or not anything is lost: the one-click rule never
    /// puts one of these in place of a task (see `Card.init`). Whether it's risky is `caution`.
    public var interrupts: Bool {
        switch kind {
        case .stop: return true
        case .quitApp: return true
        case .forceQuit: return true
        case .restartBrowser: return true
        case .stopAgent: return true
        case .keepOutOfBackup: return false
        case .stopAndTrash: return true
        case .restartApp: return true
        case .unloadModels: return false
        case .chromeCompanion: return false
        case .deleteBuildData: return false
        case .wait: return false
        case .cooler, .cpuCap: return false
        case .lookUp: return false
        case .openApp: return false
        case .reveal: return false
        case .guide: return false
        case .share: return false
        case .openPage: return false
        case .pauseJob: return false
        case .pauseSync: return false
        case .resume: return false
        }
    }

    /// Has consequences that are unknown or can't be undone, so there is risk: labelled Caution, with a warning sign, in
    /// its group, not moved apart from the others. Caution is kept for real risk, such as ending a process with unknown
    /// or irreversible consequences; quitting an app like Slack isn't risky.
    public var caution: Bool {
        if let cautionOverride { return cautionOverride }
        switch kind {
        case .stop: return true            // ends a process without asking it to save
        case .quitApp: return false        // the app asks to save; a quit that loses more is marked losingWork() where it's made
        case .forceQuit: return true       // ends an app without asking it to save
        case .restartBrowser: return true  // private windows, unsent form text and downloads in progress don't come back
        case .stopAgent: return true       // what the helper does for its app (updates, sync, a licence check) isn't known, so stopping it may break something
        case .stopAndTrash: return true       // what the program was doing isn't known; it can be put back from the Trash
        case .restartApp: return false        // the app asks to save; one that loses more is marked losingWork() where it's made
        case .unloadModels: return false      // nothing is lost: the next question loads it again
        case .chromeCompanion: return false   // asleep tabs stay in the tab bar; protected tabs stay awake
        case .deleteBuildData: return false   // nothing is lost: Xcode rebuilds it, at the cost of a slower next build
        case .keepOutOfBackup: return false   // known and undoable: only rebuildable build output is offered, and the option says it won't be backed up
        case .wait: return false
        case .cooler, .cpuCap: return false
        case .lookUp: return false
        case .openApp: return false
        case .reveal: return false
        case .guide: return false
        case .share: return false
        case .openPage: return false
        case .pauseJob: return false
        case .pauseSync: return false
        case .resume: return false
        }
    }
}

extension Fix {
    /// Why an option is marked Caution, in one sentence, shown on the option at the first click, which asks for a
    /// second to go ahead, so the warning always says why; nil when it isn't. One kind per line, with no default, so a
    /// new kind says its reason.
    public var cautionReason: String? {
        guard caution else { return nil }
        switch kind {
        case .stop: return "It ends at once, without a chance to save or finish what it was doing."
        case .forceQuit: return "The app ends at once, without a chance to save."
        case .restartBrowser: return "Private windows, text typed into pages, and downloads in progress do not open again."
        case .stopAgent: return "What it does for its app, such as updates or syncing, stops too, so the app may not work as it should."
        case .stopAndTrash: return "It ends at once, and anything that relies on it stops working until you put it back from the Trash."
        case .restartApp: return "What it's in the middle of stops, and reopening it may not pick up where it left off."
        case .unloadModels: return nil
        case .chromeCompanion: return nil
        case .deleteBuildData: return nil
        // a quit marked losingWork() where it's made: its description says what is lost
        case .quitApp: return "What it's in the middle of stops, and reopening it may not pick up where it left off."
        case .keepOutOfBackup: return "It will not be in your backups."
        case .wait: return nil
        case .cooler, .cpuCap: return nil
        case .lookUp: return nil
        case .openApp: return nil
        case .reveal: return nil
        case .guide: return nil
        case .share: return nil
        case .openPage: return nil
        case .pauseJob: return nil
        case .pauseSync: return nil
        case .resume: return nil
        }
    }
}

/// What the user sees: one sentence saying what it is and whether it is fine; behind "Explore fixes", a short
/// explanation of how we know, and the options, each with its consequence, one of them recommended.
public struct Card {
    public let state: JobState
    public let headline: String
    public let explanation: String
    public private(set) var fixes: [Fix]
    /// The card's own recommendation where the one-click rule put an option in one click in its place (see `init`): it
    /// is the next one shown once that option is done (see `after`). Nil where the card's own pick stood.
    public internal(set) var displaced: String? = nil
    /// The processes this card names, as shown (see `Naming`): checked to be told apart on every example card.
    public var names: [String] = []
    /// Facts behind the card that its text leaves out, to keep it short: shown first in its Nerdy stuff.
    public var facts: [String] = []
    /// Which kind of card this is, for a card about one busy process (`Card.make`): the card that won for it, as the
    /// golden ranking records it (see Ranking.swift). Nil for cards about the Mac as a whole.
    public var cardID: String? = nil
    /// For a card about one busy process: every card that matched it, and why this one was chosen (see Ranker).
    public var choice: Ranker.Choice? = nil
    /// What the card saw and what it thinks it means, and facts about its options in its own words, for the decision
    /// record (see Decision.swift).
    public var diagnosis: Diagnosis? = nil
    public var optionFacts: [String: OptionFacts] = [:]
    /// The slots the card was written from, for a card made from the template (see CardTemplate); the selftest checks
    /// its headline against them.
    public var template: CardTemplate? = nil

    public init(state: JobState, headline: String, explanation: String, fixes: [Fix]) {
        self.state = state; self.headline = headline; self.explanation = explanation
        // Waiting isn't an option in the list: each card has a clock in its corner for that (10 minutes, 30 minutes or
        // an hour, never "until it's done"). The rest in one fixed order.
        var seen = false
        var kept = fixes.filter { if case .wait = $0.kind { return false }; return true }.map { f -> Fix in
            var f = f
            if f.recommended { if seen { f.recommended = false }; seen = true }    // one recommendation at most
            return f
        }
        // Quit beside a restart of the same app: both close it, so the quit says when it's the one to use ("Use this
        // only if you are no longer using it. This closes all its tabs."), or the two read as the same choice.
        kept = Card.marked(kept)
        // One click first, since it's the least effort: where a card recommends something, and that is a task for you
        // or only tells you more, an option Cool Head does in one click that helps is recommended instead, if there is
        // one that isn't Caution: one that closes nothing first, then the one that does most about the problem. A task
        // that does more says so ("Fixes the cause"). A one-click recommendation stays, Caution or not (stopping a
        // stuck job was chosen for its card's reason). A card that recommends nothing (a job working normally) gets no
        // recommendation from this rule. Where the card can't tell what it's doing (`unknown`), an option that closes it
        // isn't put forward: quitting may end work Cool Head can't see (a render, say), so what it costs isn't known.
        if let rec = kept.first(where: \.recommended), rec.doer == .you || rec.result < .eases,
           let i = kept.indices.filter({ kept[$0].doer == .coolHead && !kept[$0].caution && !kept[$0].holdBack && kept[$0].result >= .eases
                                        && !(state == .unknown && kept[$0].interrupts) })
                .max(by: { (kept[$0].interrupts ? 0 : 1, kept[$0].result, -Card.rank(kept[$0]), -$0) < (kept[$1].interrupts ? 0 : 1, kept[$1].result, -Card.rank(kept[$1]), -$1) }) {
            displaced = rec.id
            for k in kept.indices { kept[k].recommended = k == i }
        }
        self.fixes = Card.ordered(kept)
    }

    /// What a quit says beside a restart of the same app, before its own consequence, in the cards' fixed "Use this
    /// only if" form (as JobCard.onlyIfKnown).
    public static let whenDoneWords = "Use this only if you are no longer using it."
    /// The options with each quit marked while a restart of the same app is among them, and unmarked otherwise.
    static func marked(_ fs: [Fix]) -> [Fix] {
        let restarted = Set(fs.compactMap(\.restarts))
        return fs.map { f in
            var f = f
            if case .quitApp(let b) = f.kind { f.whenDone = restarted.contains(b) } else { f.whenDone = false }
            return f
        }
    }

    /// The recommendation first; then what does most about the problem; then, at the same, what interrupts nothing;
    /// then the fixed order of kinds (see `rank`); the order given last.
    static func ordered(_ fs: [Fix]) -> [Fix] {
        func key(_ f: Fix, _ at: Int) -> (Int, Int, Int, Int, Int) { (f.recommended ? 0 : 1, -f.result.rawValue, f.caution ? 1 : 0, Card.rank(f), at) }
        return fs.enumerated().sorted { key($0.element, $0.offset) < key($1.element, $1.offset) }.map(\.element)
    }

    /// The card once the options in `done` (their `doneKey`s) are done (pressed, and it worked): those go, since they can't be done
    /// again. While the recommended option is left, it stays the recommendation (another option done doesn't move
    /// it); once it is done, the next option is recommended. That is the card's own pick where the one-click rule put an option in
    /// one click in its place (`displaced`), one click or a task, since the easy way has been tried; otherwise the first
    /// option left, in the card's order, that acts, isn't Caution, isn't held back, and, where the card can't tell what
    /// it's doing, doesn't close it (as in `init`; a risky option is never put forward by this, only offered). Nothing is recommended where none is left, nor on a card that recommended nothing (a job working
    /// normally), since nothing there needs doing. The card unchanged when nothing is done.
    public func after(_ done: Set<String>) -> Card {
        guard !done.isEmpty else { return self }
        let left = fixes.filter { !done.contains($0.doneKey) }
        let own = displaced.flatMap { d in left.first { $0.id == d && !$0.caution } }
        let still = recommended.flatMap { r in left.first { $0.id == r.id } }
        let next = recommended == nil ? nil : still ?? own ?? left.first { $0.kind.isAction && !$0.caution && !$0.holdBack && !(state == .unknown && $0.interrupts) }
        var c = self
        c.fixes = Card.ordered(Card.marked(left).map { var f = $0; f.recommended = f.id == next?.id; return f })
        return c
    }

    /// Tasks for you that do more about the problem than the recommended option: shown with "Fixes the cause", so a
    /// better result is clear even below the one-click options. (An option Cool Head does that fixes the cause by
    /// quitting or stopping something is labelled Caution instead.)
    public var betterThanRecommended: [Fix] {
        guard let rec = recommended, rec.result < .fixesCause else { return [] }
        return fixes.filter { !$0.recommended && $0.doer == .you && $0.result == .fixesCause }
    }

    /// Why the recommended option is the recommendation, in one sentence under it: what sets it apart from the other
    /// options that act, from the facts the choice is made on (see `init`). Where no other does as much about the
    /// problem, it's the only one that does; otherwise it's what it does, and each way it's easier than every option
    /// that does as much or more: in one click where all of those are tasks for you (and it isn't Caution, which asks
    /// twice), and, for what Cool Head does, closing nothing where all of those close something. Its risk is the Caution tag's, and what you lose its consequence's, so neither is said again. Every
    /// recommended option has the line, since it is what marks the recommendation in words (the tile's blue marks it
    /// by sight): where it's the only option that acts, where it only tells you more, or where the facts don't say why
    /// it won (a reason of its card's own, such as slowing a tab you're using), the line is "Cool Head recommends
    /// this." with no reason, since a reason that isn't the real one would mislead. Nil only when nothing is recommended.
    public var why: String? {
        guard let r = recommended else { return nil }
        let bare = "Cool Head recommends this."
        let others = fixes.filter { $0.kind.isAction && $0.id != r.id }
        // an option that only tells you more is recommended for its card's own reason (it may be rendering, say)
        guard !others.isEmpty, r.result > .informs else { return bare }
        let rivals = others.filter { $0.result >= r.result }
        let does = r.result == .fixesCause ? "fixes the cause" : "helps"
        if rivals.isEmpty { return "Cool Head recommends this because it is the only option that \(does)." }
        // each reason holds against every rival; a Caution option asks for a second click, so it's never "in one click";
        // and only what Cool Head does is known to close nothing (a task may well be closing tabs, done your way)
        var easier: [String] = []
        if r.doer == .coolHead, !r.caution, rivals.allSatisfy({ $0.doer == .you }) { easier.append("in one click") }
        if r.doer == .coolHead, !r.closesSomething, rivals.allSatisfy(\.closesSomething) { easier.append("without closing anything") }
        guard !easier.isEmpty else { return bare }
        return "Cool Head recommends this because it \(does) " + easier.joined(separator: ", ") + "."
    }

    /// The order every card's options are shown in, so they read the same way everywhere: the recommended option;
    /// then options you can undo, most helpful first; then options that close or lose something, least loss first;
    /// then sharing; then notes with nothing to press.
    public static func rank(_ f: Fix) -> Int {
        if f.recommended { return 0 }
        // one kind per line, so pull requests adding different kinds edit different lines
        switch f.kind {
        case .cooler, .cpuCap: return 1
        case .pauseJob: return 1
        case .resume: return 1
        case .keepOutOfBackup: return 1
        case .pauseSync: return 2
        case .openPage: return 2
        case .openApp: return 2
        case .reveal: return 2
        case .guide: return 2
        case .lookUp: return 3
        case .restartBrowser: return 3     // closes the browser, but its tabs come back: less loss than quitting
        case .quitApp: return 4
        case .forceQuit: return 4
        case .stopAgent: return 4
        case .stopAndTrash: return 4
        case .restartApp: return 3     // closes the app, but it opens again: less loss than quitting
        case .unloadModels: return 1
        case .chromeCompanion: return 1
        case .deleteBuildData: return 1
        case .stop: return f.id == "stop" ? 5 : 4      // closing one tab or extension loses less than quitting its browser
        case .share: return 6
        case .wait: return 8
        }
    }

    public var recommended: Fix? { fixes.first { $0.recommended } }
    /// Has something to press that acts on the cause (not only advice or sharing).
    public var hasAction: Bool {
        fixes.contains { f in
            // every kind listed, one per line: a new kind must say whether it acts on the cause, and pull requests
            // adding different kinds edit different lines
            switch f.kind {
            case .cooler, .cpuCap: return true
            case .stop: return true
            case .quitApp: return true
            case .lookUp: return true
            case .openPage: return true
            case .pauseJob: return true
            case .pauseSync: return true
            case .resume: return true
            case .forceQuit: return true
            case .restartBrowser: return true
            case .stopAgent: return true
            case .keepOutOfBackup: return true
            case .stopAndTrash: return true
            case .restartApp: return true
            case .unloadModels: return true
            case .chromeCompanion: return true
            case .deleteBuildData: return true
            // opening an app, showing a folder or showing how help, but don't act on the cause
            case .openApp: return false
            case .reveal: return false
            case .guide: return false
            case .share: return false
            case .wait: return false
            }
        }
    }

    /// Who the card is about, in a word or two: the project ("Photo Export"), the script, or the app.
    public static func subject(_ e: Evidence) -> String {
        // a script names the job better than its runtime (Homebrew's Python is itself an app bundle)
        if e.script != nil { return e.project ?? e.task }
        if let part = e.browserPart, let app = e.app {
            return part == .tab ? "\(app) tab" : part == .extensionPart ? "\(app) extension" : app
        }
        if let app = e.app { return app }
        return e.name
    }

    static func wait(until: Date?, now: Date, recommended: Bool) -> Fix {
        if let u = until, u > now.addingTimeInterval(120) {
            return Fix(id: "wait", title: "Wait until \(Fmt.time(u))", consequence: "This hides the card until then.",
                       kind: .wait(u), recommended: recommended)
        }
        return Fix(id: "wait", title: "Wait 30 minutes", consequence: "This hides the card until then.",
                   kind: .wait(now.addingTimeInterval(1800)), recommended: recommended)
    }

    // sent to Cool Head's makers only after you see it and choose to (see CaseReport)
    static let share = Fix(id: "share", title: "Send this case", consequence: "This shows you what Cool Head saw. You choose whether to send it to Cool Head's makers.", kind: .share)

    static func lookUp(_ name: String, recommended: Bool) -> Fix {
        Fix(id: "lookup", title: "Search the web", consequence: "This searches for \u{201C}\(name)\u{201D} in your browser.", kind: .lookUp(name), recommended: recommended)
    }

    /// The card for one busy process: every card in Sources/CoolHeadCore/Cards that matches is made, and the ranker
    /// chooses one (see ProcessCard.swift).
    public static func make(_ e: Evidence, now: Date = Date(), busySince: Date? = nil, warm: Bool = false, gameRunning: String? = nil,
                            frontApp: String? = nil, battery: Int? = nil, syncFeed: SyncFeed? = nil,
                            agent: BackgroundAgents.Agent? = nil, backupFeed: BackupFeed? = nil, disguise: Disguise.Finding? = nil,
                            background: BackgroundWork.Reading? = nil, apps: AppBuild.Facts? = nil, busyWith: BusyWith? = nil) -> Card {
        make(Situation(e, now: now, busySince: busySince, warm: warm, gameRunning: gameRunning, frontApp: frontApp, battery: battery,
                       syncFeed: syncFeed, agent: agent, backupFeed: backupFeed, disguise: disguise, background: background, apps: apps,
                       busyWith: busyWith))
    }

    /// Sees every situation `make` is given, for `coolhead cards --why`, which reviews the reasons on every sample and
    /// check varied many ways. Nil in the app.
    nonisolated(unsafe) public static var observer: ((Situation) -> Void)?

    public static func make(_ s: Situation) -> Card {
        observer?(s)
        var (c, choice) = Ranker.choose(s)
        c.choice = choice
        // the processes it names, as shown (see Naming): the process, when the card names it (macOS's own processes and
        // security software are named by what they are instead: "Spotlight", "CrowdStrike Falcon"), and a game it is
        // competing with
        let text = c.headline + " " + c.explanation
        c.names = [subject(s.e)].filter { text.contains($0) }
            + (s.gameRunning.map { g in text.contains("slows \(g)") ? [g] : [] } ?? [])
        return c
    }
}

/// Formats in Cool Head's house style: 4:50pm, 3 hours 20 minutes.
public enum Fmt {
    /// A list in a sentence, in US style with the Oxford comma from three items, as in all of Cool Head's copy:
    /// "A", "A and B", "A, B, and C". Not ListFormatter, which follows the Mac's region and drops the comma in British
    /// English.
    public static func list(_ items: [String], or: Bool = false) -> String {
        let word = or ? "or" : "and"
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(word) \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", \(word) " + items.last!
        }
    }

    /// A temperature, given in °C, in the unit this Mac is set to, taken from its region settings: System Settings ▸
    /// General ▸ Language & Region ▸ Temperature where it's been chosen, otherwise the region's usual unit. Cool Head's
    /// own limits stay in °C.
    public static func temperature(_ celsius: Double, fahrenheit: Bool = Fmt.fahrenheit) -> String {
        fahrenheit ? "\(Int((celsius * 9 / 5 + 32).rounded()))°F" : "\(Int(celsius.rounded()))°C"
    }
    public static var fahrenheit: Bool {
        if let unit = UserDefaults.standard.string(forKey: "AppleTemperatureUnit") { return unit == "Fahrenheit" }
        if #available(macOS 13, *) { return Locale.current.measurementSystem == .us }
        return !Locale.current.usesMetricSystem
    }
    public static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        let s = f.string(from: d).lowercased()
        let cal = Calendar.current
        if cal.isDateInToday(d) { return s }
        if cal.isDateInTomorrow(d) { return "\(s) tomorrow" }
        if cal.isDateInYesterday(d) { return "\(s) yesterday" }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "d MMMM"
        return "\(s) on \(day.string(from: d))"
    }

    public static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        let h = m / 60, r = m % 60
        let hs = h == 1 ? "1 hour" : "\(h) hours"
        return r == 0 ? hs : "\(hs) \(r) minute\(r == 1 ? "" : "s")"
    }

    /// A clock time alone, for chart labels: 11:59pm.
    public static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.component(.minute, from: d) == 0 ? "ha" : "h:mma"
        return f.string(from: d).lowercased()
    }

    /// What else a busy process is doing, as one sentence: " It's adding to the heat, competing with Hades, and draining
    /// your battery." Empty when there's nothing to say. Hand-written wording joins its facts into one sentence rather
    /// than a string of short "It's" sentences.
    public static func its(_ clauses: [String?]) -> String {
        let c = clauses.compactMap { $0 }
        guard !c.isEmpty else { return "" }
        return " It's \(Fmt.list(c))."
    }

    /// A name at the start of a sentence: a leading "the", "a", "an" or "another" gets its capital ("the claude
    /// command-line program" → "The claude …"); a name itself keeps its own spelling ("macOS", "claude", "train.py").
    public static func sentenceStart(_ s: String) -> String {
        for article in ["the ", "a ", "an ", "another "] where s.hasPrefix(article) { return article.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    public static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded(.down)))%" }

    /// A rough share, to the nearest 5%: "about 70%", or "under 5%".
    public static func share(_ f: Double) -> String {
        let p = Int((f * 20).rounded()) * 5
        return p < 5 ? "under 5%" : "about \(min(100, p))%"
    }

    public static func cores(_ c: Double) -> String {
        if c < 0.95 { return "\(Int((c * 100).rounded()))% of one core" }
        let r = (c * 2).rounded() / 2
        let s = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        return r == 1 ? "1 core" : "\(s) cores"
    }

    public static func bytes(_ b: UInt64) -> String {
        let g = Double(b) / 1_073_741_824
        return g >= 1 ? String(format: "%.1f GB", g) : "\(Int(Double(b) / 1_048_576)) MB"
    }

    /// A file's size the way Finder shows it, in thousands: "512 B", "48 KB", "3.2 MB", "14 GB". Shown beside a count
    /// of files moved, so the count comes with how much space they take.
    public static func fileSize(_ b: UInt64) -> String {
        var v = Double(b), unit = 0
        while v >= 999.5 && unit < 3 { v /= 1000; unit += 1 }
        if unit == 0 { return "\(b) B" }
        return String(format: v < 9.95 ? "%.1f" : "%.0f", v) + " " + ["B", "KB", "MB", "GB"][unit]
    }
}

import Foundation

// Cards about one busy process: each kind of card is its own file in Sources/CoolHeadCore/Cards (<Name>Card.swift,
// declaring `<Name>Card`), and the build lists them (Plugins/Lists), so a new card is one new file. Every card that
// matches a process is made, and the ranker below chooses one: rules first, then weights (Phil, 17 November 2026:
// "Rules, then weights"; notes/card-architecture-design.md). Extras (<Name>Extra.swift) add a sentence or an option
// to whichever card wins. Nothing is loaded or chosen from outside while the app runs: the lists are fixed when it's
// built.

/// What a card about one busy process is given: the process, what's around it, and what every card works out from
/// them, worked out once.
public struct Situation {
    public let e: Evidence
    public let now: Date
    public let busySince: Date?
    public let warm: Bool
    public let gameRunning: String?
    public let frontApp: String?
    public let battery: Int?
    public let syncFeed: SyncFeed?
    public let agent: BackgroundAgents.Agent?
    public let backupFeed: BackupFeed?
    public let disguise: Disguise.Finding?
    public let background: BackgroundWork.Reading?
    public let apps: AppBuild.Facts?

    public let onBattery: Bool
    /// Who the card is about, in a word or two (see `Card.subject`).
    public let who: String
    public let busyFor: TimeInterval
    public let state: JobState
    /// The share of the graphics chip it keeps busy (see GPU).
    public let gpu: Double
    /// Busy on the CPU or the graphics chip.
    public let active: Bool
    public let gpuClause: String?
    /// Here for the graphics chip, not the CPU.
    public let gpuLed: Bool
    public let heating: Bool
    /// Stopping it, where that's offered: never macOS's own programs (stopping loginwindow logs you out), and never an
    /// app's main program, which should be quit so it can ask to save.
    public let stop: Fix?
    /// Running it cooler, where that helps (see RunCooler): your own work above background priority, never macOS's.
    public let cooler: Fix?
    /// "has used about 1.2 cores for 2 hours." or the graphics chip's share.
    public let used: String
    /// WebKit's graphics process, which draws web pages.
    public let webkitGPU: Bool
    /// One of WebKit's processes, which run or draw web pages.
    public let webkit: Bool

    public init(_ e: Evidence, now: Date = Date(), busySince: Date? = nil, warm: Bool = false, gameRunning: String? = nil,
                frontApp: String? = nil, battery: Int? = nil, syncFeed: SyncFeed? = nil, agent: BackgroundAgents.Agent? = nil,
                backupFeed: BackupFeed? = nil, disguise: Disguise.Finding? = nil, background: BackgroundWork.Reading? = nil,
                apps: AppBuild.Facts? = nil) {
        self.e = e; self.now = now; self.busySince = busySince; self.warm = warm; self.gameRunning = gameRunning
        self.frontApp = frontApp; self.battery = battery; self.syncFeed = syncFeed; self.agent = agent
        self.backupFeed = backupFeed; self.disguise = disguise; self.background = background; self.apps = apps

        onBattery = battery != nil
        who = Card.subject(e)
        let busyFor = now.timeIntervalSince(busySince ?? e.start ?? now)
        self.busyFor = busyFor
        let state = Health.assess(e, now: now, busySince: busySince)
        self.state = state
        let gpu = e.gpuShare ?? 0
        self.gpu = gpu
        active = e.coresNow >= 0.25 || e.gpuBusy
        gpuClause = e.gpuBusy ? "keeping \(Fmt.share(gpu)) of the graphics chip busy" : nil
        let gpuLed = e.gpuBusy && e.coresNow < 0.5
        self.gpuLed = gpuLed
        heating = e.coresNow >= 0.5 || gpu >= GPU.busyShare

        // what stopping would cost, in a few words
        let atStake = now.timeIntervalSince(e.workStart ?? e.start ?? now)
        let output = e.writing.first { !Evidence.isLog($0) }.map { ($0 as NSString).lastPathComponent }
        func stopConsequence() -> String {
            if state == .stalled, let p = e.progress { return "Nothing since \(Fmt.time(p.lineTime)) is lost." }
            let lose = atStake >= 10 * 60 ? "You may lose up to \(Fmt.duration(atStake)) of work." : "Little work is lost."
            return lose + (output.map { " \($0) may be left unfinished." } ?? "")
        }
        let appMain = e.script == nil && (e.path.map { $0.components(separatedBy: ".app/").count == 2 && $0.contains(".app/Contents/MacOS/") } ?? false)
        // a script run by macOS's own interpreter (/usr/bin/python3) is still the person's job
        let macOSProgram = e.script == nil && (e.path.map(CaseReport.isMacOS) ?? true)
        let stoppable = e.mine && !macOSProgram && !appMain
        stop = stoppable ? Fix(id: "stop", title: "Stop it", consequence: stopConsequence(), kind: .stop, recommended: state == .stalled) : nil
        cooler = RunCooler.offered(e)
            ? Fix(id: "cooler", title: "Run it cooler", consequence: RunCooler.consequence(e), kind: .cooler, recommended: false,
                  holdBack: RunCooler.isVirtualMachine(e))     // never put in place of a task's recommendation for a VM
            : nil

        used = gpuLed ? "has kept \(Fmt.share(gpu)) of the graphics chip busy for \(Fmt.duration(busyFor))."
            : "has used about \(Fmt.cores(e.coresNow)) for \(Fmt.duration(busyFor))."
        let webkitGPU = e.name == "com.apple.WebKit.GPU" || (e.path?.contains("com.apple.WebKit.GPU") ?? false)
        self.webkitGPU = webkitGPU
        webkit = webkitGPU || e.name == "com.apple.WebKit.WebContent" || (e.path?.contains("com.apple.WebKit.WebContent") ?? false)
    }
}

/// The kinds of card, in the one fixed order the ranker uses first. A new kind changes this list; a new card never does.
public enum CardKind: Int, Comparable, CaseIterable {
    /// Who a program really is (the disguise check): whatever it's doing, this comes first.
    case identity = 0
    /// macOS's own work that is stuck.
    case stalled = 1
    /// What a process is doing: Spotlight indexing, a sync app catching up, a Chrome tab.
    case explanation = 2
    /// What's said when nothing more specific explains it: a busy job, a macOS service nobody catalogued.
    case catchAll = 3

    public static func < (a: CardKind, b: CardKind) -> Bool { a.rawValue < b.rawValue }
}

/// How specifically a card matches a process: the ranker's first weight, worked out from how the card matches.
public enum Match: Int, Comparable {
    /// Any busy process.
    case any = 0
    /// A category: any Chromium-style app's helper, any game, any of macOS's services.
    case category = 1
    /// A process name, or a family of them.
    case name = 2
    /// A list of exact bundle IDs or products.
    case bundle = 3
    /// A program's signature.
    case signed = 4

    public static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
}

/// One kind of card about a busy process, in its own file.
public protocol ProcessCard {
    /// Stable, never reused: what the golden ranking records.
    static var id: String { get }
    static var kind: CardKind { get }
    /// Where the card comes from: a research rule, or Phil's decision and its date.
    static var rule: String { get }
    static var match: Match { get }
    /// Cards this one says more about, where both match, and why: it wins over them before any other rule.
    static var refines: [String: String] { get }
    /// Samples (`Wording.samples`) this card must win: the selftest checks each, and that every card has one.
    static var samples: [String] { get }
    /// The card, or nil when it doesn't apply to this process.
    static func card(_ s: Situation) -> Card?
    /// How strongly the evidence points to it, from 0: the ranker's second weight.
    static func strength(_ s: Situation) -> Double
}

extension ProcessCard {
    public static var refines: [String: String] { [:] }
    public static func strength(_ s: Situation) -> Double { 0 }
}

/// A sentence or an option added to whichever card wins (a background helper's "turn off", an Intel app's note).
/// Extras never compete: every one that applies is added.
public protocol CardExtra {
    static var id: String { get }
    static var rule: String { get }
    /// The card with this added, or nil when it doesn't apply.
    static func add(to c: Card, _ s: Situation) -> Card?
}

/// Chooses one card for a busy process.
public enum Ranker {
    /// What was chosen and why: every card that matched, and, for each one that lost, the rule or weight that decided.
    public struct Choice {
        public var winner: String
        public var matched: [String]
        /// "Chosen over job: its kind comes first".
        public var reasons: [String]
        /// Cards no rule or weight told apart from the winner: the selftest fails on any.
        public var ties: [String]
    }

    struct Candidate {
        let type: any ProcessCard.Type
        let card: Card
        var risk: Int { card.fixes.map(Ranker.risk).max() ?? 0 }
    }

    /// How risky an option is: Caution, then anything that interrupts, then the rest.
    static func risk(_ f: Fix) -> Int { f.caution ? 2 : f.interrupts ? 1 : 0 }

    /// Whether `a` wins over `b`, and why; nil when nothing tells them apart.
    static func decide(_ a: Candidate, _ b: Candidate, _ s: Situation) -> (aWins: Bool, why: String)? {
        // rules, never traded against anything
        if a.type.kind != b.type.kind { return (a.type.kind < b.type.kind, "its kind comes first") }
        if let why = a.type.refines[b.type.id] { return (true, why) }
        if let why = b.type.refines[a.type.id] { return (false, why) }
        if a.risk != b.risk { return (a.risk < b.risk, "it's more cautious: its riskiest option is less risky") }
        // then weights
        if a.type.match != b.type.match { return (a.type.match > b.type.match, "it matches more specifically") }
        let sa = a.type.strength(s), sb = b.type.strength(s)
        if sa != sb { return (sa > sb, "the evidence for it is stronger") }
        return nil
    }

    /// The winning card, with the extras that apply, and why it won.
    public static func choose(_ s: Situation, cards: [any ProcessCard.Type] = ProcessCards.all,
                              extras: [any CardExtra.Type] = ProcessCards.extras) -> (Card, Choice) {
        let candidates = cards.compactMap { t in t.card(s).map { Candidate(type: t, card: $0) } }
        // the job card matches any process, so there is always one
        var best = candidates[0]
        for c in candidates.dropFirst() where decide(c, best, s)?.aWins == true { best = c }
        var reasons: [String] = [], ties: [String] = []
        for c in candidates where c.type.id != best.type.id {
            if let d = decide(best, c, s) { reasons.append("Chosen over \(c.type.id): \(d.why)") } else { ties.append(c.type.id) }
        }
        var card = best.card
        for x in extras { if let added = x.add(to: card, s) { card = added } }
        card.cardID = best.type.id
        return (card, Choice(winner: best.type.id, matched: candidates.map { $0.type.id }, reasons: reasons, ties: ties))
    }
}

import Foundation

// Cards about one busy process: each kind of card is its own file in Sources/CoolHeadCore/Cards (<Name>Card.swift,
// declaring `<Name>Card`), and the build lists them (Plugins/Lists), so a new card is one new file. Every card that
// matches a process is made, and the ranker below chooses one: rules first, then weights, not positions set by hand, so
// cards order themselves and a new one can't conflict with the rest. Extras (<Name>Extra.swift) add a sentence or an
// option to whichever card wins. Nothing is loaded or chosen from outside while the app runs: the lists are fixed when
// it's built.

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
    /// Playing sound or downloading now (see BusyWith): Pause until you plug in isn't offered then, and the card says why.
    public let busyWith: BusyWith?

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
    /// How much work stopping it could lose, from when its work began.
    public let atStake: TimeInterval
    /// "has used about 1.2 cores for 2 hours." or the graphics chip's share.
    public let used: String
    /// WebKit's graphics process, which draws web pages.
    public let webkitGPU: Bool
    /// One of WebKit's processes, which run or draw web pages.
    public let webkit: Bool

    public init(_ e: Evidence, now: Date = Date(), busySince: Date? = nil, warm: Bool = false, gameRunning: String? = nil,
                frontApp: String? = nil, battery: Int? = nil, syncFeed: SyncFeed? = nil, agent: BackgroundAgents.Agent? = nil,
                backupFeed: BackupFeed? = nil, disguise: Disguise.Finding? = nil, background: BackgroundWork.Reading? = nil,
                apps: AppBuild.Facts? = nil, busyWith: BusyWith? = nil) {
        self.busyWith = busyWith
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
        self.atStake = atStake
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

/// What a card is about. Only one kind is a rule outside the score (see Ranker): a card about who a program really is.
public enum CardKind: Int, Comparable, CaseIterable {
    /// Who a program really is (the disguise check).
    case identity = 0
    /// macOS's own work that is stuck.
    case stalled = 1
    /// What a process is doing: Spotlight indexing, a sync app catching up, a Chrome tab.
    case explanation = 2
    /// What's said when nothing more specific explains it: a busy job, a macOS service nobody catalogued.
    case catchAll = 3

    public static func < (a: CardKind, b: CardKind) -> Bool { a.rawValue < b.rawValue }
}

/// How surely a card fits a process, with the reason in plain words: the factor that counts most in its score.
public enum Confidence {
    /// It fits any busy program.
    case any(String)
    /// It goes only by something other programs can share, such as a process's name.
    case guess(String)
    /// It recognizes what kind of program this is.
    case type(String)
    /// It recognizes this exact app, product or part of macOS.
    case named(String)

    public var level: Int {
        switch self { case .any: return 0; case .guess: return 1; case .type: return 2; case .named: return 3 }
    }
    public var reason: String {
        switch self { case .any(let r), .guess(let r), .type(let r), .named(let r): return r }
    }
}

/// One kind of card about a busy process, in its own file.
public protocol ProcessCard {
    /// Stable, never reused: what the golden ranking records.
    static var id: String { get }
    /// What it's about, in a few plain words, for the reason a card was chosen: "a web page in an app".
    static var name: String { get }
    static var kind: CardKind { get }
    /// Where the card comes from: a research rule or a design decision.
    static var rule: String { get }
    /// Samples (`Wording.samples`) this card must win: the selftest checks each, and that every card has one.
    static var samples: [String] { get }
    /// The card, or nil when it doesn't apply to this process.
    static func card(_ s: Situation) -> Card?
    /// How surely it fits this process, and why.
    static func confidence(_ s: Situation) -> Confidence
}

/// A sentence or an option added to whichever card wins (a background helper's "turn off", an Intel app's note).
/// Extras never compete: every one that applies is added.
public protocol CardExtra {
    static var id: String { get }
    static var rule: String { get }
    /// The card with this added, or nil when it doesn't apply.
    static func add(to c: Card, _ s: Situation) -> Card?
}

/// Chooses one card for a busy process: the one with the most impact, the least risk, the most confidence, and the least
/// effort, taken together. Every card that fits is scored on those four factors, from its own data, and the highest
/// total wins:
///
/// - Confidence (0 to 3), how surely it fits, counted twice: a choice made against the samples, not a measured truth.
///   Counted once, a Chromium-style helper inside security software, a sync app or a game gets the browser-tab card,
///   and six cases tie.
/// - Impact (1 to 3) of its advice, the recommended option: fixes the cause 3, eases it 2, only informs 1. A card that
///   recommends nothing tells you what's happening, which informs.
/// - Risk (0 to 3) of its advice: Caution 3, interrupts something 1, neither 0.
/// - Effort (0 or 1) of its advice: a task for you 1, one click or nothing to do 0.
///
/// One rule is outside the score: a card about who a program really is (the disguise card) always wins, because a
/// score could let a busy-looking explanation outweigh a warning that a program isn't what it claims to be.
public enum Ranker {
    /// A card's score, factor by factor.
    public struct Score: Equatable {
        public var confidence: Int
        public var impact: Int
        public var risk: Int
        public var effort: Int
        public var total: Int { 2 * confidence + impact - risk - effort }
        /// "confidence 3, impact 1, risk 0, effort 1: 6".
        public var text: String { "confidence \(confidence), impact \(impact), risk \(risk), effort \(effort): \(total)" }
    }

    /// What was chosen and why: every card that fitted, with its score, and why this one won over each.
    public struct Choice {
        public var winner: String
        public var matched: [String]
        /// Each card's score, by ID.
        public var scores: [String: Score]
        /// "Chosen over job: …", for `coolhead cards`.
        public var reasons: [String]
        /// Cards with the winner's score, that nothing told apart: the selftest fails on any. A tie is settled by merging
        /// the two cards where they share the fix, as tied cards should be, otherwise by changing a card's confidence or
        /// options, with the reason.
        public var ties: [String]
        /// The other cards that fitted, by name ("a busy program"), the closest first.
        public var others: [String] = []
        /// Why this card won over the closest one, in plain words, and that reason's name ("confidence").
        public var because: (text: String, kind: String)?
        /// What we recommend and why, from the decision record (see Decision.swift), and its pattern's name.
        public var explanation: (text: String, pattern: String)?
        /// For reviewing every pattern of explanation.
        public var pattern: String { explanation?.pattern ?? "no explanation" }

        /// For the card's Nerdy stuff: what we recommend and why, in plain words. Nil when there's nothing to say.
        public var line: String? { explanation?.text }
    }

    struct Candidate {
        let type: any ProcessCard.Type
        let card: Card
        let confidence: Confidence
        var score: Score {
            guard let r = card.recommended else { return Score(confidence: confidence.level, impact: 1, risk: 0, effort: 0) }
            return Score(confidence: confidence.level, impact: r.result.rawValue + 1,
                         risk: r.caution ? 3 : r.interrupts ? 1 : 0, effort: r.doer == .you ? 1 : 0)
        }
    }

    /// Why `a` beats `b`: the main thing in its favour, as "because …" with its reason, and the name of that reason
    /// for review; nil when it doesn't win. It never says which factor matters more (that's in DIAGNOSIS.md).
    static func why(_ a: Candidate, over b: Candidate) -> (text: String, kind: String)? {
        if a.type.kind == .identity, b.type.kind != .identity {
            return ("because whether a program is what it claims to be matters before anything else.", "identity")
        }
        if b.type.kind == .identity, a.type.kind != .identity { return nil }
        let x = a.score, y = b.score
        guard x.total > y.total else { return nil }
        if x.confidence > y.confidence {
            let result = a.card.recommended?.result ?? .informs
            let what = result == .fixesCause ? " will fix the problem" : result == .eases ? " will help" : "'s right"
            return ("because we're more confident it\(what): \(a.confidence.reason).", "confidence")
        }
        if x.impact > y.impact {
            return ("because its advice does more: it \(x.impact == 3 ? "fixes the cause" : "eases the problem"), where the other card's \(y.impact == 2 ? "only eases it" : "only explains it").", "impact")
        }
        if x.risk < y.risk { return ("because its advice is safer.", "risk") }
        return ("because its advice is less work for you: it's one click.", "effort")
    }

    /// The winning card, with the extras that apply, and why it won.
    public static func choose(_ s: Situation, cards: [any ProcessCard.Type] = ProcessCards.all,
                              extras: [any CardExtra.Type] = ProcessCards.extras) -> (Card, Choice) {
        let candidates = cards.compactMap { t in t.card(s).map { Candidate(type: t, card: $0, confidence: t.confidence(s)) } }
        // the job card fits any process, so there is always one
        var best = candidates[0]
        for c in candidates.dropFirst() where why(c, over: best) != nil { best = c }
        var reasons: [String] = [], ties: [String] = []
        let rest = candidates.filter { $0.type.id != best.type.id }.sorted { ($0.score.total, $1.type.id) > ($1.score.total, $0.type.id) }
        for c in rest {
            if let w = why(best, over: c) { reasons.append("Chosen over \(c.type.id) (\(c.score.text)): \(w.text)") } else { ties.append(c.type.id) }
        }
        var card = best.card
        for x in extras { if let added = x.add(to: card, s) { card = added } }
        // an extra makes a new card: keep the winner's decision record, and add the extra's
        // an extra may say what it saw (the Electron apps): its diagnosis wins; its option facts join the winner's
        card.diagnosis = card.diagnosis ?? best.card.diagnosis
        card.optionFacts = best.card.optionFacts.merging(card.optionFacts) { _, b in b }
        card.cardID = best.type.id
        let scores = Dictionary(candidates.map { ($0.type.id, $0.score) }, uniquingKeysWith: { a, _ in a })
        return (card, Choice(winner: best.type.id, matched: candidates.map { $0.type.id }, scores: scores, reasons: reasons,
                             ties: ties, others: rest.map { $0.type.name }, because: rest.first.flatMap { why(best, over: $0) },
                             explanation: Decision.explain(card, subject: s.who)))
    }
}

extension Ranker {
    /// Every card and extra, as `coolhead cards` lists them: ID, kind, rule, and each of its samples with the card it
    /// gets, every fitting card's score and why this one won (wording as `coolhead wording` prints it).
    public static func list(now: Date = Date()) -> [[String: Any]] {
        let samples = Dictionary(Wording.samples(now: now).map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        let cards: [[String: Any]] = ProcessCards.all.map { t in
            ["id": t.id, "type": "card", "kind": "\(t.kind)", "rule": t.rule,
             "samples": t.samples.map { id -> [String: Any] in
                 guard let c = samples[id] else { return ["id": id] }
                 return ["id": id, "headline": c.headline, "options": c.fixes.map(\.id), "recommended": c.recommended?.id ?? NSNull(),
                         "why": c.choice?.line ?? NSNull(), "chosenOver": c.choice?.reasons ?? [],
                         "scores": (c.choice?.scores ?? [:]).mapValues { $0.text }]
             }]
        }
        let extras: [[String: Any]] = ProcessCards.extras.map { ["id": $0.id, "type": "extra", "rule": $0.rule] }
        return cards + extras
    }

    /// The same, to read.
    public static func listText(now: Date = Date()) -> [String] {
        list(now: now).flatMap { d -> [String] in
            var out = ["[\(d["id"]!)] \(d["type"]!)" + (d["kind"].map { ", \($0)" } ?? ""), "  Rule: \(d["rule"]!)"]
            for s in (d["samples"] as? [[String: Any]]) ?? [] { out.append("  Sample \(s["id"]!): \(s["headline"] ?? "missing")") }
            return out + [""]
        }
    }
}

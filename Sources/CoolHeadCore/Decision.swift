import Foundation

// The decision record (Phil, 17 November 2026: "we're converting data/facts into a fixed structure of human-readable
// text"): facts about the problem, written by each card, and facts about each option, written once per kind of option
// or by a card where its option needs its own words, each a clause written by hand for one role in one fixed template.
// The comparison between the recommended option and the strongest alternative records which factor decided, and the
// text says that factor. Nothing is reworded by a model, and no sentence is joined from words written for somewhere
// else.

/// What a card saw, and what it thinks it means. Each a clause with its own subject, without a full stop: "it hasn't
/// made any progress for 2 hours", "it's stuck, using power without getting anywhere". `subject` names what "it" in an
/// option's title is ("the busy extension"), when that isn't who the card is about.
public struct Diagnosis {
    public var saw: String
    public var means: String?
    public var subject: String?
    public init(saw: String, means: String? = nil, subject: String? = nil) { self.saw = saw; self.means = means; self.subject = subject }
}

/// Facts about one option, each written for its role in the template.
public struct OptionFacts {
    /// What it does about the problem, as a verb phrase after "It": "slows only the busy tab".
    public var helps: String
    /// What it costs, as a clause with its own subject: "it ends at once, without a chance to save". Nil when it costs
    /// nothing worth weighing.
    public var cost: String?
    /// Whether it can be undone.
    public var undo: Undo
    /// When it's the right choice, as a condition: "if you know what it is and don't need it".
    public var when: String?
    /// What Cool Head checked about what's at stake.
    public var stakes: Stakes?
    /// Why it isn't recommended, when that isn't its risk or its effort: a clause, "you may be using that tab".
    public var whyNot: String?

    public init(helps: String, cost: String? = nil, undo: Undo = .no, when: String? = nil, stakes: Stakes? = nil, whyNot: String? = nil) {
        self.helps = helps; self.cost = cost; self.undo = undo; self.when = when; self.stakes = stakes; self.whyNot = whyNot
    }

    public enum Undo { case anyTime, no, other(String) }

    public enum Stakes {
        /// A stuck job's last progress: nothing after it is lost ("3:22pm").
        case nothingLostSince(String)
        /// Work that may be lost ("3 hours").
        case mayLose(String)
        /// What protects you, as a clause: "Mail asks about anything unsaved first".
        case protected(String)
    }
}

public enum Decision {
    /// "Run it cooler" -> "running Site cooler": the verb as "-ing", "it" as who the card is about. Every option's
    /// first word is in `verbs`; the selftest checks that.
    public static func doing(_ title: String, subject: String) -> String {
        if let phrase = phrases[title] { return phrase.replacingOccurrences(of: "{who}", with: subject) }
        var words = title.split(separator: " ").map(String.init)
        for i in words.indices {
            // "it" right after the verb is the program ("Stop it", "Run it cooler"); later it's something else
            // ("Stop the model if you aren't using it")
            if words[i] == "it", i == 1 { words[i] = subject }
            else if let v = verbs[words[i]], i == 0 || words[i - 1] == "and" { words[i] = v }
        }
        return words.joined(separator: " ")
    }

    /// Titles whose "-ing" form isn't the verb swapped.
    static let phrases = ["Look it up": "searching the web for {who}", "Pause until you plug in": "pausing {who} until you plug in",
                          "Disconnect when you don't need it": "disconnecting it", "Stop and delete it": "stopping and deleting {who}",
                          "Turn off and delete it": "turning off and deleting {who}", "Lower its graphics settings": "lowering {who}'s graphics settings"]

    /// Each option title's verb and its "-ing" form.
    static let verbs: [String: String] = [
        "Stop": "stopping", "Run": "running", "Quit": "quitting", "reopen": "reopening", "Turn": "turning", "Find": "finding",
        "Keep": "keeping", "Pause": "pausing", "Lower": "lowering", "Restart": "restarting", "Check": "checking",
        "Update": "updating", "Delete": "deleting", "delete": "deleting", "Open": "opening", "Close": "closing",
        "Disconnect": "disconnecting", "Move": "moving", "Unload": "unloading", "Remove": "removing", "Resume": "resuming",
        "Set": "setting", "Limit": "limiting", "Share": "sharing", "Tell": "telling", "Reinstall": "reinstalling",
        "Free": "freeing", "Bring": "bringing", "Show": "showing", "Use": "using", "See": "seeing", "Clear": "clearing",
        "Wait": "waiting", "Get": "getting", "Make": "making", "Switch": "switching", "Choose": "choosing", "Look": "looking",
    ]

    /// An option's facts: the card's own, else those written for its kind; nil when neither has them.
    public static func facts(_ f: Fix, _ c: Card) -> OptionFacts? { c.optionFacts[f.id] ?? kindFacts(f) }

    /// Facts written once for each kind of option that needs no card's own words.
    static func kindFacts(_ f: Fix) -> OptionFacts? {
        let app = f.title.hasPrefix("Quit ") ? String(f.title.dropFirst(5)) : nil
        switch f.kind {
        case .stop: return OptionFacts(helps: "ends the load completely", cost: "nothing gets a chance to save")
        case .cooler: return OptionFacts(helps: "moves {who} to background priority, so it uses less power and makes less heat", undo: .anyTime)
        case .pauseJob: return OptionFacts(helps: "freezes {who} until you plug in, when it carries on by itself with nothing lost")
        case .quitApp:
            guard let app else { return nil }
            let asks = f.consequence.contains("asks about anything unsaved")
            return OptionFacts(helps: "closes \(app) and ends the work it was doing", cost: !asks && f.caution ? "unsaved work in it may be lost" : nil,
                               stakes: asks ? .protected("\(app) asks about anything unsaved first") : nil)
        case .forceQuit: return OptionFacts(helps: "ends the app at once", cost: "anything unsaved in it is lost")
        case .stopAgent: return OptionFacts(helps: "stops it and keeps it from starting again by itself",
                                            cost: "what it does for its app, such as updates or syncing, stops too", undo: .other("You can turn it back on later."))
        case .stopAndTrash: return OptionFacts(helps: "stops it and moves it to the Trash", cost: "anything that relies on it stops working",
                                               undo: .other("You can put it back from the Trash."))
        case .lookUp: return OptionFacts(helps: "may tell you what it is")
        case .share: return OptionFacts(helps: "sends us the details, so we can work out what it is")
        case .wait: return OptionFacts(helps: "gives it time to finish")
        // the rest need words for what they do in their card
        case .restartBrowser, .keepOutOfBackup, .restartApp, .unloadModels, .deleteBuildData, .chromeLimit, .resume,
             .pauseSync, .openApp, .reveal, .guide, .openPage:
            return nil
        }
    }

    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// A fact with "{who}" in it, filled with who the card is about.
    static func fill(_ s: String, _ subject: String) -> String { s.replacingOccurrences(of: "{who}", with: subject) }

    static func list(_ p: [String]) -> String { p.count < 3 ? p.joined(separator: " and ") : p.dropLast().joined(separator: ", ") + ", and " + p.last! }

    static func stakes(_ s: OptionFacts.Stakes?, after cost: Bool) -> String {
        switch s {
        case .nothingLostSince(let t)?: return ", but its last progress was at \(t), so nothing after that is lost"
        case .mayLose(let d)?: return "\(cost ? "," : "") and you could lose up to \(d) of work"
        case .protected(let p)?: return "; \(p)"
        case nil: return ""
        }
    }

    /// The option on the card that does most, when it does more than the advice and isn't it.
    static func strongest(_ c: Card) -> Fix? {
        let floor = c.recommended?.result ?? .informs
        return c.fixes.filter { !$0.recommended && $0.result > floor && $0.kind.isAction }
            .reduce(nil as Fix?) { best, f in best.map { f.result > $0.result ? f : $0 } ?? f }
    }

    /// Which factor decides between the advice and a stronger option, in words, and its name; nil when the facts don't
    /// say.
    static func decisive(_ b: Fix, _ fb: OptionFacts, over r: Fix?) -> (String, String)? {
        if b.caution, let cost = fb.cost { return (cost + stakes(fb.stakes, after: true), "risk") }
        if let why = fb.whyNot { return (why, "card's reason") }
        if b.interrupts, let cost = fb.cost { return (cost, "ends something") }
        if b.doer == .you, r?.doer != .you { return ("you have to do it yourself", "effort") }
        return nil
    }

    /// The text, and the name of its pattern ("recommend + stronger: effort"), for review. Nil when there's no
    /// diagnosis written, or nothing recommended and nothing held back.
    public static func explain(_ c: Card, subject: String) -> (text: String, pattern: String)? {
        guard let p = c.diagnosis else { return nil }
        let subject = p.subject ?? subject
        var out: [String] = [], pattern: [String] = []
        let because = p.saw + (p.means.map { ", so \($0)" } ?? "")
        let r = c.recommended
        if let r {
            guard let f = facts(r, c) else { return nil }          // its facts are missing: the selftest names it
            out.append("We recommend \(doing(r.title, subject: subject)) because \(because).")
            out.append("That \(fill(f.helps, subject))" + (f.cost == nil ? stakes(f.stakes, after: false) : "") + ".")
            if let cost = f.cost {
                out.append(cap(fill(cost, subject)) + stakes(f.stakes, after: true) + ".")
                pattern.append("recommend + cost")
            } else {
                var easy: [String] = []
                if r.doer == .coolHead && !r.interrupts { easy.append("takes one click") }
                if case .anyTime = f.undo { easy.append("can be undone any time") }
                if !easy.isEmpty { out.append("It " + list(easy) + ".") }
                pattern.append("recommend")
            }
            if case .other(let t) = f.undo { out.append(fill(t, subject)) }
        }
        if let b = strongest(c), let fb = facts(b, c), let (why, factor) = decisive(b, fb, over: r),
           fb.cost == nil || fb.cost != r.flatMap({ facts($0, c) })?.cost {
            let who = doing(b.title, subject: subject)
            // "Stop Site": the option's own words, with who it's about
            var words = b.title.split(separator: " ").map(String.init)
            if words.count > 1, words[1] == "it" { words[1] = subject }
            let act = words.joined(separator: " ")
            if let when = fb.when {
                out.append("\(act) only \(when): it \(fill(fb.helps, subject)), but \(fill(why, subject)).")
            } else if r == nil {
                out.append(factor == "card's reason"
                    ? "We don't recommend \(who) because \(because), and \(fill(why, subject))."
                    : "We don't recommend \(who) because \(because). If you \(act.prefix(1).lowercased() + act.dropFirst()), \(fill(why, subject)).")
            } else {
                out.append("Instead, \(who) \(fill(fb.helps, subject)), but \(fill(why, subject)).")
            }
            pattern.append((r == nil ? "nothing to do + " : "") + "stronger: \(factor)")
        }
        return out.isEmpty ? nil : (out.joined(separator: " "), pattern.joined(separator: " + "))
    }

    /// What's missing, for the selftest: every recommended option, and every option stronger than the advice, needs its
    /// facts, and a card with either needs its diagnosis.
    public static func missing(_ c: Card, id: String) -> [String] {
        var out: [String] = []
        if c.diagnosis == nil, c.recommended != nil || strongest(c) != nil { out.append("\(id): no diagnosis") }
        for f in [c.recommended, strongest(c)].compactMap({ $0 }) {
            if facts(f, c) == nil { out.append("\(id): no facts for \(f.id)") }
            if phrases[f.title] == nil, verbs[String(f.title.split(separator: " ").first ?? "")] == nil { out.append("\(id): no -ing form for \"\(f.title)\"") }
        }
        return out
    }
}

extension Fix.Kind {
    /// An option that acts, rather than one that only shares the case or waits.
    var isAction: Bool {
        if case .share = self { return false }
        if case .wait = self { return false }
        return true
    }
}

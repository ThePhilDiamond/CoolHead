import Foundation

/// The card template (docs/BRAND.md, Card template; the rules and their sources are in docs/CARD-TEMPLATE.md).
/// Every card fills the same slots, and the sentences are written here from them, in simple English that a person who
/// learned English as a second language reads correctly the first time: the simple present for now, the simple past
/// for a measured stretch of time, never the present perfect ("has used"), no contractions, no idioms, and one word
/// for each idea.
///
/// - Headline: subject, reading, verdict. "A Google Chrome tab is still working hard after 1 hour. This is more than usual."
/// - Explanation: how we know (evidence), then what it means for you (effect).
/// - Each option: what it does, what you lose (`Loss`), and "You can undo this." where Cool Head can undo it.
public struct CardTemplate: Equatable {
    /// What the card is about, named the same way on every card: "Photo Export", "A Google Chrome tab".
    public var subject: String
    public var reading: Reading?
    public var verdict: Verdict?
    /// How we know, as full sentences.
    public var evidence: [String]
    /// What it means for you, as full sentences.
    public var effect: [String]

    /// The verdict leads the headline: on a memory card the verdict is about the whole Mac, and the subject is only who
    /// uses the most ("Apps and programs are using almost all of your Mac's memory. Google Chrome uses the most, 5.1 GB.").
    public var verdictFirst = false

    public init(_ subject: String, _ reading: Reading?, _ verdict: Verdict?, evidence: [String] = [], effect: [String] = [], verdictFirst: Bool = false) {
        self.subject = subject; self.reading = reading; self.verdict = verdict; self.evidence = evidence; self.effect = effect
        self.verdictFirst = verdictFirst
    }

    /// A word a reader may not know, defined once in the terms footer under the cards: one visible line that names
    /// it, under every card on screen, however many use it, so no card carries the definition itself: a standard place
    /// to explain terms. A term joins the list only when a card uses it and a reader is likely to confuse it.
    public struct Term: Equatable {
        public let id: String
        /// The words on a card that bring it up.
        public let pattern: String
        public let definition: String
    }

    /// Memory and storage, which many people don't tell apart: brought up by either word, since a card that says
    /// one may still leave the reader thinking of the other.
    public static let terms = [
        Term(id: "memory-storage", pattern: #"\b(?:[Mm]emory|[Ss]torage)\b"#,
             definition: "Memory is where apps and programs work. Storage is where your files are kept."),
    ]

    /// Every word a card shows: its headline, explanation, and each option's title and consequence.
    static func text(_ c: Card) -> String {
        ([c.headline, c.explanation] + c.fixes.flatMap { [$0.title, $0.consequence] }).joined(separator: " ")
    }

    /// The terms the footer defines under these cards, each once, in the list's order; empty when none is used.
    public static func terms(for cards: [Card]) -> [Term] {
        terms.filter { t in cards.contains { text($0).range(of: t.pattern, options: .regularExpression) != nil } }
    }

    /// One measurement; its type sets its words and its tense. Something still going on is said in the present, with
    /// "still … after" and how long (never "has been", which learners misread, and never the simple past, which reads
    /// as over: docs/CARD-TEMPLATE.md); the past is only for an event that is over. How hard something works is
    /// "working hard" here, and its figure is in Nerdy stuff, since a reader can't judge "1 core" (plain-reader review,
    /// 26 November 2026); the figure stays in the reading for a fuller rendering.
    public enum Reading: Equatable {
        /// "is working hard"
        case coresNow(Double)
        /// "still works hard at Slow and steady"
        case coresUnderLimit(Double, CPUCap.Level)
        /// "is still working hard after 1 hour"
        case coresFor(Double, TimeInterval)
        /// "is still keeping the graphics chip busy after 1 hour"
        case graphicsFor(Double, TimeInterval)
        /// "is still busy after 3 hours"
        case busyFor(TimeInterval)
        /// "is 96% done"
        case done(Double)
        /// "is working"
        case working
        /// "made its last progress at 1:39pm" (an event that is over)
        case noProgressAfter(Date)
        /// "started at 3:38pm" (an event that is over)
        case startedAt(Date)
        /// "waits for another job"
        case waitsFor(String)
        /// "is not busy now"
        case quiet
        /// Any other reading, in the present or, for an event that is over, the past, without its period.
        case words(String)

        public var words: String {
            switch self {
            case .coresNow: return "is working hard"
            case .coresUnderLimit(_, let l): return "still works hard at \(l.name)"
            case .coresFor(_, let d): return "is still working hard after \(Fmt.duration(d))"
            case .graphicsFor(_, let d): return "is still keeping the graphics chip busy after \(Fmt.duration(d))"
            case .busyFor(let d): return "is still busy after \(Fmt.duration(d))"
            case .done(let f): return "is \(Fmt.percent(f)) done"
            case .working: return "is working"
            case .noProgressAfter(let t): return "made its last progress at \(Fmt.time(t))"
            case .startedAt(let t): return "started at \(Fmt.time(t))"
            case .waitsFor(let what): return "waits for \(what)"
            case .quiet: return "is not busy now"
            case .words(let w): return w
            }
        }
    }

    /// What Cool Head thinks, from a closed set: each verdict has one meaning, and no card writes its own.
    public enum Verdict: Equatable {
        /// Expected; nothing to do.
        case normal
        /// Expected work after a macOS update.
        case normalAfterUpdate
        /// It was busy, and is not now.
        case notBusyNow
        /// Paused by you, and waiting for you to continue it.
        case waitsForYou
        /// It looks like malware (a disguise): the brief disclaimer is in "probably".
        case probablyHarmful
        /// It holds the Mac awake while it does almost nothing.
        case probablyForgot
        /// Expected work, running past its usual length.
        case longerThanUsual
        /// It costs more than this kind of thing normally does, and we know what it is.
        case moreThanUsual
        /// It just started; Cool Head checks again.
        case waitAFewMinutes
        /// No progress for a while, from what Cool Head sees.
        case probablyStuck
        /// Shown directly: a restart didn't clear it.
        case stuck
        /// macOS marks it Not Responding: macOS's own words, a fact.
        case notResponding
        /// Limited or slowed, and still making heat.
        case stillAddsHeat
        /// The Mac moves data from memory to storage. Said as what open apps do, not as what the Mac lacks, since the
        /// fix is to close something, not to buy memory a Mac can't take.
        case lowOnMemory
        /// macOS says memory is critical.
        case veryLowOnMemory
        /// It grew with the same windows open (see Leaks).
        case probablyLeaks
        /// A part that reports errors or a fault that can come before it stops working (the drive).
        case mayFail
        /// macOS or the part itself says it needs a repair (the battery).
        case needsService
        /// Wear from use, as expected (a battery or drive with fewer years left).
        case normalWear
        /// Plugged in, and the battery still loses charge.
        case batteryDrains
        /// A part that is warm or hot: what to do is give it a break (the one other verdict that's advice).
        case letItCool
        /// A forecast from its own progress.
        case finishAt(Date)
        /// Its own estimate has passed.
        case almostDone

        public var sentence: String {
            switch self {
            case .normal: return "This is normal."
            case .normalAfterUpdate: return "This is normal after an update."
            case .notBusyNow: return "It is not busy now."
            case .waitsForYou: return "It waits for you."
            case .probablyHarmful: return "It is probably harmful."
            case .probablyForgot: return "It probably forgot to stop."
            case .longerThanUsual: return "This is longer than usual."
            case .moreThanUsual: return "This is more than usual."
            case .waitAFewMinutes: return "Wait a few minutes."
            case .probablyStuck: return "It is probably stuck."
            case .stuck: return "It is stuck."
            case .notResponding: return "It is not responding."
            case .stillAddsHeat: return "It still adds heat."
            case .lowOnMemory: return "Apps and programs are using almost all of your Mac's memory."
            case .veryLowOnMemory: return "Apps and programs are using all of your Mac's memory."
            case .probablyLeaks: return "It probably leaks memory."
            case .mayFail: return "It may fail."
            case .needsService: return "It needs a repair."
            case .normalWear: return "This is normal wear."
            case .batteryDrains: return "The battery drains even when it is plugged in."
            case .letItCool: return "Let it cool."
            case .finishAt(let t): return "It will finish at about \(Fmt.time(t))."
            case .almostDone: return "It is almost done."
            }
        }

        /// The verdict said of the subject itself, when the headline has no reading: "Foo is not responding."
        var predicate: String? {
            switch self {
            case .notResponding: return "is not responding"
            case .stuck: return "is stuck"
            case .probablyStuck: return "is probably stuck"
            case .needsService: return "needs a repair"
            default: return nil
            }
        }
    }

    /// What an option loses, from a closed set.
    public enum Loss: Equatable {
        case nothing
        case unsaved
        /// A job with a known stretch of work.
        case upTo(TimeInterval)
        /// A job whose work is unknown.
        case workItDid
        /// An app that asks before it closes anything unsaved.
        case asksToSave

        public var sentence: String {
            switch self {
            case .nothing: return "Nothing is lost."
            case .unsaved: return "Unsaved work is lost."
            case .upTo(let d): return "You may lose up to \(Fmt.duration(d)) of its work."
            case .workItDid: return "You may lose the work it did."
            case .asksToSave: return "It asks you to save your work first."
            }
        }
    }

    /// Said after what an option does, where Cool Head can undo it from the card or the Managed list.
    public static let undo = "You can undo this."

    /// An option's consequence: what it does ("This closes all its tabs."), what you lose, and the undo.
    public static func says(_ does: String?, _ loss: Loss? = nil, undo: Bool = false) -> String {
        [does, loss?.sentence, undo ? CardTemplate.undo : nil].compactMap { $0 }.joined(separator: " ")
    }

    /// "the last hour", "the last 3 hours", "the last 25 minutes".
    static func last(_ d: TimeInterval) -> String {
        let words = Fmt.duration(d)
        switch words {
        case "1 hour": return "the last hour"
        case "1 minute", "under a minute": return "the last minute"
        default: return "the last \(words)"
        }
    }

    /// Effects joined into one sentence: "It adds heat, slows Hades, and uses a lot of battery power." Each is a verb
    /// phrase in the simple present; nil when there are none.
    public static func it(_ verbs: [String?]) -> String? {
        let v = verbs.compactMap { $0 }
        return v.isEmpty ? nil : "It \(Fmt.list(v))."
    }

    public var headline: String {
        let who = Fmt.sentenceStart(subject)
        guard let reading else {
            if let p = verdict?.predicate { return "\(who) \(p)." }
            return verdict.map { "\(who). \($0.sentence)" } ?? "\(who)."
        }
        if verdictFirst, let v = verdict { return "\(v.sentence) \(who) \(reading.words)." }
        return "\(who) \(reading.words)." + (verdict.map { " " + $0.sentence } ?? "")
    }

    /// Sentences in a text: ends at . ? or !, with any closing quote or bracket.
    static func sentences(_ s: String) -> Int {
        s.components(separatedBy: CharacterSet.newlines).joined(separator: " ")
            .matches(of: #/[.?!]["”')]?(\s|$)/#).count
    }

    /// The explanation's pieces, at most 3 sentences: evidence first, then effect. Over that, the first evidence and the
    /// first effect stay, and the rest fill in, in order, while they fit; what doesn't fit goes to Nerdy stuff, so it is
    /// moved, not lost (an independent review found optional sentences stacking up to 6 on real inputs).
    public var pieces: (shown: [String], overflow: [String]) {
        let all = evidence + effect
        guard all.map(CardTemplate.sentences).reduce(0, +) > 3 else { return (all, []) }
        let firstEffect = effect.isEmpty ? nil : evidence.count
        var order = [0] + (firstEffect.map { [$0] } ?? []) + all.indices.filter { $0 != 0 && $0 != firstEffect }
        order = order.filter { all.indices.contains($0) }
        var kept = Set<Int>(), count = 0
        for i in order {
            let n = CardTemplate.sentences(all[i])
            if count + n <= 3 || kept.isEmpty { kept.insert(i); count += n }
        }
        return (all.indices.filter(kept.contains).map { all[$0] }, all.indices.filter { !kept.contains($0) }.map { all[$0] })
    }

    public var explanation: String { pieces.shown.joined(separator: " ") }

    // MARK: - The check the selftest runs on every card made from the template

    /// Words and forms the rules leave out, each with the reason, found by a pattern (docs/CARD-TEMPLATE.md).
    static let banned: [(pattern: String, why: String)] = [
        (#"\b\w+n't\b"#, "a contraction"),
        (#"\b(?:it|that|there|what|here|who|let)'s\b"#, "a contraction"),
        (#"\b\w+'(?:re|ll|ve|d|m)\b"#, "a contraction"),
        (#"\b(?:has|have)\s+(?:not\s+)?(?:been|done|had|gone|made|kept|run|found|seen|grown|slept|left|lost|got|put|set|come|become|risen|taken|given|\w+ed)\b"#, "the present perfect"),
        (#"\b(?:likely|seems?|looks|might|could|perhaps)\b"#, "a word for how sure outside probably, may, and usually"),
        (#"\b(?:since|around)\b"#, "a time word outside for the last, at, after, and about"),
        (#"\b(?:we|us|our)\b"#, "\"we\", which is unclear on a card"),
        (#"\b(?:process(?:es)?|helpers?|stalled|frozen|tight|services?|disk space)\b"#, "a word the word list replaces"),
        (#"\b(?:give it a minute|look it up|share this case|undo any time|takes you to|quit and reopen|the cause is unknown|reports nothing about its work|for the last|low on memory|low memory|memory is low)\b"#, "an idiom or a replaced phrase"),
        // two-word verbs; macOS's own Turn on, Turn off, Shut down, Back up, and plugged in are allowed
        (#"\b(?:comes?|came) back\b|\bcarr(?:y|ies) on\b|\bfigures? (?:it )?out\b|\bsets? up\b|\bgo(?:es)? on\b|\blooks? up\b|\bgives? back\b|\bbrings? (?:it )?back\b|\bslows? down\b|\bturns? down\b"#, "a two-word verb"),
    ]
    /// Option titles that start with an action the word list replaces.
    static let replacedActions = #"^(?:End|Kill|Terminate|Resume|Bring)\b"#

    /// How each option's consequence may begin: "This …", or a fixed phrase.
    static let consequenceStarts = ["This ", "Use this only if ", "You lose no work from after "] + [Loss.nothing, .unsaved, .workItDid, .asksToSave].map(\.sentence) + ["You may lose up to "]

    /// A text's sentences: each ends at . ? or !, with any closing quote or bracket.
    static func split(_ s: String) -> [String] {
        s.replacingOccurrences(of: #"([.?!]["”')]?)\s+"#, with: "$1\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Every way a card's words break the rules, as "headline: a contraction (isn't)"; empty when none does. Names are
    /// left out of the words checked (a program may be called "helper"), and curly apostrophes count as straight ones.
    public static func problems(_ c: Card) -> [String] {
        var out: [String] = []
        var parts = [("headline", c.headline), ("explanation", c.explanation)]
        for f in c.fixes {
            parts.append(("\(f.id) title", f.title))
            parts.append(("\(f.id) consequence", f.consequence))
            if case .guide(let steps) = f.kind { parts += steps.map { ("\(f.id) step", $0) } }
            if case .reveal(_, let steps) = f.kind { parts.append(("\(f.id) step", steps)) }
            if !f.consequence.isEmpty, !consequenceStarts.contains(where: { f.consequence.hasPrefix($0) }) {
                out.append("\(f.id) consequence: doesn't start with This or a fixed phrase (\(f.consequence.prefix(30)))")
            }
            if f.title.hasSuffix(".") { out.append("\(f.id) title: ends with a period") }
            if f.title.range(of: replacedActions, options: .regularExpression) != nil { out.append("\(f.id) title: an action the word list replaces (\(f.title))") }
        }
        // a term is defined in the footer, never on the card (so it's said once, however many cards use it)
        for t in terms where text(c).contains(t.definition) || t.definition.split(separator: ".").contains(where: { text(c).contains($0.trimmingCharacters(in: .whitespaces)) }) {
            out.append("\(t.id): defined on the card, not in the terms footer")
        }
        // at most 3 sentences of explanation (docs/CARD-TEMPLATE.md)
        let sentences = split(c.explanation)
        if sentences.count > 3 { out.append("explanation: \(sentences.count) sentences, more than 3") }
        // "This" begins an option's consequence, where it is the option; in the explanation it would be unclear
        for s in sentences where s.hasPrefix("This ") {
            out.append("explanation: a sentence starts with This (\(s.prefix(30)))")
        }
        // names masked, macOS's own "Service Recommended" kept, curly apostrophes straightened
        let names = (c.names + [c.template?.subject].compactMap { $0 }).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        for (part, raw) in parts {
            var text = raw.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "Service Recommended", with: "Rating")
            for n in names { text = text.replacingOccurrences(of: n, with: "Name") }
            // a quoted name, such as the one Search the web looks for, is a name too
            text = text.replacingOccurrences(of: #"\x{201C}[^\x{201D}]*\x{201D}"#, with: "Name", options: .regularExpression)
            for b in banned {
                if let r = text.range(of: b.pattern, options: [.regularExpression, .caseInsensitive]) { out.append("\(part): \(b.why) (\(text[r]))") }
            }
            // at most 25 words a sentence (ASD-STE100, GOV.UK)
            for s in split(raw) where s.split(separator: " ").count > 25 {
                out.append("\(part): a sentence over 25 words (\(s.prefix(30))…)")
            }
        }
        return out
    }
}

extension Card {
    /// A card written from the template: its headline and explanation come from the slots.
    public init(state: JobState, _ t: CardTemplate, fixes: [Fix]) {
        self.init(state: state, headline: t.headline, explanation: t.explanation, fixes: fixes)
        template = t
        facts = t.pieces.overflow
    }

    /// This card with a sentence added, from an extra or a rule line, written through its template when it has one, so
    /// the 3-sentence limit and the rest of the rules hold; the card's record, names, and facts are kept.
    public func adding(evidence: String? = nil, effect: String? = nil, fixes newFixes: [Fix]? = nil) -> Card {
        var c: Card
        if var t = template {
            if let evidence { t.evidence.append(evidence.trimmingCharacters(in: .whitespaces)) }
            if let effect { t.effect.append(effect.trimmingCharacters(in: .whitespaces)) }
            c = Card(state: state, t, fixes: newFixes ?? fixes)
            c.facts = facts.filter { !(template?.pieces.overflow.contains($0) ?? false) } + c.facts
        } else {
            let added = [evidence, effect].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            c = Card(state: state, headline: headline, explanation: ([explanation] + added).filter { !$0.isEmpty }.joined(separator: " "), fixes: newFixes ?? fixes)
            c.facts = facts
        }
        c.names = names; c.cardID = cardID; c.choice = choice; c.diagnosis = diagnosis; c.optionFacts = optionFacts
        return c
    }
}

import Foundation

/// A program borrowing macOS's name or an Apple label (see Disguise.swift): who it is comes first, whatever it's doing.
enum DisguiseCard: ProcessCard {
    static let name = "a program that is not what it claims to be"
    static let id = "disguise"
    static let kind = CardKind.identity
    static let rule = "Disguise.swift: a program outside macOS's folders using one of macOS's names, or an Apple label it cannot have"
    static func confidence(_ s: Situation) -> Confidence { .named("we checked who signed the program") }
    static let samples = ["disguise-macos-name", "disguise-apple-label", "disguise-protection-off"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        switch s.disguise {
        case .macOSName?: c.diagnosis = Diagnosis(saw: "it uses a macOS name without Apple's signature, a common malware trick")
        case .appleLabel?: c.diagnosis = Diagnosis(saw: "it's labelled as Apple's without Apple's signature, a common malware trick")
        case .notAppleSigned?: c.diagnosis = Diagnosis(saw: "a program in macOS's own folders was changed while macOS's protection is off")
        default: break
        }
        c.optionFacts["delete"] = OptionFacts(helps: "removes it", undo: .other("You can put it back from the Trash if it turns out to be something you use."))
        c.optionFacts["loginitems"] = OptionFacts(helps: "stops it starting again")
        c.optionFacts["protect"] = OptionFacts(helps: "stops anything changing macOS's own programs", cost: "it takes a restart into Recovery")
        c.optionFacts["remove"] = OptionFacts(helps: "stops it and moves it to the Trash", undo: .other("You can put it back from the Trash if it turns out to be something you use."))
        return c
    }

    static func made(_ s: Situation) -> Card? { s.disguise.map { Disguise.card($0, s.e) } }
}

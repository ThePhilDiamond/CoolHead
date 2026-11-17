import Foundation

/// A program borrowing macOS's name or an Apple label (see Disguise.swift): who it is comes first, whatever it's doing.
enum DisguiseCard: ProcessCard {
    static let name = "a program that isn't what it claims to be"
    static let id = "disguise"
    static let kind = CardKind.identity
    static let rule = "Disguise.swift: a program outside macOS's folders using one of macOS's names, or an Apple label it can't have"
    static func confidence(_ s: Situation) -> Confidence { .named("Cool Head checked who signed the program") }
    static let samples = ["disguise-macos-name", "disguise-apple-label", "disguise-protection-off"]

    static func card(_ s: Situation) -> Card? { s.disguise.map { Disguise.card($0, s.e) } }
}

import Foundation
import PackagePlugin

/// Writes the lists that used to be kept by hand, from the names of the files in a target's folder, each time the
/// target is built (see notes in CONTRIBUTING.md, "Write where no one else is writing"):
///
/// - CoolHeadCore: every `Fixtures+<Feature>.swift` file's checks (`<feature>Checks`) and sample cards
///   (`<feature>Samples`), as `Fixture.suites` and `Fixture.sampleSuites`; and every file in its Cards folder, a card
///   (`<Name>Card.swift`, declaring `<Name>Card`) or an extra (`<Name>Extra.swift`, declaring `<Name>Extra`), as
///   `ProcessCards.all` and `ProcessCards.extras` (see ProcessCard.swift).
/// - CoolHeadApp: every `<Name>Cards.swift` file's card source (`<Name>Watch.shared`), as `CardSources.all`.
///
/// It reads file names only, never their contents, and writes one Swift file into its own work folder. A file whose
/// name promises a function or a source it doesn't declare fails to compile, so nothing can be left out silently.
/// Nothing is chosen while the app runs: the lists are fixed when it's built.
@main
struct Lists: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SourceModuleTarget else { return [] }
        let files = module.sourceFiles(withSuffix: "swift").map(\.path)
        let names = files.map(\.stem)
        let cards = files.filter { $0.removingLastComponent().lastComponent == "Cards" }.map(\.stem)
        let text: String
        switch target.name {
        case "CoolHeadCore": text = Lists.fixtures(names) + Lists.processCards(cards)
        case "CoolHeadApp": text = Lists.cardSources(names)
        default: return []
        }
        let folder = context.pluginWorkDirectory.appending("Lists")
        try FileManager.default.createDirectory(atPath: folder.string, withIntermediateDirectories: true)
        let file = folder.appending("Lists.swift")
        // written only when it changes, so an unchanged list doesn't rebuild the target
        if (try? String(contentsOfFile: file.string, encoding: .utf8)) != text {
            try text.write(toFile: file.string, atomically: true, encoding: .utf8)
        }
        // the file is already written; this command only tells the build to compile what's in the folder
        return [.prebuildCommand(displayName: "Lists for \(target.name)", executable: Path("/usr/bin/true"), arguments: [],
                                 outputFilesDirectory: folder)]
    }

    static let header = "// Written by the Lists build plugin (Plugins/Lists/Lists.swift) from this target's file names. It isn't in\n// the repository; to change a list, add, rename or remove a file.\n"

    /// "CrashLoops" -> "crashLoops".
    static func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// The part after a prefix and before a suffix, for names that have both.
    static func features(_ names: [String], prefix: String = "", suffix: String = "") -> [String] {
        names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) && $0.count > prefix.count + suffix.count }
            .map { String($0.dropFirst(prefix.count).dropLast(suffix.count)) }
            .sorted()
    }

    static func fixtures(_ names: [String]) -> String {
        let f = features(names, prefix: "Fixtures+")
        return header + """
            import Foundation

            extension Fixture {
                /// Each Fixtures+<Feature>.swift file's checks, alphabetical by file name.
                static let suites: [(Date) -> [(String, Bool, String)]] = [
            \(f.map { "        \(lower($0))Checks," }.joined(separator: "\n"))
                ]

                /// Each Fixtures+<Feature>.swift file's sample cards, alphabetical by file name.
                static let sampleSuites: [(Date) -> [(String, Card)]] = [
            \(f.map { "        \(lower($0))Samples," }.joined(separator: "\n"))
                ]
            }

            """
    }

    static func processCards(_ names: [String]) -> String {
        """

        /// Every card about a busy process, and every extra, from the files in Sources/CoolHeadCore/Cards, alphabetical
        /// by file name (see ProcessCard.swift).
        public enum ProcessCards {
            public static let all: [any ProcessCard.Type] = [
        \(features(names, suffix: "Card").map { "        \($0)Card.self," }.joined(separator: "\n"))
            ]
            public static let extras: [any CardExtra.Type] = [
        \(features(names, suffix: "Extra").map { "        \($0)Extra.self," }.joined(separator: "\n"))
            ]
        }

        """
    }

    static func cardSources(_ names: [String]) -> String {
        let f = features(names, suffix: "Cards")
        return header + """
            /// Every card source, from each <Name>Cards.swift file, alphabetical by file name (see CardSources.swift).
            @MainActor
            enum CardSources {
                static let all: [any CardSource] = [
            \(f.map { "        \($0)Watch.shared," }.joined(separator: "\n"))
                ]
            }

            """
    }
}

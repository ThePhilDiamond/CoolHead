import Foundation

/// Checks for saving before a quit (see SaveAndQuit): which apps can be told to save, what osascript's answers mean,
/// and how a quit option is worded.
extension Fixture {
    static func saveAndQuitChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []

        // which apps can be told to save: their details say so; a stand-in app without it can't; a missing app can't
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "coolhead-savequit-\(getpid())-\(UUID().uuidString.prefix(8))"
        func app(_ name: String, _ info: [String: Any]) -> String {
            let path = dir + "/\(name).app"
            try? fm.createDirectory(atPath: path + "/Contents", withIntermediateDirectories: true)
            try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
            return path
        }
        let yes = app("Scripted", ["CFBundleIdentifier": "org.example.scripted", "NSAppleScriptEnabled": true])
        let dictionary = app("Dictionary", ["CFBundleIdentifier": "org.example.dictionary", "OSAScriptingDefinition": "App.sdef"])
        let no = app("Plain", ["CFBundleIdentifier": "org.example.plain"])
        defer { try? fm.removeItem(atPath: dir) }
        let textEdit = SaveAndQuit.scriptable(bundle: "/System/Applications/TextEdit.app")
        let r1 = SaveAndQuit.scriptable(bundle: yes) && SaveAndQuit.scriptable(bundle: dictionary) && !SaveAndQuit.scriptable(bundle: no)
            && !SaveAndQuit.scriptable(bundle: dir + "/Missing.app") && textEdit
        review.append(("save-quit-which-apps", r1, "stand-ins told apart; TextEdit can be told to save \(textEdit)"))

        // osascript's answers: done, not allowed (-1743), cancelled (-128), anything else; a bad identifier never runs
        let o = SaveAndQuit.outcome
        let r2 = o(0, "") == .quit
            && o(1, "execution error: Not authorized to send Apple events to TextEdit. (-1743)") == .notAllowed
            && o(1, "execution error: TextEdit got an error: User canceled. (-128)") == .cancelled
            && o(1, "execution error: TextEdit got an error: Connection is invalid. (-609)") == .failed("execution error: TextEdit got an error: Connection is invalid. (-609)")
            && SaveAndQuit.runBlocking(bundleID: "x\"; do shell script \"true") == .failed("not an app identifier")
            && SaveAndQuit.runBlocking(bundleID: "") == .failed("not an app identifier")
        review.append(("save-quit-answers", r2, "quit, not allowed, cancelled and other errors told apart; an identifier with quotes is refused"))

        // the wording: a quit that relies on the app asking says Cool Head saves first, where it can; nothing else changes
        let quit = Fix(id: "quit", title: "Quit Pages", consequence: "Frees 2.0 GB. Save your work first; it asks about anything unsaved.", kind: .quitApp(yes))
        let plain = Fix(id: "quit", title: "Quit Plain", consequence: "Frees 2.0 GB. Save your work first; it asks about anything unsaved.", kind: .quitApp(no))
        let slack = Fix(id: "quit", title: "Quit Slack", consequence: "Frees 1.1 GB. No messages until you reopen it.", kind: .quitApp(yes))
        let reopen = Fix(id: "reopen", title: "Quit and reopen Scripted", consequence: "Save your work first. Gives back about 7.4 GB; some windows may not reopen.", kind: .restartApp(yes))
        let card = Card(state: .unknown, headline: "x", explanation: "y", fixes: [quit, plain, slack, reopen])
        let r3 = card.fixes.first { $0.id == "quit" && $0.title == "Quit Pages" }?.consequence == "Frees 2.0 GB. Saves your work first, then quits."
            && card.fixes.first { $0.title == "Quit Plain" }?.consequence == plain.consequence
            && card.fixes.first { $0.title == "Quit Slack" }?.consequence == slack.consequence
            && card.fixes.first { $0.id == "reopen" }?.consequence == "Saves your work first. Gives back about 7.4 GB; some windows may not reopen."
        review.append(("save-quit-wording", r3, card.fixes.map { "\($0.title): \($0.consequence)" }.joined(separator: " | ")))
        return review
    }
}

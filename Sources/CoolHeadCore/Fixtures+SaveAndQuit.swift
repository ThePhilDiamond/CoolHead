import Foundation

/// Checks for saving before a quit (see SaveAndQuit): which apps can be told to save, what osascript's answers mean,
/// and how a quit option is worded.
extension Fixture {
    /// The example cards (see Wording): an app Cool Head can save in, on the memory card, and leaking.
    static func saveAndQuitSamples(_ now: Date) -> [(String, Card)] {
        let te = "/System/Applications/TextEdit.app"
        let textEdit = MemGroup(key: te, name: "TextEdit", kind: .app, bundle: te, bytes: 6_200_000_000, count: 1)
        let slack = MemGroup(key: "/Applications/Slack.app", name: "Slack", kind: .app, bundle: "/Applications/Slack.app", bytes: 1_200_000_000, count: 5)
        var tight = MacState(); tight.memoryPressure = "warning"; tight.swapUsedMB = 2500; tight.swapTotalMB = 4096
        let leak = Leaks.Leak(from: 900_000_000, to: 6_200_000_000, since: now.addingTimeInterval(-3 * 3600))
        return [("memory-save-and-quit", MemoryAdvice.card([textEdit, slack], mac: tight, now: now)),
                ("memory-leaking-app-save", MemoryAdvice.card([textEdit, slack], mac: tight, now: now, leak: leak))]
    }

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

        // where Cool Head can save, a quit is two options: save and quit (taking the quit's recommendation), and the plain
        // quit, where the app asks; nothing is saved without its own press (Phil, 17 November 2026: "I don't think we
        // should auto-save anything"); the same for Quit and reopen; others unchanged
        let quit = Fix(id: "quit", title: "Quit Scripted", consequence: "Frees 2.0 GB. Save your work first; it asks about anything unsaved.", kind: .quitApp(yes), recommended: true)
        let plain = Fix(id: "quit", title: "Quit Plain", consequence: "Frees 2.0 GB. Save your work first; it asks about anything unsaved.", kind: .quitApp(no))
        let slack = Fix(id: "quit2", title: "Quit Slack", consequence: "Frees 1.1 GB. No messages until you reopen it.", kind: .quitApp(yes))
        let reopen = Fix(id: "reopen", title: "Quit and reopen Scripted", consequence: "Save your work first. Gives back about 7.4 GB; some windows may not reopen.", kind: .restartApp(yes))
        let card = Card(state: .unknown, headline: "x", explanation: "y", fixes: [quit, plain, slack, reopen])
        func f(_ title: String) -> Fix? { card.fixes.first { $0.title == title } }
        let r3 = f("Save and quit Scripted")?.kind == .saveAndQuit(yes, reopen: false) && f("Save and quit Scripted")?.recommended == true
            && f("Save and quit Scripted")?.consequence == "Frees 2.0 GB. Saves every open document first."
            && f("Quit Scripted")?.consequence == "Frees 2.0 GB. It asks about anything unsaved." && f("Quit Scripted")?.recommended == false
            && f("Quit Plain")?.consequence == plain.consequence && f("Save and quit Plain") == nil
            && f("Quit Slack")?.consequence == slack.consequence && f("Save and quit Slack") == nil
            && f("Save and reopen Scripted")?.kind == .saveAndQuit(yes, reopen: true)
            && f("Save and reopen Scripted")?.consequence == "Saves every open document first. Gives back about 7.4 GB; some windows may not reopen."
            && f("Quit and reopen Scripted")?.consequence == "It asks about anything unsaved. Gives back about 7.4 GB; some windows may not reopen."
            && card.fixes.filter(\.recommended).count == 1
        review.append(("save-quit-two-options", r3, card.fixes.map { "\($0.title)\($0.recommended ? " (recommended)" : ""): \($0.consequence)" }.joined(separator: " | ")))
        return review
    }
}

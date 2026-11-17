import Foundation

/// Saving for you before a quit, where the app allows it, and only when you choose it (Phil, 16 November 2026: *"if we
/// can save and quit for the user that'd be the best option for least effort most value"*; 17 November 2026: *"I don't
/// think we should auto-save anything, in case a user doesn't want to save. We could have two buttons"*).
///
/// An app that supports AppleScript can be told `quit saving yes`: it saves its open documents, then quits (a document
/// never saved before still asks where to save it). macOS doesn't ask permission for the quit command itself (tested
/// 16 November 2026 with TextEdit on 26.6.2: a changed document saved and TextEdit quit, with no prompt for the quit);
/// if the app refuses, or doesn't answer, it stays open and the panel says so. It is only ever done when you press
/// "Save and quit": the plain Quit beside it lets the app ask about each unsaved document. Cool Head's Info.plist
/// carries the reason macOS would show if it did ask (NSAppleEventsUsageDescription). Apps without AppleScript (most
/// Electron apps: Slack, Figma, VS Code) get only the plain Quit. Stop and Force Quit can't save: they end a program at
/// once, so the panel asks "Did you save?" first.
public enum SaveAndQuit {
    /// The app supports AppleScript: its details say so, or it has a scripting dictionary.
    public static func scriptable(bundle: String) -> Bool {
        guard let info = Bundle(path: bundle)?.infoDictionary else { return false }
        return (info["NSAppleScriptEnabled"] as? Bool) == true || (info["NSAppleScriptEnabled"] as? String) == "YES"
            || info["OSAScriptingDefinition"] != nil
    }

    public enum Outcome: Equatable {
        case quit                 // it saved and quit
        case notAllowed           // macOS didn't let Cool Head control it
        case cancelled            // you cancelled a save dialog, so it stayed open
        case failed(String)       // anything else, with the error's own words
    }

    /// What osascript's error text means (its number in brackets at the end).
    public static func outcome(status: Int32, error: String) -> Outcome {
        if status == 0 { return .quit }
        if error.contains("(-1743)") { return .notAllowed }
        if error.contains("(-128)") { return .cancelled }
        return .failed(error.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Asks the app with this identifier to save and quit, and waits (up to 10 minutes, for a save dialog you may be
    /// filling in). Blocks: call it off the main thread.
    public static func runBlocking(bundleID: String) -> Outcome {
        guard !bundleID.isEmpty, bundleID.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) }) else { return .failed("not an app identifier") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "with timeout of 600 seconds", "-e", "tell application id \"\(bundleID)\" to quit saving yes", "-e", "end timeout"]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return .failed(error.localizedDescription) }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return outcome(status: p.terminationStatus, error: String(decoding: data, as: UTF8.self))
    }

    public static func run(bundleID: String) async -> Outcome {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: runBlocking(bundleID: bundleID)) }
        }
    }

    /// The words a quit option ends with when it relies on the app asking.
    static let asks = "Save your work first; it asks about anything unsaved."
    static let saveFirst = "Save your work first. "

    /// Where Cool Head can save for you, a quit becomes two options, so nothing is saved without your choosing it (Phil,
    /// 17 November 2026: *"I don't think we should auto-save anything, in case a user doesn't want to save"*):
    /// "Save and quit" (recommended where the quit was), and the plain quit, where the app asks about anything unsaved.
    /// Quit and reopen (see Leaks) the same: "Save and reopen", and the plain one. Anything else is left as it is.
    public static func options(_ f: Fix, scriptable: (String) -> Bool = { scriptable(bundle: $0) }) -> [Fix] {
        func copy(_ f: Fix, id: String, title: String, consequence: String, kind: Fix.Kind, recommended: Bool) -> Fix {
            var g = Fix(id: id, title: title, consequence: consequence, kind: kind, recommended: recommended)
            g.resultOverride = f.resultOverride; g.holdBack = f.holdBack; g.cautionOverride = f.cautionOverride
            return g
        }
        switch f.kind {
        case .quitApp(let bundle) where f.consequence.contains(asks) && scriptable(bundle):
            let app = String(f.title.dropFirst("Quit ".count))
            let save = copy(f, id: "save" + f.id, title: "Save and quit \(app)",
                            consequence: f.consequence.replacingOccurrences(of: asks, with: "Saves every open document first."),
                            kind: .saveAndQuit(bundle, reopen: false), recommended: f.recommended)
            var plain = copy(f, id: f.id, title: f.title, consequence: f.consequence.replacingOccurrences(of: asks, with: "It asks about anything unsaved."),
                             kind: f.kind, recommended: false)
            plain.cautionOverride = f.cautionOverride
            return [save, plain]
        case .restartApp(let bundle) where f.consequence.hasPrefix(saveFirst) && scriptable(bundle):
            let app = String(f.title.dropFirst("Quit and reopen ".count))
            let rest = String(f.consequence.dropFirst(saveFirst.count))
            return [copy(f, id: "save" + f.id, title: "Save and reopen \(app)", consequence: "Saves every open document first. " + rest,
                         kind: .saveAndQuit(bundle, reopen: true), recommended: f.recommended),
                    copy(f, id: f.id, title: f.title, consequence: "It asks about anything unsaved. " + rest, kind: f.kind, recommended: false)]
        default:
            return [f]
        }
    }
}

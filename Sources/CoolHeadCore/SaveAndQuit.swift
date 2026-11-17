import Foundation

/// Saving for you before a quit, where the app allows it (Phil, 16 November 2026: *"if we can save and quit for the
/// user that'd be the best option for least effort most value"*; asked which way, *"Save for you, guard the rest"*).
///
/// An app that supports AppleScript can be told `quit saving yes`: it saves its open documents, then quits (a document
/// never saved before still asks where to save it). macOS doesn't ask permission for the quit command itself (tested
/// 16 November 2026 with TextEdit on 26.6.2: a changed document saved and TextEdit quit, with no prompt for the quit);
/// if an app ever refuses, or doesn't answer, Cool Head falls back to a normal quit, where the app asks about anything
/// unsaved. Cool Head's Info.plist carries the reason macOS would show if it did ask (NSAppleEventsUsageDescription). Apps without AppleScript (most Electron apps: Slack, Figma, VS Code) get the normal quit. Stop and Force
/// Quit can't save: they end a program at once, so the panel asks "Did you save?" first.
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

    /// The words a quit option ends with when it relies on the app asking: replaced, where Cool Head can save for you.
    static let asks = "Save your work first; it asks about anything unsaved."

    /// A quit option, worded for what will happen: "Saves your work first, then quits." where Cool Head can save for you.
    public static func worded(_ f: Fix, scriptable: (String) -> Bool = { scriptable(bundle: $0) }) -> Fix {
        guard case .quitApp(let bundle) = f.kind, f.consequence.contains(asks), scriptable(bundle) else { return f }
        var g = Fix(id: f.id, title: f.title, consequence: f.consequence.replacingOccurrences(of: asks, with: "Saves your work first, then quits."),
                    kind: f.kind, recommended: f.recommended)
        g.resultOverride = f.resultOverride; g.holdBack = f.holdBack; g.cautionOverride = f.cautionOverride
        return g
    }
}

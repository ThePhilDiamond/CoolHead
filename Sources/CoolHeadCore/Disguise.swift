import Foundation
import Security

/// A program that borrows macOS's name, or an Apple launch label, without being macOS's own (research rule 2, node N-021).
///
/// A name counts only in macOS's own folders, which System Integrity Protection keeps anyone else from writing to (see
/// `Pattern.matches`). So a program that calls itself by one of macOS's names from anywhere else isn't macOS's. Miners
/// hidden in pirated apps have run as `mdworker_local` and `mdworker_shared` from /private/tmp and /usr/local/bin
/// (Jamf Threat Labs, 23 February 2023; Intego, 9 March 2023), and a backdoor has used the label com.apple.qtop for its
/// helper in ~/Library/LaunchAgents (Jamf, September 2025). The card says what Cool Head thinks ("pretending to be part
/// of macOS"), a brief disclaimer, and its advice (Phil, 16 November 2026: "Say what we think, use a brief disclaimer,
/// then give our advice"). It never says "is malware": an Apple installer has left an unsigned
/// com.apple.installer.osmessagetracing.plist in /Library/LaunchDaemons (Apple Community 254334032), and someone's own
/// tool can share a name with one of macOS's.
///
/// Apple's own programs outside macOS's folders (Xcode's simulators run copies of macOS's services) pass the test
/// `anchor apple`, which only programs Apple signed pass; a Developer ID or no signature fails it. "No Team ID" is not
/// the same: Apple's programs and unsigned tools both show none.
///
/// Only reads: the process's own facts, `csrutil status`, the launch plists' text and code signatures. Nothing is
/// deleted, and nothing is turned off without a press.
public enum Disguise {
    public enum Finding: Equatable {
        /// One of macOS's names (the kernel's, or the name it gave itself), on a program outside macOS's folders that Apple
        /// didn't sign.
        case macOSName(name: String, path: String)
        /// One of macOS's names, but macOS didn't say where its program is, so it couldn't be checked.
        case unchecked(name: String)
        /// One of macOS's names in macOS's folders, but System Integrity Protection is off, so the folders aren't
        /// protected, and Apple didn't sign this copy.
        case notAppleSigned(name: String, path: String)
        /// Started by a launch item labelled like Apple's (com.apple.…), outside macOS's folders, whose program Apple
        /// didn't sign.
        case appleLabel(label: String, plist: String, program: String)
    }

    /// A launch item labelled like Apple's, from its plist (read as a file; nothing is run).
    public struct LaunchItem: Equatable {
        public let label: String
        public let plist: String
        public let program: String
        public let appleSigned: Bool
        public init(label: String, plist: String, program: String, appleSigned: Bool) {
            self.label = label; self.plist = plist; self.program = program; self.appleSigned = appleSigned
        }
    }

    /// Where launch items outside macOS's folders live: yours, everyone's, and the system's.
    public static var folders: [String] {
        [NSHomeDirectory() + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
    }

    /// The decision, from facts passed in, so the selftest can check it without this Mac's state.
    public static func judge(_ e: Evidence, sipOff: Bool, appleSigned: (String) -> Bool, launchItems: [LaunchItem]) -> Finding? {
        // the kernel's name, then the name it gave itself (exec -a changes only that one); a script is named by its file
        let given = e.args.first.map { ($0 as NSString).lastPathComponent }
        if e.script == nil, let name = [e.name, given].compactMap({ $0 }).first(where: Pattern.isMacOSName) {
            guard let path = e.path else { return e.pid == 0 ? nil : .unchecked(name: name) }
            if !CaseReport.isMacOS(path) {
                if !appleSigned(path) { return .macOSName(name: name, path: path) }
            } else if sipOff && !appleSigned(path) {
                return .notAppleSigned(name: name, path: path)
            }
        }
        // a launch item labelled like Apple's that started this process, or one that started it
        let programs = Set(([e.path] + e.ancestors.map(\.path)).compactMap { $0 }.map(resolve))
        if let item = launchItems.first(where: { !$0.appleSigned && programs.contains(resolve($0.program)) }) {
            return .appleLabel(label: item.label, plist: item.plist, program: item.program)
        }
        return nil
    }

    /// The decision for a process on this Mac.
    public static func find(_ e: Evidence) -> Finding? {
        judge(e, sipOff: sipOff, appleSigned: appleSigned, launchItems: cache.items(folders))
    }

    static func resolve(_ p: String) -> String { (p as NSString).resolvingSymlinksInPath }

    // MARK: what is read

    /// System Integrity Protection is off, wholly or in part, as `csrutil status` says (readable without a password).
    /// Read once: changing it needs a restart into Recovery.
    public static let sipOff: Bool = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        p.arguments = ["status"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return sipOffSaid(String(decoding: data, as: UTF8.self))
    }()

    /// "System Integrity Protection status: disabled.", or a custom configuration with any protection disabled.
    static func sipOffSaid(_ status: String) -> Bool { status.lowercased().contains("disabled") }

    /// Signed by Apple itself (`anchor apple`), checked on the file; cached per path while the file is unchanged.
    public static func appleSigned(_ path: String) -> Bool {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        let key = "\(path)|\((a?[.systemFileNumber] as? Int) ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        if let known = signatures.value[key] { return known }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var ok = false
        if SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
           SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess, let requirement {
            ok = SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        }
        signatures.with { $0[key] = ok }
        return ok
    }
    static let signatures = Locked<[String: Bool]>([:])

    /// The launch items in these folders labelled com.apple.…, with whether Apple signed what each starts.
    public static func launchItems(in dirs: [String]) -> [LaunchItem] {
        dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix("com.apple.") && $0.hasSuffix(".plist") }.sorted()
                .compactMap { file -> LaunchItem? in
                    let path = dir + "/" + file
                    guard let data = FileManager.default.contents(atPath: path),
                          let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                          let label = d["Label"] as? String, label.hasPrefix("com.apple."),
                          let prog = BackgroundAgents.program(d), prog.hasPrefix("/") else { return nil }
                    return LaunchItem(label: label, plist: path, program: prog, appleSigned: appleSigned(prog))
                }
        }
    }

    /// The plists are read again only when a folder changes.
    final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var key = ""
        var list: [LaunchItem] = []
        func items(_ dirs: [String]) -> [LaunchItem] {
            let k = dirs.map { d in "\(d):\(((try? FileManager.default.attributesOfItem(atPath: d))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" }
                .joined(separator: "|")
            lock.lock(); defer { lock.unlock() }
            if k != key { list = Disguise.launchItems(in: dirs); key = k }
            return list
        }
    }
    static let cache = Cache()

    // MARK: the card

    /// Where a program is, in words: "a temporary folder", "your Downloads folder", or its folder.
    static func place(_ path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        if ["/private/tmp", "/tmp", "/private/var/folders", "/var/folders"].contains(where: { dir == $0 || dir.hasPrefix($0 + "/") }) { return "a temporary folder" }
        let home = NSHomeDirectory()
        if dir == home + "/Downloads" || dir.hasPrefix(home + "/Downloads/") { return "your Downloads folder" }
        return dir.hasPrefix(home + "/") ? "~" + dir.dropFirst(home.count) : dir
    }

    /// The one disclaimer every finding carries, kept short: the terms of use say the rest.
    static let disclaimer = "We can't be certain it's harmful."

    /// The card for a finding, in place of the usual one: who it is comes before what it's doing (research rules,
    /// "Order of evaluation"). What Cool Head thinks, the disclaimer, then its advice, which is the recommended option.
    public static func card(_ f: Finding, _ e: Evidence) -> Card {
        let delete = { (path: String, steps: String, rec: Bool) in
            Fix(id: "delete", title: "Delete it", consequence: "Shows it in Finder, to drag to the Trash.", kind: .reveal(path, steps), recommended: rec).fixingTheCause()
        }
        switch f {
        case .macOSName(let name, let path):
            let stop: Fix? = e.mine ? Fix(id: "stop", title: "Stop it", consequence: "Ends it now. Delete it too, or it may come back.", kind: .stop, recommended: true) : nil
            return Card(state: .unknown, headline: "\(name) is pretending to be part of macOS.",
                        explanation: "It uses a macOS name but runs from \(place(path)), without Apple's signature: a common malware trick. \(disclaimer) Stop it, then delete it.",
                        fixes: [stop, delete(path, "Drag it to the Trash, then empty the Trash.", stop == nil), Card.share].compactMap { $0 })
        case .unchecked(let name):
            return Card(state: .working, headline: "\(name) is probably part of macOS, but we couldn't confirm it.",
                        explanation: "macOS didn't say where its program lives. Nothing to do unless it stays busy for hours.",
                        fixes: [Card.share])
        case .notAppleSigned(let name, _):
            return Card(state: .unknown, headline: "This copy of \(name) isn't Apple's.",
                        explanation: "System Integrity Protection is off, so macOS's own programs can be replaced, and this one has been. \(disclaimer) Turn protection back on and reinstall macOS; your files are kept.",
                        fixes: [Fix.guide("restore", "Turn protection on and reinstall macOS", "Puts back Apple's own copy. Your files and apps are kept.",
                                          steps: ["Shut down your Mac.", "Press and hold the power button until the startup options appear, then choose Options to start in Recovery.",
                                                  "Choose Utilities ▸ Terminal, type csrutil enable, press Return, then quit Terminal.",
                                                  "Choose Reinstall macOS and follow the steps."], recommended: true).fixingTheCause(),
                                Card.share])
        case .appleLabel(let label, let plist, let program):
            let folder = (plist as NSString).deletingLastPathComponent
            let shown = folder == NSHomeDirectory() + "/Library/LaunchAgents" ? "your LaunchAgents folder" : folder
            let file = (program as NSString).lastPathComponent
            var off: Fix?
            if folder == "/Library/LaunchDaemons" {
                // the system's own launch items need an administrator to turn off (see the padlock line in the research)
                off = Fix.guide("loginitems", "Turn it off in Login Items", "Needs an administrator password.",
                                steps: ["Open System Settings ▸ General ▸ Login Items & Extensions.",
                                        "Under Allow in the Background, find the item for \(file) and switch it off.",
                                        "Enter an administrator password if asked."], recommended: true)
            } else if e.mine {
                // in your login session: the same turning off as another app's helper (see BackgroundAgents), which allows a
                // com.apple label only when Apple didn't sign the program
                var a = BackgroundAgents.fix(BackgroundAgents.Agent(label: label, plist: plist, program: program, owner: label))
                a.recommended = true
                off = a
            }
            return Card(state: .unknown, headline: "A background item is pretending to be Apple's.",
                        explanation: "\(label) starts \(file) from \(shown), without Apple's signature: a common malware trick. \(disclaimer) Turn it off, then delete it.",
                        fixes: [off, delete(plist, "Drag it to the Trash, and its program, \(file), too.", off == nil), Card.share].compactMap { $0 })
        }
    }
}

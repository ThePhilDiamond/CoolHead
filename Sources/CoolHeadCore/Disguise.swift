import Foundation
import Security

/// A program that borrows macOS's name, or an Apple launch label, without being macOS's own (research rule 2, node N-021).
///
/// A name counts only in macOS's own folders, which System Integrity Protection keeps anyone else from writing to (see
/// `Pattern.matches`). So a program that calls itself by one of macOS's names from anywhere else isn't macOS's. Miners
/// hidden in pirated apps have run as `mdworker_local` and `mdworker_shared` from /private/tmp and /usr/local/bin
/// (Jamf Threat Labs, 23 February 2023; Intego, 9 March 2023), and a backdoor has used the label com.apple.qtop for its
/// helper in ~/Library/LaunchAgents (Jamf, September 2025). The card says what Cool Head thinks ("pretending to be part
/// of macOS"), a brief disclaimer, and its advice. It never says "is malware": an Apple installer has left an unsigned
/// com.apple.installer.osmessagetracing.plist in /Library/LaunchDaemons (Apple Community 254334032), and someone's own
/// tool can share a name with one of macOS's.
///
/// Apple's own programs outside macOS's folders (Xcode's simulators run copies of macOS's services) pass the test
/// `anchor apple`, which only programs Apple signed pass; a Developer ID or no signature fails it. "No Team ID" is not
/// the same: Apple's programs and unsigned tools both show none.
///
/// A finding needs a definite answer: a signature that is missing, broken or someone else's, never a check that failed
/// for another reason. "Isn't Apple's" inside macOS's folders also needs those folders to be changeable at all, since
/// reinstalling macOS is a huge ask and that advice needs more confidence than any other; even then, a reinstall is
/// offered, never recommended.
///
/// Only reads: the process's own facts, `csrutil status` and `csrutil authenticated-root status`, the launch plists'
/// text and code signatures. Nothing is deleted, turned off or moved to the Trash without a press and a confirmation.
public enum Disguise {
    public enum Finding: Equatable {
        /// One of macOS's names (the kernel's, or the name it gave itself), on a program outside macOS's folders that Apple
        /// didn't sign.
        case macOSName(name: String, path: String)
        /// One of macOS's names, but macOS didn't say where its program is, so it couldn't be checked.
        case unchecked(name: String)
        /// One of macOS's names in macOS's folders that could have been changed (see `changeable`), and this copy's
        /// signature is missing, broken or someone else's.
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
        public let signer: Signer
        public init(label: String, plist: String, program: String, signer: Signer) {
            self.label = label; self.plist = plist; self.program = program; self.signer = signer
        }
    }

    /// Where launch items outside macOS's folders live: yours, everyone's, and the system's.
    public static var folders: [String] {
        [NSHomeDirectory() + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
    }

    /// Who signed a program, as far as can be told for certain.
    public enum Signer: Equatable {
        case apple       // passes `anchor apple`
        case other       // unsigned, a broken signature, or signed by someone else: a definite "not Apple's"
        case unknown     // the check itself failed (the file is gone, unreadable, or something else went wrong): no finding
    }

    /// What protects macOS's folders on this Mac now.
    public struct Protection: Equatable {
        public var sipOff = false
        public var sealBroken = false     // authenticated root off: the sealed system volume can be changed
        public init(sipOff: Bool = false, sealBroken: Bool = false) { self.sipOff = sipOff; self.sealBroken = sealBroken }
    }

    /// Whether a program in macOS's folders could have been changed at all. The system volume (/System, /usr, /bin,
    /// /sbin) is sealed: a changed file there can't even start unless the seal is off. /Library/Apple is on the data
    /// volume, protected only by System Integrity Protection.
    static func changeable(_ path: String, _ p: Protection) -> Bool {
        path.hasPrefix("/Library/Apple/") ? p.sipOff : p.sealBroken
    }

    /// The decision, from facts passed in, so the selftest can check it without this Mac's state.
    public static func judge(_ e: Evidence, protection: Protection, signer: (String) -> Signer, launchItems: [LaunchItem]) -> Finding? {
        // the kernel's name, then the name it gave itself (exec -a changes only that one); a script is named by its file
        let given = e.args.first.map { ($0 as NSString).lastPathComponent }
        if e.script == nil, let name = [e.name, given].compactMap({ $0 }).first(where: Pattern.isMacOSName) {
            guard let path = e.path else { return e.pid == 0 ? nil : .unchecked(name: name) }
            if !CaseReport.isMacOS(path) {
                if signer(path) == .other { return .macOSName(name: name, path: path) }
            } else if changeable(path, protection) && signer(path) == .other {
                return .notAppleSigned(name: name, path: path)
            }
        }
        // a launch item labelled like Apple's that started this process, or one that started it
        let programs = Set(([e.path] + e.ancestors.map(\.path)).compactMap { $0 }.map(resolve))
        if let item = launchItems.first(where: { $0.signer == .other && programs.contains(resolve($0.program)) }) {
            return .appleLabel(label: item.label, plist: item.plist, program: item.program)
        }
        return nil
    }

    /// The decision for a process on this Mac.
    public static func find(_ e: Evidence) -> Finding? {
        judge(e, protection: protection, signer: signer, launchItems: cache.items(folders))
    }

    static func resolve(_ p: String) -> String { (p as NSString).resolvingSymlinksInPath }

    // MARK: what is read

    /// Read once (changing either needs a restart into Recovery), with no password: `csrutil status` and
    /// `csrutil authenticated-root status`.
    public static let protection = Protection(sipOff: disabledSaid(csrutil(["status"])), sealBroken: disabledSaid(csrutil(["authenticated-root", "status"])))

    static func csrutil(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// "System Integrity Protection status: disabled.", a custom configuration with any protection disabled, or
    /// "Authenticated Root status: disabled".
    static func disabledSaid(_ status: String) -> Bool { status.lowercased().contains("disabled") }

    /// Who signed the program at this path, checked on the file against `anchor apple`; cached per path while the file is
    /// unchanged. Only a missing, broken or foreign signature counts as `.other`.
    public static func signer(_ path: String) -> Signer {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        guard a != nil else { return .unknown }
        let key = "\(path)|\((a?[.systemFileNumber] as? Int) ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        if let known = signatures.value[key] { return known }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var result = Signer.unknown
        if SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
           SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess, let requirement {
            result = signer(status: SecStaticCodeCheckValidity(code, [], requirement))
        }
        signatures.with { $0[key] = result }
        return result
    }
    static let signatures = Locked<[String: Signer]>([:])

    /// The check's answer: passed; unsigned (errSecCSUnsigned), signature broken (errSecCSSignatureFailed) or someone
    /// else's (errSecCSReqFailed); anything else is no answer.
    static func signer(status: OSStatus) -> Signer {
        switch status {
        case errSecSuccess: return .apple
        case errSecCSUnsigned, errSecCSSignatureFailed, errSecCSReqFailed: return .other
        default: return .unknown
        }
    }

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
                    return LaunchItem(label: label, plist: path, program: prog, signer: signer(prog))
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

    /// What every finding's evidence ends with; the verdict's "probably" is the brief disclaimer (the terms of use say
    /// the rest).
    static let trick = "Malware often does this."

    /// The card for a finding, in place of the usual one: who it is comes before what it's doing (research rules,
    /// "Order of evaluation"). What Cool Head thinks, the disclaimer, then its advice, which is the recommended option,
    /// done in one click where Cool Head can, rather than stopping it and then deleting it as a separate task. An
    /// option marked Caution says why in its own description.
    public static func card(_ f: Finding, _ e: Evidence) -> Card {
        let reveal = { (path: String, steps: String, rec: Bool) in
            Fix(id: "delete", title: "Delete it", consequence: "This shows it in Finder, so you can drag it to the Trash. macOS asks for your password.",
                kind: .reveal(path, steps), recommended: rec).fixingTheCause()
        }
        switch f {
        case .macOSName(let name, let path):
            let fix = e.mine
                ? Fix(id: "remove", title: "Stop and delete it",
                      consequence: "This stops it and moves it to the Trash. If it is something you use, it stops working until you put it back from the Trash.",
                      kind: .stopAndTrash([path], nil), recommended: true)
                : reveal(path, "Drag it to the Trash, then empty the Trash.", true)
            return Card(state: .unknown, CardTemplate(name, .words("pretends to be a part of macOS"), .probablyHarmful,
                                                      evidence: ["It uses a name from macOS, but it runs from \(place(path)) without Apple's signature. \(trick)"]),
                        fixes: [fix, Card.share])
        case .unchecked(let name):
            return Card(state: .working, CardTemplate(name, .words("is probably a part of macOS"), nil,
                                                      evidence: ["macOS did not say where its program is, so Cool Head cannot check it."],
                                                      effect: ["You do not need to do anything unless it stays busy for hours."]),
                        fixes: [Card.share])
        case .notAppleSigned(let name, _):
            let steps = ["Shut down your Mac.", "Press and hold the power button until the startup options appear, then choose Options to start in Recovery.",
                         "Choose \(Fmt.path("Utilities", "Terminal")), type \(Fmt.ui("csrutil enable")), and press Return."]
                + (protection.sealBroken || !path(isOnDataVolume: f) ? ["Type \(Fmt.ui("csrutil authenticated-root enable")), and press Return."] : [])
                + ["Restart."]
            return Card(state: .unknown, CardTemplate("This copy of \(name)", .words("is not Apple's"), .probablyHarmful,
                                                      evidence: ["macOS protection is off on this Mac, and this program in the macOS folders was changed."]),
                        fixes: [Fix.guide("protect", "Turn on macOS protection", "This shows how. It stops anything from changing macOS programs, and it needs a restart into Recovery.",
                                          steps: steps, recommended: true),
                                Fix.guide("reinstall", "Reinstall macOS", "This puts back Apple's own programs. Your files and apps stay, but it takes a long time.",
                                          steps: ["Start in Recovery: shut down, then press and hold the power button until the startup options appear, and choose Options.",
                                                  "Choose Reinstall macOS and follow the steps."]),
                                Card.share])
        case .appleLabel(let label, let plist, let program):
            let folder = (plist as NSString).deletingLastPathComponent
            let shown = folder == NSHomeDirectory() + "/Library/LaunchAgents" ? "your LaunchAgents folder" : folder
            let file = (program as NSString).lastPathComponent
            let fix: Fix
            if folder != "/Library/LaunchDaemons" && e.mine {
                // in your login session: turned off as another app's helper is (see BackgroundAgents), stopped, and moved
                // to the Trash with its item, in one click
                fix = Fix(id: "remove", title: "Turn off and delete it",
                          consequence: "This stops it, keeps it from starting again, and moves it to the Trash. If it is something you use, it stops working until you put it back.",
                          kind: .stopAndTrash([program, plist], plist), recommended: true)
            } else {
                // the system's own launch items need an administrator (see the padlock line in the research)
                fix = Fix.guide("loginitems", "Turn it off in Login Items", "This shows how. It needs an administrator password.",
                                steps: ["Open \(Fmt.path("System Settings", "General", "Login Items & Extensions")).",
                                        "Under \(Fmt.ui("Allow in the Background")), find the item for \(file) and turn it off.",
                                        "Enter an administrator password if asked."], recommended: true)
            }
            return Card(state: .unknown, CardTemplate("a background item", .words("pretends to be Apple's"), .probablyHarmful,
                                                      evidence: ["\(label) starts \(file) from \(shown) without Apple's signature. \(trick)"]),
                        fixes: [fix, Card.share])
        }
    }

    /// Never moved to the Trash: anything in macOS's folders or signed by Apple.
    public static func refusesTrash(_ paths: [String]) -> Bool {
        paths.contains { CaseReport.isMacOS($0) || signer($0) == .apple }
    }

    /// Moves each file that is there to the Trash (where it can be put back); the names of those macOS didn't let move.
    public static func moveToTrash(_ paths: [String], moved: ((URL) -> Void)? = nil) -> [String] {
        var failed: [String] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            var to: NSURL?
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &to); if let u = to as URL? { moved?(u) } }
            catch { failed.append((path as NSString).lastPathComponent) }
        }
        return failed
    }

    static func path(isOnDataVolume f: Finding) -> Bool {
        if case .notAppleSigned(_, let p) = f { return p.hasPrefix("/Library/Apple/") }
        return false
    }
}

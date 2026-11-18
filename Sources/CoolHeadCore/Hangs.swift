import AppKit
import Darwin
import Foundation

/// Processes that are stuck while using almost nothing, which the busy-process cards never see (Phil, 15 November
/// 2026: "are we also looking at smaller ones that hang? Mindful if they're locking up a tiny amount of resources, not
/// a huge deal, but also could have unforeseen consequences if the frozen process is a dependency for something
/// else"). Three kinds, each read without an administrator password or a permission prompt:
/// - **paused** by something other than Cool Head (state T in `ps`), such as a Terminal job suspended with Control-Z;
/// - **waiting on a disk or network** that hasn't answered (state U in `ps`) for minutes;
/// - **Not Responding** apps, as macOS marks them (what Activity Monitor and Force Quit show).
/// Each card says what started it and which of its own programs are waiting on it, where that can be seen.
public enum Hang {
    public enum Kind: String { case paused, diskWait, notResponding }

    /// How long each kind lasts before it gets a card (COOLHEAD_HANG_SECONDS sets all of them, for testing): a short
    /// wait on a busy disk, or a beachball for a few seconds, is normal.
    public static func threshold(_ k: Kind, suspendedInShell: Bool) -> TimeInterval {
        if let s = Double(ProcessInfo.processInfo.environment["COOLHEAD_HANG_SECONDS"] ?? "") { return s }
        switch k {
        case .paused: return suspendedInShell ? 30 * 60 : 5 * 60     // a job you suspended yourself is likely on purpose
        case .diskWait: return 2 * 60
        case .notResponding: return 60
        }
    }

    /// The kind of hang `ps` shows for a process, if any. A process a debugger is attached to (X) is skipped: a
    /// breakpoint pauses it on purpose.
    public static func kind(psState s: String) -> Kind? {
        if s.contains("X") { return nil }
        if s.hasPrefix("T") { return .paused }
        if s.hasPrefix("U") { return .diskWait }
        return nil
    }

    // MARK: - Not Responding

    private typealias PSNForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias Connection = @convention(c) () -> Int32
    private typealias IsUnresponsive = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    /// macOS keeps no public way to ask whether an app is Not Responding; this is the window server's own check, the one
    /// Activity Monitor and Force Quit use. Looked up when Cool Head starts, so a macOS that drops it only loses this
    /// one kind of card. Tested on macOS 26 (16 November 2026): a test app whose main thread slept was marked after
    /// about 25 seconds, with no prompt.
    private static let check: (PSNForPID, Int32, IsUnresponsive)? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let hi = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let psn = dlsym(hi, "GetProcessForPID"), let conn = dlsym(sky, "SLSMainConnectionID"),
              let unresponsive = dlsym(sky, "SLSEventIsAppUnresponsive") else { return nil }
        let main = unsafeBitCast(conn, to: Connection.self)()
        return (unsafeBitCast(psn, to: PSNForPID.self), main, unsafeBitCast(unresponsive, to: IsUnresponsive.self))
    }()

    /// True when this Mac can tell Cool Head which apps are Not Responding.
    public static var canCheckResponding: Bool { check != nil }

    /// The apps macOS marks Not Responding right now, by process number.
    public static func notResponding() -> Set<pid_t> {
        guard let (psnFor, conn, unresponsive) = check else { return [] }
        var out = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            var psn = ProcessSerialNumber()
            guard psnFor(app.processIdentifier, &psn) == 0 else { continue }
            if unresponsive(conn, &psn) { out.insert(app.processIdentifier) }
        }
        return out
    }

    // MARK: - What's waiting on it

    /// A sentence naming the programs it started that are still running, which may be waiting on it.
    public static func waitingWords(_ names: [String]) -> String? {
        let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !unique.isEmpty else { return nil }
        let shown = Fmt.list(Array(unique.prefix(3)) + (unique.count > 3 ? ["others"] : []))
        return names.count == 1 ? "It started \(shown), which may be waiting on it."
                                : "It started \(names.count) programs that may be waiting on it: \(shown)."
    }

    /// The other disks and network drives it has files open on ("Backup", "Shared"), by name: the likely thing it is
    /// waiting for. Read from the kernel's list of its open files, without touching the files themselves.
    public static func volumes(_ pid: pid_t) -> [String] {
        let names = Proc.openFiles(pid).compactMap { f -> String? in
            let parts = f.path.split(separator: "/")
            return parts.count >= 2 && parts[0] == "Volumes" ? String(parts[1]) : nil
        }
        return names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// True when its parent is a shell.
    public static func parentIsShell(_ e: Evidence) -> Bool {
        guard let p = e.ancestors.first else { return false }
        return ["zsh", "bash", "sh", "fish", "tcsh", "csh", "dash", "-zsh", "-bash"].contains(p.name)
    }

    /// The app whose terminal window it was suspended in (Terminal, iTerm, an editor's terminal), when its parent is a
    /// shell and it is attached to a terminal window: then a pause is most likely Control-Z, and `fg` there brings it
    /// back. nil otherwise.
    public static func terminalApp(_ e: Evidence, pid: pid_t) -> String? {
        guard parentIsShell(e), Proc.bsd(pid)?.hasTerminal == true else { return nil }
        return e.ancestors.lazy.compactMap { Evidence.bundle($0.path) }.first ?? "/System/Applications/Utilities/Terminal.app"
    }

    // MARK: - The card

    /// The card for a process stuck in one of the three ways, for `stuckFor` seconds. `waiting`: the names of
    /// programs it started that are still running. `volumes`: other disks it has files open on.
    /// `terminal`: the app it was suspended in (its bundle path), from `terminalApp`.
    public static func card(_ kind: Kind, _ e: Evidence, stuckFor: TimeInterval, waiting: [String] = [], volumes: [String] = [],
                            terminal: String? = nil, now: Date = Date()) -> Card {
        // the programs it started, named so they can be told apart from it (see Naming): a child shares its parent's
        // kind, run from the same terminal or in the background, so "ffmpeg" started by ffmpeg is "another ffmpeg"
        let who = Card.subject(e)
        let what: Naming.What = e.script != nil ? .script : e.appBundle != nil ? .app : Naming.what(path: e.path, hasTerminal: parentIsShell(e))
        // several copies of one program are one name, counted (waitingWords says "2 programs … ffmpeg")
        let unique = waiting.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let told = Naming.distinct([Naming.Named(who, what)] + unique.map { Naming.Named($0, what) })
        let rename = Dictionary(uniqueKeysWithValues: zip(unique, told.dropFirst()))
        var c = body(kind, e, stuckFor: stuckFor, who: told[0], waiting: waiting.map { rename[$0] ?? $0 }, volumes: volumes, terminal: terminal, now: now)
        c.names = told
        return c
    }

    static func body(_ kind: Kind, _ e: Evidence, stuckFor: TimeInterval, who: String, waiting: [String], volumes: [String],
                     terminal: String?, now: Date) -> Card {
        let long = Fmt.duration(stuckFor)
        let protected = SecuritySoftware.product(path: e.path, name: e.name) != nil
        let macOS = e.script == nil && (e.path.map(CaseReport.isMacOS) ?? true)
        let appMain = e.appBundle != nil && e.script == nil && e.browserPart == nil
            && (e.path?.contains(".app/Contents/MacOS/") ?? false)
        let waits = waitingWords(waiting).map { " " + $0 } ?? ""
        let started = appMain ? "" : " Started by \(e.startedBy)."
        let memory = e.memoryBytes >= 10_000_000 ? " (\(Fmt.bytes(e.memoryBytes)))" : ""
        let stop: Fix? = e.mine && !macOS && !appMain && !protected
            ? Fix(id: "stop", title: "Stop it", consequence: "It ends without finishing. Anything it hasn't saved is lost.", kind: .stop)
            : nil
        let forceQuit: Fix? = appMain && e.mine && !protected
            ? Fix(id: "forcequit", title: "Force quit \(who)", consequence: "Like Force Quit in the Apple menu. Anything unsaved in it is lost.", kind: .forceQuit)
            : nil

        switch kind {
        case .paused:
            if let bundle = terminal {
                let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
                return Card(state: .waiting, headline: "\(who) has been paused in \(app) for \(long).",
                            explanation: "It was suspended there, usually with Control-Z, and does nothing until it's brought back. "
                                + "It still holds its memory\(memory) and any files it has open." + waits,
                            fixes: [Fix.openApp("fg", "Bring it back", bundle: bundle, steps: "In the window it's in, type fg and press Return.", recommended: true).fixingTheCause(),
                                    stop].compactMap { $0 })
            }
            return Card(state: .unknown, headline: "\(who) has been paused for \(long), not by Cool Head.",
                        explanation: "Something stopped it, and it does nothing until it's resumed. It still holds its memory\(memory) and any files it has open."
                            + started + waits,
                        fixes: [e.mine ? Fix(id: "resume", title: "Resume it", consequence: "It carries on from where it stopped. If something paused it on purpose, it may pause it again.",
                                             kind: .resume, recommended: true) : nil,
                                stop, forceQuit, Card.lookUp(e.name, recommended: !e.mine), Card.share].compactMap { $0 })

        case .diskWait:
            let drive = volumes.first
            let target = drive ?? "a disk or network drive"
            return Card(state: .unknown, headline: "\(who) has been stuck waiting on \(target) for \(long).",
                        explanation: "It asked \(drive == nil ? "it" : "that drive") for something and is still waiting for the answer. "
                            + "It's usually a network drive that dropped, an external disk, or a disk that's very busy. It can't be stopped or quit until the answer comes."
                            + started + waits,
                        fixes: [Fix.guide("drive", drive.map { "Reconnect \($0)" } ?? "Reconnect your drives", "Reconnect the network drive or plug the disk back in. Once it answers, the stuck process carries on by itself.",
                                          steps: ["For a network drive: in Finder, choose \(Fmt.path("Go", "Connect to Server")), and connect to it again.",
                                                  "For a disk: check its cable, or plug it back in."],
                                          recommended: true).fixingTheCause(),
                                Fix.guide("restart", "Restart if it won't clear", "If it's still stuck once the drive is back, restarting your Mac frees it. Nothing else can end a process stuck on a drive.",
                                          steps: ["Save your work in other apps.", "Choose \(Fmt.path("Apple menu", "Restart"))."]).fixingTheCause(),
                                Card.lookUp(e.name, recommended: false), Card.share])

        case .notResponding:
            let busy = e.coresNow >= 0.5
            let settled = stuckFor >= 5 * 60 && !busy
            let why = busy ? " It's busy, using about \(Fmt.cores(e.coresNow)), so it may be working through something big and recover."
                           : " It's using almost no power, so it's probably waiting on something: a network drive, a stuck helper, or another app."
            return Card(state: .unknown, headline: "\(who) isn't responding.",
                        explanation: "macOS marked it Not Responding \(long) ago: it has stopped answering clicks and keys." + why + waits
                            + (settled ? "" : " Apps often recover once a long task finishes. To wait, use the clock in this card's corner."),
                        fixes: [forceQuit.map { var f = $0; f.recommended = settled; return f },
                                Card.lookUp(e.name, recommended: false), Card.share].compactMap { $0 })
        }
    }

    /// A few words for a report and the activity log, after the process's anonymised name.
    public static func words(_ k: Kind) -> String {
        switch k {
        case .paused: return "paused, not by Cool Head"
        case .diskWait: return "stuck waiting on a disk or network"
        case .notResponding: return "not responding"
        }
    }
}

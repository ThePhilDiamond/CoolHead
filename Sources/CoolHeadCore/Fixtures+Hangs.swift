import Darwin
import Foundation

/// Checks for hangs (see Hangs.swift).
extension Fixture {
    /// An example process with one parent: a shell (started from a terminal) or launchd (started by macOS).
    static func withParent(_ e: Evidence, _ parent: String) -> Evidence {
        Evidence(pid: e.pid, name: e.name, path: e.path, args: e.args, cwd: e.cwd, start: e.start, mine: e.mine, coresNow: e.coresNow,
                 coresAverage: e.coresAverage, performanceShare: nil, memoryBytes: e.memoryBytes,
                 ancestors: [.init(pid: parent == "launchd" ? 1 : 500, name: parent, path: parent == "launchd" ? "/sbin/launchd" : "/bin/\(parent)", args: [parent])],
                 writing: [], locks: [], progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil,
                 savesAsItGoes: false, workStart: e.start)
    }

    /// Hangs that use almost nothing: paused by something else, stuck waiting on a drive, and Not Responding apps.
    static func hangsChecks(_ now: Date) -> [(String, Bool, String)] {
        var out: [(String, Bool, String)] = []
        func ids(_ c: Card) -> [String] { c.fixes.map(\.id) }
        func with(_ e: Evidence, parent: String) -> Evidence {
            Evidence(pid: e.pid, name: e.name, path: e.path, args: e.args, cwd: e.cwd, start: e.start, mine: e.mine, coresNow: e.coresNow,
                     coresAverage: e.coresAverage, performanceShare: nil, memoryBytes: e.memoryBytes,
                     ancestors: [.init(pid: parent == "launchd" ? 1 : 500, name: parent, path: parent == "launchd" ? "/sbin/launchd" : "/bin/\(parent)", args: [parent])],
                     writing: [], locks: [], progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil,
                     savesAsItGoes: false, workStart: e.start)
        }
        // ps's state letters: T paused, U waiting on a drive; a debugger's pause (X) and sleeping (S) aren't hangs
        let ps = Proc.parsePS("  123   0.0 T\n  124   0.0 TX\n  125   0.0 U\n  126   1.0 S+\n  127   0,0 U+\n")
        let kinds = [123, 124, 125, 126, 127].map { ps[pid_t($0)].flatMap { Hang.kind(psState: $0.state) } }
        out.append(("hang-kinds-from-ps", kinds == [.paused, nil, .diskWait, nil, .diskWait], "\(kinds.map { $0?.rawValue ?? "none" })"))

        let job = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                  start: now.addingTimeInterval(-7200), cores: 0)
        let inShell = Hang.card(.paused, with(job, parent: "zsh"), stuckFor: 3600, terminal: "Terminal", now: now)
        out.append(("hang-paused-in-terminal", inShell.state == .waiting && inShell.recommended?.title == "Bring it back"
                        && !inShell.fixes.contains { $0.kind == .resume } && inShell.explanation.contains("Control-Z"),
                    inShell.headline))
        let other = Hang.card(.paused, with(job, parent: "launchd"), stuckFor: 600, waiting: ["ffmpeg", "ffmpeg"], now: now)
        out.append(("hang-paused-by-something-else", other.state == .unknown && other.recommended?.title == "Resume it"
                        && ids(other).contains("stop") && ids(other).contains("share") && other.explanation.contains("started 2 programs that may be waiting on it: ffmpeg."),
                    other.headline + " " + other.explanation))
        let drive = Hang.card(.diskWait, with(job, parent: "launchd"), stuckFor: 300, volumes: ["Backup"], now: now)
        out.append(("hang-waiting-on-a-drive", drive.headline.contains("Backup") && drive.recommended?.title == "Reconnect Backup"
                        && !drive.fixes.contains { $0.kind == .stop || $0.kind == .forceQuit },
                    drive.headline))
        let app = Evidence.sample(name: "Foo", path: "/Applications/Foo.app/Contents/MacOS/Foo", start: now.addingTimeInterval(-7200), cores: 0)
        let busyApp = Evidence.sample(name: "Foo", path: "/Applications/Foo.app/Contents/MacOS/Foo", start: now.addingTimeInterval(-7200), cores: 2)
        let fresh = Hang.card(.notResponding, app, stuckFor: 120, now: now)
        let settled = Hang.card(.notResponding, app, stuckFor: 600, now: now)
        let working = Hang.card(.notResponding, busyApp, stuckFor: 600, now: now)
        let ok = fresh.recommended == nil && ids(fresh).contains("forcequit") && settled.recommended?.title == "Force quit Foo"
            && working.recommended == nil && !ids(fresh).contains("stop") && fresh.explanation.contains("clock in this card's corner")
        out.append(("hang-not-responding", ok,
                    "2 minutes: \(fresh.recommended?.title ?? "nothing recommended yet"); 10 minutes idle: \(settled.recommended?.title ?? "none"); 10 minutes busy: \(working.recommended?.title ?? "none")"))
        out.append(("not-responding-check-available", Hang.canCheckResponding, Hang.canCheckResponding ? "macOS answers which apps are Not Responding" : "macOS's check wasn't found"))
        // for real: a child process paused by something other than Cool Head is found, and Resume lets it carry on
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["20"]
        if (try? sleeper.run()) != nil {
            let pid = sleeper.processIdentifier
            usleep(200_000)
            kill(pid, SIGSTOP)
            usleep(100_000)
            let found = Proc.psTable()[pid].flatMap { Hang.kind(psState: $0.state) } == .paused
            let lc = LiveCard(id: "hang-paused-\(pid)", pid: pid, start: Proc.bsd(pid)?.start, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: [])
            let resumed = { if case .done = Watcher().resumeStopped(lc) { return true }; return false }() && Proc.bsd(pid)?.stopped == false
            sleeper.terminate()
            out.append(("hang-paused-really-found-and-resumed", found && resumed, "found \(found), resumed \(resumed)"))
        }
        // Stop on a paused process (it must carry on to act on the signal), and Force quit, each on a child of our own
        func child() -> (Process, LiveCard)? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sleep")
            p.arguments = ["20"]
            guard (try? p.run()) != nil else { return nil }
            usleep(200_000)
            let pid = p.processIdentifier
            return (p, LiveCard(id: "hang-\(pid)", pid: pid, start: Proc.bsd(pid)?.start, card: Card(state: .unknown, headline: "", explanation: "", fixes: []), details: []))
        }
        if let (a, ca) = child(), let (b, cb) = child() {
            kill(a.processIdentifier, SIGSTOP)
            usleep(100_000)
            let w = Watcher()
            _ = w.stop(ca); _ = w.forceQuit(cb)
            for _ in 0..<20 where a.isRunning || b.isRunning { usleep(50_000) }
            out.append(("hang-stop-and-force-quit-really-work", !a.isRunning && !b.isRunning,
                        "paused process stopped \(!a.isRunning), force quit \(!b.isRunning)"))
            if a.isRunning { kill(a.processIdentifier, SIGKILL) }
            if b.isRunning { b.terminate() }
        }
        return out
    }


    /// No sample cards of its own for `coolhead wording`.
    static func hangsSamples(_ now: Date) -> [(String, Card)] { [] }
}

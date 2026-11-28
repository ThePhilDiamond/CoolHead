import Darwin
import Foundation

/// The processes the selftest starts for its checks (sleepers, busy loops, its restart test app). Each check ends what
/// it starts on every path, whether it passes, fails or gives up; and a process that would otherwise run on by itself
/// (a busy loop, the test app) also ends itself once the selftest has gone, so a selftest stopped part way (Control-C,
/// a time limit) leaves nothing running either (26 November 2026: the restart test app from a run on 17 November was
/// still running).
extension Fixture {
    /// Ends a child process of the selftest: asks with SIGTERM (macOS ends a paused process on it too), and if it is
    /// still there after 3 seconds, ends it with SIGKILL, which it can't ignore. Waits at most 5 seconds in all (never
    /// for good, as `waitUntilExit` could); true if it has gone.
    @discardableResult
    static func end(_ p: Process) -> Bool {
        func gone(within seconds: Double) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while p.isRunning && Date() < deadline { usleep(20_000) }
            return !p.isRunning
        }
        if p.isRunning { p.terminate() }
        if gone(within: 3) { return true }
        kill(p.processIdentifier, SIGKILL)
        return gone(within: 2)
    }

    /// A shell loop that keeps one core busy until it is ended, or until `owner` (this selftest, unless a check says
    /// otherwise) has gone. With `background`, started at background priority by taskpolicy -b, which runs the loop in
    /// its own place (the same process).
    static func busyLoop(background: Bool = false, owner: pid_t = getpid()) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: background ? "/usr/sbin/taskpolicy" : "/bin/sh")
        p.arguments = (background ? ["-b", "/bin/sh"] : []) + ["-c", "exec 2>/dev/null; while kill -0 \(owner); do :; done"]
        return (try? p.run()) != nil ? p : nil
    }

    /// The path with every link followed, as the kernel reports a process's program (/private/var for /var).
    static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    /// Every process running the program at `program` (a real path), from the kernel's own list: unlike macOS's list of
    /// running apps, it has a process as soon as it runs that program, and until it ends.
    static func processes(running program: String) -> [pid_t] {
        Proc.allPIDs().filter { Proc.path($0) == program }
    }

    /// Ends every process running the program at `program`, and waits up to 5 seconds for them to go; true if none is
    /// left. SIGKILL, which an app can't decline, as it can a request to quit.
    @discardableResult
    static func endAll(running program: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while true {
            let left = processes(running: program)
            if left.isEmpty { return true }
            if Date() > deadline { return false }
            left.forEach { kill($0, SIGKILL) }
            usleep(50_000)
        }
    }

    static func testProcessesChecks(_ now: Date) -> [(String, Bool, String)] {
        func sleeper() -> Process? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sleep")
            p.arguments = ["20"]
            return (try? p.run()) != nil ? p : nil
        }
        func until(_ seconds: Double, _ ok: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while !ok() { if Date() > end { return false }; usleep(20_000) }
            return true
        }
        var out: [(String, Bool, String)] = []
        // a child that ignores SIGTERM is ended all the same
        let stubborn = Process()
        stubborn.executableURL = URL(fileURLWithPath: "/bin/sh")
        stubborn.arguments = ["-c", "trap '' TERM; while :; do sleep 1; done"]
        if (try? stubborn.run()) != nil {
            let pid = stubborn.processIdentifier
            usleep(300_000)
            let ended = end(stubborn)
            out.append(("test-process-ended-even-ignoring-sigterm", ended && Proc.bsd(pid) == nil, "ended \(ended)"))
        } else { out.append(("test-process-ended-even-ignoring-sigterm", false, "could not start /bin/sh")) }
        // a busy loop ends by itself once what it belongs to has gone, as when the selftest is stopped part way: here
        // it belongs to a sleeper, which is ended
        let owner = sleeper(), loop = owner.flatMap { busyLoop(owner: $0.processIdentifier) }
        if let owner, let loop {
            let busy = until(2) { (Proc.usage(loop.processIdentifier)?.cpuSeconds ?? 0) > 0.1 }
            end(owner)
            let gone = until(3) { !loop.isRunning }
            out.append(("busy-loop-ends-with-the-selftest", busy && gone, "busy \(busy); ended by itself once its owner had gone \(gone)"))
        } else { out.append(("busy-loop-ends-with-the-selftest", false, "could not start /bin/sleep or the loop")) }
        [owner, loop].compactMap { $0 }.forEach { end($0) }
        return out
    }

    /// No sample cards of its own for `coolhead wording`.
    static func testProcessesSamples(_ now: Date) -> [(String, Card)] { [] }
}

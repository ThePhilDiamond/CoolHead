import AppKit
import Foundation

/// Restart a Chromium browser, keeping its tabs: a normal quit (so it can ask about downloads), a wait for it to
/// close, then a reopen with Chromium's `--restore-last-session` switch, which brings back the last session's windows
/// and tabs whatever the browser's "On startup" setting says. Chrome slowly builds up memory; a restart frees it.
///
/// Incognito (private) windows, text typed into forms and not sent, and downloads in progress don't come back: the
/// option on the memory card says so before it's pressed. If the browser hasn't closed within the wait (it may be
/// asking something, such as whether to cancel a download), it is not reopened.
public enum BrowserRestart {
    /// Chromium browsers whose own launch switches include `--restore-last-session`. Not Arc (it keeps its own tabs
    /// and windows its own way), Opera (Chromium underneath, but its startup handling is its own and untested), Safari
    /// or Firefox (not Chromium).
    public static let browsers = ["Google Chrome", "Microsoft Edge", "Brave Browser", "Vivaldi", "Chromium"]
    public static let argument = "--restore-last-session"
    public static let wait: TimeInterval = 20

    /// What each browser calls its private windows, for the option's consequence.
    public static func privateWindows(_ name: String) -> String {
        switch name {
        case "Microsoft Edge": return "InPrivate windows"
        case "Brave Browser", "Vivaldi": return "private windows"
        default: return "Incognito windows"
        }
    }

    public enum Outcome: Equatable {
        case restarted(seconds: Int)      // closed after this long, and reopened
        case notRunning
        case refused                      // the quit request couldn't be sent
        case stillOpen                    // asked to quit, but still open after the wait: not reopened
        case reopenFailed(String)         // closed, but didn't reopen
    }

    /// Quits the app at `bundle` (every copy of it running from that path), waits up to `wait` seconds for it to close,
    /// then reopens it with `--restore-last-session`. Blocks the calling thread: call it off the main thread (see
    /// `restart`). `log` gets each step in words that name nothing private.
    /// `arguments`: what it is reopened with; none for an app that isn't a Chromium browser (see Leaks).
    public static func restartBlocking(bundle: String, wait: TimeInterval = wait, activate: Bool = true, arguments: [String] = [argument],
                                       log: (String) -> Void = { _ in }) -> Outcome {
        let url = URL(fileURLWithPath: bundle)
        // found by where the app is installed, not by its display name (which can differ, or be shared)
        let id = Bundle(url: url)?.bundleIdentifier
        let running = (id.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } ?? NSWorkspace.shared.runningApplications)
            .filter { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path }
            // and only if its process still exists: seen from a background thread, macOS's list of running apps can
            // still hold an app that has just quit (GitHub's build machine, 15 November 2026)
            .filter { !$0.isTerminated && Proc.bsd($0.processIdentifier) != nil }
        guard !running.isEmpty else { log("not running"); return .notRunning }
        // each process by number and start time, so a reused number isn't mistaken for the browser still open
        let watched = running.map { ($0.processIdentifier, Proc.bsd($0.processIdentifier)?.start) }
        guard running.map({ $0.terminate() }).contains(true) else { log("the quit request couldn't be sent"); return .refused }
        log("asked it to quit")
        let started = Date()
        func open(_ pid: pid_t, _ start: Date?) -> Bool {
            guard let b = Proc.bsd(pid) else { return false }
            return start.map { abs(b.start.timeIntervalSince($0)) < 1 } ?? true
        }
        while watched.contains(where: open) {
            if Date().timeIntervalSince(started) > wait {
                log("still open after \(Int(wait)) seconds, so not reopened")
                return .stillOpen
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let took = Int(Date().timeIntervalSince(started).rounded())
        log("closed after \(took) seconds")
        Thread.sleep(forTimeInterval: 1)        // let its helper processes finish closing too
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = activate
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            result.error = error.map { $0.localizedDescription } ?? (app == nil ? "macOS didn't open it" : nil)
            done.signal()
        }
        if done.wait(timeout: .now() + 15) == .timedOut { result.error = "macOS didn't open it within 15 seconds" }
        if let e = result.error { log("didn't reopen"); return .reopenFailed(e) }
        log(arguments.isEmpty ? "reopened" : "reopened with its last session")
        return .restarted(seconds: took)
    }

    /// The same, without blocking the caller: the work runs on a background thread.
    public static func restart(bundle: String, wait: TimeInterval = wait, activate: Bool = true, arguments: [String] = [argument],
                               log: @escaping (String) -> Void) async -> Outcome {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                c.resume(returning: restartBlocking(bundle: bundle, wait: wait, activate: activate, arguments: arguments, log: log))
            }
        }
    }

    private final class Box: @unchecked Sendable { var error: String? }

    /// What the panel says afterward, in a sentence or two.
    public static func note(_ o: Outcome, name: String) -> (text: String, failed: Bool) {
        switch o {
        case .restarted:
            return ("Restarted \(name). Your tabs are coming back.", false)
        case .notRunning:
            return ("It's already closed.", false)
        case .refused:
            return ("\(name) didn't quit. It may be asking you something.", true)
        case .stillOpen:
            return ("\(name) is still open after \(Int(wait)) seconds, so it wasn't reopened. It may be asking you something, such as about a download. If it closes later, open it again: it may offer to restore your tabs, or look in History ▸ Recently Closed.", true)
        case .reopenFailed(let why):
            return ("\(name) closed but didn't reopen: \(why). Open it again: it may offer to restore your tabs, or look in History ▸ Recently Closed.", true)
        }
    }

    // MARK: - The selftest's own app

    /// The start of the bundle identifier of the throwaway app the selftest builds from a copy of the `coolhead`
    /// program; each run adds its own process number, as `testAppID(run:)` does. Launched with such an identifier,
    /// `coolhead` runs as that app instead (see main.swift).
    public static let testAppID = "io.github.thephildiamond.coolhead.selftest-restart"

    /// Each selftest run's app has an identifier of its own. macOS treats two apps with one identifier as the same app:
    /// asked to open a second copy while the first is running, it brings the first forward and opens nothing, and a
    /// selftest running at the same time would then see no launch of its own (16 November 2026).
    public static func testAppID(run: Int32) -> String { "\(testAppID).run\(run)" }

    /// Whether `id` is the bundle identifier of a selftest run's app.
    public static func isTestApp(_ id: String?) -> Bool { id?.hasPrefix(testAppID + ".run") ?? false }

    /// Run as the selftest's app: records its launch arguments, one launch per line, in `launches.txt` beside its
    /// bundle, then waits like any app until asked to quit. While `refuse-quit` exists beside its bundle, it declines
    /// to quit, as a browser asking about a download would. Never returns.
    public static func runTestApp() -> Never {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
        let line = CommandLine.arguments.dropFirst().joined(separator: " ") + "\n"
        let file = folder.appendingPathComponent("launches.txt")
        if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: file, atomically: true, encoding: .utf8) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = TestAppDelegate(refuse: folder.appendingPathComponent("refuse-quit").path)
        app.delegate = delegate
        app.run()
        _ = delegate
        exit(0)
    }

    private final class TestAppDelegate: NSObject, NSApplicationDelegate {
        let refuse: String
        init(refuse: String) { self.refuse = refuse }
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            FileManager.default.fileExists(atPath: refuse) ? .terminateCancel : .terminateNow
        }
    }

    /// Builds the selftest's app in `folder`, with identifier `id`: a bundle whose program is a copy of this one.
    /// Returns its path.
    public static func makeTestApp(in folder: URL, program: String, id: String) throws -> String {
        let fm = FileManager.default
        let app = folder.appendingPathComponent("Restart Test.app")
        try? fm.removeItem(at: app)
        try? fm.removeItem(at: folder.appendingPathComponent("launches.txt"))
        try? fm.removeItem(at: folder.appendingPathComponent("refuse-quit"))
        let macos = app.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: program), to: macos.appendingPathComponent("restarttest"))
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "restarttest", "CFBundleName": "Restart Test",
                                    "CFBundlePackageType": "APPL", "LSUIElement": true, "LSMinimumSystemVersion": "14.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app.path
    }
}

import AppKit
import Foundation

/// Checks for Restart Chrome, keeping your tabs (see BrowserRestart.swift).
extension Fixture {
    /// Restarting for real, on a throwaway app of our own (never a browser): a copy of this program in its own bundle,
    /// which writes down how it was opened. It quits when asked, comes back with --restore-last-session, and isn't
    /// reopened when it declines to quit. COOLHEAD_SELFTEST_DIR says where to build it (a temporary folder otherwise);
    /// each run builds its own copy, with an identifier and a folder of its own, so selftests run at the same time (one
    /// per pull request being worked on) never open, quit, rebuild or unblock each other's app. Runs only from the
    /// coolhead command-line program.
    static func browserRestartChecks(_ now: Date) -> [(String, Bool, String)] {
        guard let program = Bundle.main.executablePath, (program as NSString).lastPathComponent == "coolhead" else { return [] }
        return [restartTest(program: program)]
    }

    /// Waits for `work` on a background thread while the main run loop keeps turning (macOS may answer on it).
    static func offMain<T>(_ work: @escaping () -> T) -> T {
        let slot = Slot()
        DispatchQueue.global().async { let v = work(); DispatchQueue.main.async { slot.value = v } }
        while slot.value == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return slot.value as! T
    }

    private final class Slot: @unchecked Sendable { var value: Any? }

    static func restartTest(program: String) -> (String, Bool, String) {
        let env = ProcessInfo.processInfo.environment["COOLHEAD_SELFTEST_DIR"]
        let base = URL(fileURLWithPath: env ?? NSTemporaryDirectory() + "coolhead-selftest-restart", isDirectory: true)
        // this run's own folder and identifier: a run that shared them would rebuild the app, erase launches.txt and
        // refuse-quit, and quit the app under the other (16 November 2026: 3 of 6 failed with two at once, "declining
        // to quit" finding it restarted)
        let folder = base.appendingPathComponent("run-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let launches = folder.appendingPathComponent("launches.txt"), refuse = folder.appendingPathComponent("refuse-quit")
        func lines() -> [String] { ((try? String(contentsOf: launches, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) }
        func until(_ seconds: Double, _ ok: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while !ok() { if Date() > end { return false }; RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            return true
        }
        let id = BrowserRestart.testAppID(run: getpid())
        guard let app = try? BrowserRestart.makeTestApp(in: folder, program: program, id: id) else { return ("restart-browser-really-works", false, "couldn't build the test app") }
        let url = URL(fileURLWithPath: app)
        func running() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path }
        }
        // first open, as a person would: no arguments
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        let opened = until(10) { lines().count == 1 } && until(5) { !running().isEmpty }
        let firstPID = running().first?.processIdentifier
        var steps: [String] = []
        let restarted = offMain { BrowserRestart.restartBlocking(bundle: app, wait: 10, activate: false) { steps.append($0) } }
        let back = until(10) { lines().count == 2 } && until(5) { running().contains { $0.processIdentifier != firstPID } }
        let l = lines()
        let args = l.count == 2 && !l[0].contains(BrowserRestart.argument) && l[1] == BrowserRestart.argument
        let oldGone = firstPID.map { Proc.bsd($0) == nil } ?? false
        // while it declines to quit (as a browser asking about a download would), it is left open and not reopened.
        // First wait until the reopened copy is visible from a background thread, where restartBlocking looks: right
        // after opening, it can be seen from the main thread a moment before (GitHub's build machine, 15 November 2026:
        // this step once found it "not running").
        func visibleOffMain() -> Bool {
            offMain { NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .contains { $0.bundleURL?.standardizedFileURL.path == url.standardizedFileURL.path } }
        }
        _ = until(10) { visibleOffMain() }
        FileManager.default.createFile(atPath: refuse.path, contents: nil)
        let declined = offMain { BrowserRestart.restartBlocking(bundle: app, wait: 3, activate: false) }
        let leftAlone = declined == .stillOpen && lines().count == 2 && !running().isEmpty
        // quit and reopen with no arguments, as for a leaking app that isn't a browser (see Leaks)
        try? FileManager.default.removeItem(at: refuse)
        _ = until(10) { visibleOffMain() }
        let plain = offMain { BrowserRestart.restartBlocking(bundle: app, wait: 10, activate: false, arguments: []) }
        let plainBack = until(10) { lines().count == 3 } && lines().last == ""
        // tidy up: let it quit, and check there is then nothing to restart
        running().forEach { $0.terminate() }
        let quit = until(10) { running().allSatisfy { Proc.bsd($0.processIdentifier) == nil } }
        if !quit { running().forEach { $0.forceTerminate() } }
        let none = offMain { BrowserRestart.restartBlocking(bundle: app, wait: 3, activate: false) } == .notRunning
        let ok = opened && { if case .restarted = restarted { return true }; return false }() && back && args && oldGone && leftAlone && quit && none
            && { if case .restarted = plain { return plainBack }; return false }()
        return ("restart-browser-really-works", ok,
                "opened \(opened); \(restarted) (\(steps.joined(separator: ", "))); reopened \(back) with \(l.last ?? "nothing"); old copy gone \(oldGone); declining to quit: \(declined), not reopened \(leftAlone); quit and reopened plain \(plain), with no arguments \(plainBack); tidied \(quit) \(none)")
    }

}

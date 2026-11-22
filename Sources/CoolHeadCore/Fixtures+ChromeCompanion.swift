import Foundation
import CoolHeadChromeLink

/// Checks for Chrome's card with Cool Head for Chrome (see ChromeCompanion): one click when it's connected, offered when
/// it isn't and memory keeps slowing the Mac.
extension Fixture {
    static func companionCard(_ now: Date, _ status: ChromeCompanion.Status, weekCount: Int = 3) -> Card {
        MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                          context: MemoryContext(slowed: true, week: PressureHistory.Week(count: weekCount, minutes: 40, chromeCount: 2),
                                                 chrome: chromeParts(now, extGB: 1.6), companion: status), tabMemoryOn: false)
    }

    static func chromeCompanionChecks(_ now: Date) -> [(String, Bool, String)] {
        let on = companionCard(now, .connected)
        let ids = on.fixes.map(\.id)
        let offered = companionCard(now, .notInstalled).fixes.contains { $0.id == "companion" }
        let notYet = !companionCard(now, .notInstalled, weekCount: 1).fixes.contains { $0.id == "companion" }
        let noChrome = !companionCard(now, .noChrome).fixes.contains { $0.id == "companion" }
        // Cool Head's end of the link, the real helper, and Chrome played through pipes: the helper says Cool Head is
        // running; Chrome's hello makes Cool Head linked; Cool Head's reading reaches Chrome; a card's request reaches
        // Chrome and its answer comes back; and when Chrome goes, Cool Head is no longer linked
        var link = (ran: false, linked: false, state: false, request: false, answered: false, unlinked: false)
        if let host = Fixture.chromeHostPath() {
            let dir = NSTemporaryDirectory() + "chs-\(getpid())"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let sock = dir + "/s.sock"
            let server = ChromeLinkServer()
            if server.start(path: sock), let run = Fixture.HostRun(host, socket: sock) {
                link.ran = run.receive().flatMap { ChromeLink.decode(ChromeLink.Link.self, from: $0) }?.app == .running
                _ = run.receive()       // Cool Head's hello, relayed
                _ = run.send(ChromeLink.frame(ChromeLink.encode(ChromeLink.ExtensionHello(extension: "1.0.0", browser: "chrome", level: .auto)))!)
                let until = Date().addingTimeInterval(3)
                while !server.summary.connected && Date() < until { usleep(20_000) }
                link.linked = server.summary.connected
                server.publish(ChromeLink.State(memory: .slowed, freeMB: 900, chromeMB: 5200, hiddenTabsMB: 2100, extensionsMB: 1600, auto: true))
                link.state = run.receive().flatMap { ChromeLink.decode(ChromeLink.State.self, from: $0) }?.memory == .slowed
                let answer = ResultBox()
                server.request(.sleepHidden) { answer.set($0) }
                if let m = run.receive(), let r = ChromeLink.decode(ChromeLink.Request.self, from: m) {
                    link.request = r.action == .sleepHidden
                    _ = run.send(ChromeLink.frame(ChromeLink.encode(ChromeLink.ActionResult(id: r.id, ok: true, done: "Put 23 tabs to sleep.", count: 23)))!)
                }
                let until2 = Date().addingTimeInterval(3)
                while answer.get() == nil && Date() < until2 { usleep(20_000) }
                link.answered = answer.get()?.done == "Put 23 tabs to sleep."
                _ = run.finish()
                let until3 = Date().addingTimeInterval(3)
                while server.summary.connected && Date() < until3 { usleep(20_000) }
                link.unlinked = !server.summary.connected
            }
            server.stop()
            try? FileManager.default.removeItem(atPath: dir)
        }
        // Set up writes Chrome's file naming this copy's helper, in the folder given (never Chrome's own, here)
        let hosts = NSTemporaryDirectory() + "chm-\(getpid())"
        let fakeHelper = hosts + "-helper"
        FileManager.default.createFile(atPath: fakeHelper, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let wrote = ChromeCompanion.installHostFile(folder: hosts, helper: fakeHelper) && ChromeCompanion.hostFileInstalled(folder: hosts, helper: fakeHelper)
            && !ChromeCompanion.hostFileInstalled(folder: hosts, helper: "/elsewhere/coolhead-chrome-host")
        try? FileManager.default.removeItem(atPath: hosts); try? FileManager.default.removeItem(atPath: fakeHelper)
        let memoryWords = [ChromeLinkServer.memory(mac("normal", swappedMB: nil), slowed: false), ChromeLinkServer.memory(mac("warning", swappedMB: 30), slowed: false),
                           ChromeLinkServer.memory(mac("warning", swappedMB: 600), slowed: true), ChromeLinkServer.memory(mac("critical", swappedMB: 600), slowed: true)]
        return [("chrome-link-end-to-end", link.ran && link.linked && link.state && link.request && link.answered && link.unlinked, "\(link)"),
                ("chrome-link-setup-file", wrote, "written and recognized \(wrote)"),
                ("chrome-link-memory-words", memoryWords == [.fine, .tight, .slowed, .veryTight], "\(memoryWords)"),
                ("companion-one-click", on.recommended?.id == "sleep" && on.recommended?.consequence.hasPrefix("Frees about 2.1 GB.") == true
                 && !ids.contains("tabs") && ids.contains("duplicates") && on.fixes.first { $0.id == "extensions" }.map { if case .chromeCompanion = $0.kind { return true } else { return false } } == true
                 && offered && notYet && noChrome, ids.joined(separator: " ") + "; offered \(offered), not after once \(notYet), not without Chrome \(noChrome)")]
    }

    static func chromeCompanionSamples(_ now: Date) -> [(String, Card)] {
        [("memory-chrome-companion", companionCard(now, .connected)), ("memory-chrome-get-companion", companionCard(now, .notInstalled))]
    }
}

/// The answer to a request, from the link's own queue.
final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ChromeLink.ActionResult?
    func set(_ r: ChromeLink.ActionResult?) { lock.withLock { value = r } }
    func get() -> ChromeLink.ActionResult? { lock.withLock { value } }
}

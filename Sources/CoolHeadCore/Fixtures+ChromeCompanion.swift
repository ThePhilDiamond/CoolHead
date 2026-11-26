import Foundation
import CoolHeadChromeLink

/// Checks for Chrome's card with Cool Head for Chrome (see ChromeCompanion): one click when it's connected, offered when
/// it isn't and memory keeps slowing the Mac.
extension Fixture {
    static func companionCard(_ now: Date, _ status: ChromeCompanion.Status, weekCount: Int = 3, toSleep: Int = 12) -> Card {
        MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now,
                          context: { var c = MemoryContext(slowed: true, week: PressureHistory.Week(count: weekCount, minutes: 40, chromeCount: 2),
                                                 chrome: chromeParts(now, extGB: 1.6), companion: status); c.tabsToSleep = status == .connected ? toSleep : nil; return c }(), tabMemoryOn: false)
    }

    /// A build using the most and Chrome second, as when a compiler runs beside a full browser.
    static func companionBelowCard(_ now: Date, _ status: ChromeCompanion.Status) -> Card {
        let build = MemGroup(key: "rustc", name: "rustc", kind: .job, bundle: nil, bytes: 5_700_000_000, count: 1)
        let chrome = MemGroup(key: "c", name: "Google Chrome", kind: .browser, bundle: "/Applications/Google Chrome.app", bytes: 3_800_000_000, count: 41)
        return MemoryAdvice.card([build, chrome], mac: mac("warning", swappedMB: 843), now: now,
                                 context: MemoryContext(slowed: true, week: PressureHistory.Week(count: 3, minutes: 40, chromeCount: 2),
                                                        chrome: chromeParts(now, hiddenGB: 1.4), companion: status), tabMemoryOn: false)
    }

    static func chromeCompanionChecks(_ now: Date) -> [(String, Bool, String)] {
        let below = companionBelowCard(now, .connected)
        let belowIDs = below.fixes.map(\.id)
        let sleepFirst = (belowIDs.firstIndex(of: "sleep") ?? .max) < (belowIDs.firstIndex(of: "restart") ?? -1)
            && (belowIDs.firstIndex(of: "restart") ?? .max) < (belowIDs.firstIndex(of: "quit2") ?? -1)
        let belowOffered = companionBelowCard(now, .notInstalled).fixes.contains { $0.id == "companion" }
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
        // a file from 0.17.0, which allowed only the hand-loaded ID, counts as out of date, so it's written again
        let older = ChromeLink.manifest(hostPath: fakeHelper, extensionIDs: [ChromeCompanion.handID]) ?? []
        FileManager.default.createFile(atPath: hosts + "/" + ChromeLink.hostName + ".json", contents: Data(older))
        let rewritten = !ChromeCompanion.hostFileInstalled(folder: hosts, helper: fakeHelper)
            && ChromeCompanion.installHostFile(folder: hosts, helper: fakeHelper) && ChromeCompanion.hostFileInstalled(folder: hosts, helper: fakeHelper)
        try? FileManager.default.removeItem(atPath: hosts); try? FileManager.default.removeItem(atPath: fakeHelper)
        let noAmount = sleepNoAmount(now)
        let profiles = twoProfiles()
        let memoryWords = [ChromeLinkServer.memory(mac("normal", swappedMB: nil), slowed: false), ChromeLinkServer.memory(mac("warning", swappedMB: 30), slowed: false),
                           ChromeLinkServer.memory(mac("warning", swappedMB: 600), slowed: true), ChromeLinkServer.memory(mac("critical", swappedMB: 600), slowed: true)]
        return [("chrome-link-end-to-end", link.ran && link.linked && link.state && link.request && link.answered && link.unlinked, "\(link)"),
                ("chrome-link-setup-file", wrote && rewritten, "written and recognized \(wrote), an older file rewritten \(rewritten)"),
                ("chrome-link-memory-words", memoryWords == [.fine, .tight, .slowed, .veryTight], "\(memoryWords)"),
                ("companion-one-click", on.recommended?.id == "sleep" && on.recommended?.title == "Sleep 12 tabs you aren't looking at"
                 && !ids.contains("tabs") && ids.contains("duplicates") && on.fixes.first { $0.id == "extensions" }.map { if case .chromeCompanion = $0.kind { return true } else { return false } } == true
                 && offered && notYet && noChrome, ids.joined(separator: " ") + "; offered \(offered), not after once \(notYet), not without Chrome \(noChrome)"),
                // Chrome second, behind a build: the extension's one click still comes, before Restart and Quit
                ("companion-chrome-not-biggest", sleepFirst && below.recommended?.id == "sleep" && below.recommended?.title == "Sleep Chrome tabs you aren't looking at"
                 && below.recommended?.consequence.hasPrefix("They stay in the tab bar and reload when clicked") == true && belowOffered && !belowIDs.contains("companion"),
                 belowIDs.joined(separator: " ") + "; offered when not linked \(belowOffered)"),
                // no amount promised: how many tabs (the extension's own count) before, what Chrome gave back after,
                // measured; nothing about an amount when the count isn't known
                ("sleep-says-how-many", sleepWords.allSatisfy { $0 }, "\(sleepWords)"),
                ("sleep-no-amount-when-linked", noAmount.linked && noAmount.unlinked, "linked says none \(noAmount.linked), unlinked says it \(noAmount.unlinked)"),
                ("sleep-count-every-profile", sleepCountTaken.allSatisfy { $0 } && profiles.map { $0.count == 20 && $0.waited && $0.both?.count == 20
                    && $0.both?.done == "Slept 12 tabs." && $0.gone?.count == 12 && $0.quick } ?? true,
                 "\(sleepCountTaken); live \(profiles.map { "\($0)" } ?? "no helper built")")]
    }

    /// The sleep option's words before and after (see MemoryAdvice.sleepChromeTabs, ChromeParts.gaveBack).
    static var sleepWords: [Bool] {
        func ctx(_ n: Int?) -> MemoryContext { var c = MemoryContext(companion: .connected); c.tabsToSleep = n; return c }
        let gb = { (x: Double) in UInt64(x * 1_073_741_824) }
        return [
            MemoryAdvice.sleepChromeTabs(ctx(12), chrome: false, recommended: true).title == "Sleep 12 tabs you aren't looking at",
            MemoryAdvice.sleepChromeTabs(ctx(12), chrome: true, recommended: true).title == "Sleep 12 Chrome tabs you aren't looking at",
            MemoryAdvice.sleepChromeTabs(ctx(1), chrome: false, recommended: true).title == "Sleep 1 tab you aren't looking at",
            MemoryAdvice.sleepChromeTabs(ctx(0), chrome: false, recommended: true).title == "Sleep tabs you aren't looking at",
            MemoryAdvice.sleepChromeTabs(ctx(nil), chrome: true, recommended: true).title == "Sleep Chrome tabs you aren't looking at",
            MemoryAdvice.sleepChromeTabs(ctx(12), chrome: false, recommended: true).consequence == "They stay in the tab bar and reload when clicked; tabs and sites you keep, calls, sound, and unsent typing stay awake.",
            MemoryAdvice.sleepChromeTabs(ctx(1), chrome: false, recommended: true).consequence.hasPrefix("It stays in the tab bar and reloads when clicked;"),
            // the count is said once, in the title: never again in the card's explanation or the option's consequence
            { let c = companionCard(Date(timeIntervalSince1970: 1_790_000_000), .connected)
              return c.fixes.first { $0.id == "sleep" }?.title.contains("12") == true && !c.explanation.contains("12")
                  && !c.fixes.contains { $0.consequence.contains("12 tabs") } }(),
            ChromeParts.gaveBack(count: 12, done: "", before: gb(5.1), after: gb(3.1), measuring: false) == "Slept 12 tabs.\nChrome: 5.1 GB → 3.1 GB (2.0 GB less).",
            ChromeParts.gaveBack(count: 1, done: "", before: gb(5.1), after: nil, measuring: true) == "Slept 1 tab.\nChrome: 5.1 GB → measuring again in 45 seconds…",
            // the one reading comes after T15's "within about 40 seconds"
            ChromeParts.measureAfter > 40,
            ChromeParts.gaveBack(count: 3, done: "", before: nil, after: gb(3), measuring: false) == "Slept 3 tabs.",
            // Chrome quit before the second reading: nothing to compare, and never "measuring" for good
            ChromeParts.gaveBack(count: 12, done: "", before: gb(5.1), after: nil, measuring: false) == "Slept 12 tabs.",
            // a change under the line, either way, and one that rounds to the same figure: one figure, not "5.0 GB → 5.0 GB"
            ChromeParts.gaveBack(count: 3, done: "", before: gb(5), after: gb(5) - 10_000_000, measuring: false) == "Slept 3 tabs.\nChrome: 5.0 GB, not down yet: Chrome frees a slept tab's memory when it closes the tab's process.",
            ChromeParts.gaveBack(count: 3, done: "", before: gb(5), after: gb(5) + 10_000_000, measuring: false).hasSuffix(", not down yet: Chrome frees a slept tab's memory when it closes the tab's process."),
            ChromeParts.gaveBack(count: 3, done: "", before: gb(5.03), after: gb(5.03) - 64_000_000, measuring: false) == "Slept 3 tabs.\nChrome: 5.0 GB, 61 MB less than before.",
            // the line is in the megabytes shown: exactly 50 MB counts, a byte under doesn't
            ChromeParts.gaveBack(count: 3, done: "", before: gb(1), after: gb(1) - 50 * 1_048_576, measuring: false) == "Slept 3 tabs.\nChrome: 1.0 GB → 974 MB (50 MB less).",
            ChromeParts.gaveBack(count: 3, done: "", before: gb(1), after: gb(1) - 50 * 1_048_576 + 1, measuring: false).contains("not down yet"),
            // a rise is said as a rise, never "not down yet"
            ChromeParts.gaveBack(count: 3, done: "", before: gb(5), after: gb(5.2), measuring: false) == "Slept 3 tabs.\nChrome: 5.0 GB → 5.2 GB, up rather than down: the rest of Chrome grew by more than the slept tabs gave back.",
            ChromeParts.gaveBack(count: 0, done: "No tabs needed to sleep.", before: gb(5), after: gb(3), measuring: false) == "No tabs needed to sleep.",
            // a count of 0: said, and not recommended, whether Chrome is the biggest or below it
            { let z = MemoryAdvice.sleepChromeTabs(ctx(0), chrome: true, recommended: true)
              return !z.recommended && z.consequence.hasPrefix("None can sleep now") }(),
            { let c = MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: Date(timeIntervalSince1970: 1_790_000_000),
                                        context: ctx(0), tabMemoryOn: false)
              return c.fixes.contains { $0.id == "sleep" } && c.fixes.first { $0.id == "sleep" }?.recommended == false }(),
        ]
    }

    /// Linked, the card says no amount in tabs out of sight (sleeping may not give it back; the option carries the
    /// count); not linked, Cool Head's own figure stays.
    static func sleepNoAmount(_ now: Date) -> (linked: Bool, unlinked: Bool) {
        let amount = "of Chrome's memory is in tabs you aren't looking at"
        let on = companionCard(now, .connected), off = companionCard(now, .notInstalled)
        return (!on.explanation.contains(amount) && !on.fixes.contains { $0.consequence.contains(amount) }, off.explanation.contains(amount))
    }

    /// The count reaches the card only while the extension is linked, and every profile's together (ChromeLinkServer).
    static var sleepCountTaken: [Bool] {
        func report(_ n: Int?) -> ChromeLink.Report {
            ChromeLink.Report(asleep: 0, held: [:], session: .init(active: false, tabs: 0), duplicates: 0, extensionsResting: 0, level: .auto, toSleep: n)
        }
        func taken(_ status: ChromeCompanion.Status, _ n: Int?) -> Int? {
            var c = MemoryContext(companion: status); c.take(ChromeLinkServer.Summary(connected: true, report: report(n), toSleep: n)); return c.tabsToSleep
        }
        func answer(_ ok: Bool, _ n: Int?, _ done: String) -> ChromeLink.ActionResult { ChromeLink.ActionResult(id: "r", ok: ok, done: done, count: n) }
        let two = ChromeLinkServer.combined([answer(true, 12, "Slept 12 tabs."), answer(true, 8, "Slept 8 tabs.")])
        let mixed = ChromeLinkServer.combined([answer(false, 0, "Not now."), answer(true, 5, "Slept 5 tabs.")])
        return [taken(.connected, 7) == 7, taken(.notInstalled, 7) == nil, taken(.connected, nil) == nil,
                ChromeLinkServer.toSleep(of: [report(12), report(8)]) == 20,
                ChromeLinkServer.toSleep(of: [report(12), report(nil)]) == nil,     // one profile's extension doesn't say
                ChromeLinkServer.toSleep(of: [report(12), nil]) == nil,             // one profile hasn't reported yet
                ChromeLinkServer.toSleep(of: []) == nil,
                two?.count == 20 && two?.ok == true && two?.done == "Slept 12 tabs.",
                mixed?.ok == true && mixed?.count == 5 && mixed?.done == "Slept 5 tabs.",
                ChromeLinkServer.combined([answer(true, 3, "Slept 3 tabs.")]) == answer(true, 3, "Slept 3 tabs."),
                ChromeLinkServer.combined([]) == nil]
    }

    /// Two Chrome profiles, each with the extension, through the real helper: the card's count is both together, a
    /// press waits for both answers and adds them up, and a profile that goes without answering isn't waited for.
    static func twoProfiles() -> (count: Int?, waited: Bool, both: ChromeLink.ActionResult?, gone: ChromeLink.ActionResult?, quick: Bool)? {
        guard let host = Fixture.chromeHostPath() else { return nil }
        let dir = NSTemporaryDirectory() + "chp-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let server = ChromeLinkServer()
        guard server.start(path: dir + "/s.sock") else { return nil }
        defer { server.stop() }
        var runs: [Fixture.HostRun] = []
        for n in [12, 8] {
            guard let run = Fixture.HostRun(host, socket: dir + "/s.sock") else { return nil }
            _ = run.receive(); _ = run.receive()       // the link, and Cool Head's hello
            _ = run.send(ChromeLink.frame(ChromeLink.encode(ChromeLink.ExtensionHello(extension: "1.4.0", browser: "chrome", level: .auto)))!)
            _ = run.send(ChromeLink.frame(ChromeLink.encode(ChromeLink.Report(asleep: 0, held: [:], session: .init(active: false, tabs: 0),
                                                                                duplicates: 0, extensionsResting: 0, level: .auto, toSleep: n)))!)
            runs.append(run)
        }
        let until = Date().addingTimeInterval(3)
        while server.summary.toSleep != 20 && Date() < until { usleep(20_000) }
        let count = server.summary.toSleep
        func answer(_ run: Fixture.HostRun, _ n: Int) {
            if let m = run.receive(), let r = ChromeLink.decode(ChromeLink.Request.self, from: m) {
                _ = run.send(ChromeLink.frame(ChromeLink.encode(ChromeLink.ActionResult(id: r.id, ok: true, done: "Slept \(n) tabs.", count: n)))!)
            }
        }
        func wait(_ box: ResultBox, _ seconds: Double) { let u = Date().addingTimeInterval(seconds); while box.get() == nil && Date() < u { usleep(20_000) } }
        let both = ResultBox()
        server.request(.sleepHidden) { both.set($0) }
        answer(runs[0], 12)
        wait(both, 0.3)
        let waited = both.get() == nil                 // one answer isn't the whole answer
        answer(runs[1], 8)
        wait(both, 3)
        let gone = ResultBox(), asked = Date()
        server.request(.sleepHidden) { gone.set($0) }
        answer(runs[0], 12)
        _ = runs[1].finish()                           // the second profile's Chrome closes without answering
        wait(gone, 8)
        let quick = gone.get() != nil && Date().timeIntervalSince(asked) < 8
        _ = runs[0].finish()
        return (count, waited, both.get(), gone.get(), quick)
    }

    static func chromeCompanionSamples(_ now: Date) -> [(String, Card)] {
        [("memory-chrome-companion", companionCard(now, .connected)), ("memory-chrome-companion-none-to-sleep", companionCard(now, .connected, toSleep: 0)),
         ("memory-chrome-get-companion", companionCard(now, .notInstalled)),
         ("memory-chrome-second-companion", companionBelowCard(now, .connected))]
    }
}

/// The answer to a request, from the link's own queue.
final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ChromeLink.ActionResult?
    func set(_ r: ChromeLink.ActionResult?) { lock.withLock { value = r } }
    func get() -> ChromeLink.ActionResult? { lock.withLock { value } }
}

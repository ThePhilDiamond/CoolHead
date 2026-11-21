import Foundation

/// Checks for Chrome's memory by part (see ChromeParts): hidden tabs, restart advice, and hiding tab groups.
extension Fixture {
    static let chromeApp = "/Applications/Google Chrome.app"
    static func chromeProc(_ type: String?, _ gb: Double, pri: Int? = 46, ext: Bool = false, start: Date? = nil, app: String = chromeApp) -> ChromeParts.Process {
        let helper = app + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let path = type == nil ? app + "/Contents/MacOS/Google Chrome" : helper
        var args = [path] + (type.map { ["--type=\($0)"] } ?? [])
        if ext { args.append("--extension-process") }
        return ChromeParts.Process(path: path, args: args, footprint: UInt64(gb * 1_073_741_824), priority: pri, start: start)
    }
    static func chromeParts(_ now: Date, hiddenGB: Double = 2.1, browserGB: Double = 0.6, gpuGB: Double = 0.4, openDays: Double = 1, extGB: Double = 0.3) -> ChromeParts {
        var procs = [chromeProc(nil, browserGB, start: now.addingTimeInterval(-openDays * 86400)), chromeProc("gpu-process", gpuGB),
                     chromeProc("renderer", 0.7, pri: 97), chromeProc("renderer", 0.7, pri: 47), chromeProc("renderer", extGB, pri: 4, ext: true)]
        for _ in 0..<7 { procs.append(chromeProc("renderer", hiddenGB / 7, pri: 4)) }
        return ChromeParts.read(procs, bundle: chromeApp)
    }

    static func chromePartsChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        // reading: hidden tabs at 4, shown above it; extensions, other browsers, and Chrome's own parts kept apart
        var procs = [chromeProc(nil, 0.6, start: now.addingTimeInterval(-6 * 86400)), chromeProc("gpu-process", 0.4), chromeProc("renderer", 0.7, pri: 97),
                     chromeProc("renderer", 0.5, pri: 4), chromeProc("renderer", 0.5, pri: 4), chromeProc("renderer", 0.3, pri: 4, ext: true),
                     chromeProc("renderer", 0.9, pri: 4, app: "/Applications/Microsoft Edge.app"), chromeProc("utility", 0.2)]
        let p = ChromeParts.read(procs, bundle: chromeApp)
        review.append(("chrome-parts-read", p.hiddenCount == 2 && p.hiddenBytes == 2 * UInt64(0.5 * 1_073_741_824) && p.shownCount == 1 && p.shownBytes == UInt64(0.7 * 1_073_741_824)
                       && p.browserBytes == UInt64(0.6 * 1_073_741_824) && p.gpuBytes == UInt64(0.4 * 1_073_741_824) && p.openSince == now.addingTimeInterval(-6 * 86400) && p.markWorks,
                       "hidden \(p.hiddenCount) (\(p.hiddenBytes)), shown \(p.shownCount), browser \(p.browserBytes), graphics \(p.gpuBytes)"))
        // no tab in the band, or none out of it: Chrome isn't marking them here, so nothing is said
        procs = [chromeProc("renderer", 1, pri: 46), chromeProc("renderer", 1, pri: 47)]
        let unmarked = ChromeParts.read(procs, bundle: chromeApp)
        review.append(("chrome-parts-mark", !unmarked.markWorks && unmarked.hiddenSentence == nil && unmarked.facts.isEmpty, "all at 46 or 47: says nothing"))

        let tight = mac("warning", swappedMB: 600)
        func card(_ parts: ChromeParts?, groups: [MemGroup] = chromeHeavy) -> Card {
            MemoryAdvice.card(groups, mac: tight, now: now, context: MemoryContext(slowed: true, chrome: parts), tabMemoryOn: false)
        }
        // the hidden-tab sentence, from 500 MB, and its evidence in Nerdy stuff
        let big = card(chromeParts(now)), small = card(chromeParts(now, hiddenGB: 0.3))
        review.append(("chrome-hidden-line", big.explanation.contains("About 2.1 GB of Chrome's memory is in tabs you aren't looking at")
                       && big.facts.contains { $0.hasPrefix("Chrome's tabs: 2.1 GB in 7 processes Chrome marks as hidden") }
                       && !small.explanation.contains("tabs you aren't looking at"), big.explanation))
        // open for days: said, and the restart option says so, still not recommended
        let days = card(chromeParts(now, hiddenGB: 0.3, openDays: 6.2))
        let daysRestart = days.fixes.first { $0.id == "restart" }
        review.append(("chrome-restart-days", !days.explanation.contains("open for") && daysRestart?.recommended == false
                       && daysRestart?.consequence.contains("built up over 6 days") == true, days.explanation))
        // Chrome's own program grown: only a restart gives it back, so it's recommended; closing tabs still fixes the cause
        let grown = card(chromeParts(now, hiddenGB: 0.3, browserGB: 3.2))
        review.append(("chrome-restart-grown", grown.recommended?.id == "restart" && grown.explanation.contains("Chrome's own program has grown to 3.2 GB")
                       && grown.fixes.contains { $0.id == "tabs" }, (grown.recommended?.id ?? "none") + ": " + grown.explanation))
        // hiding tab groups: from 1 GB hidden, for Chrome only
        let edge = MemoryAdvice.card([MemGroup(key: "e", name: "Microsoft Edge", kind: .browser, bundle: "/Applications/Microsoft Edge.app", bytes: 5_500_000_000, count: 41)],
                                     mac: tight, now: now, context: MemoryContext(slowed: true, chrome: chromeParts(now)))
        let groupsFix = big.fixes.first { $0.id == "groups" }
        review.append(("chrome-groups-option", groupsFix?.title == "Hide tab groups you aren't using" && !card(chromeParts(now, hiddenGB: 0.6)).fixes.contains { $0.id == "groups" }
                       && !edge.fixes.contains { $0.id == "groups" } && !card(nil).fixes.contains { $0.id == "groups" }, groupsFix?.consequence ?? "not offered"))
        // extensions: said from 500 MB, with where to see which, since unloading tabs never reaches them
        let exts = card(chromeParts(now, extGB: 1.6)), fewExts = card(chromeParts(now))
        let extFix = exts.fixes.first { $0.id == "extensions" }
        review.append(("chrome-extensions-line", extFix?.consequence.contains("Chrome's extensions are using 1.6 GB, which closing tabs doesn't give back.") == true
                       && extFix?.title == "Turn off extensions you don't use" && exts.facts.contains { $0.hasPrefix("Chrome's extensions: 1.6 GB in 1 process") }
                       && !fewExts.fixes.contains { $0.id == "extensions" }, extFix?.consequence ?? "not offered"))
        return review
    }

    static func chromePartsSamples(_ now: Date) -> [(String, Card)] {
        func card(_ parts: ChromeParts) -> Card {
            MemoryAdvice.card(chromeHeavy, mac: mac("warning", swappedMB: 600), now: now, context: MemoryContext(slowed: true, chrome: parts), tabMemoryOn: false)
        }
        return [("memory-chrome-hidden-tabs", card(chromeParts(now, openDays: 6.2, extGB: 1.6))),
                ("memory-chrome-grown", card(chromeParts(now, hiddenGB: 0.3, browserGB: 3.2)))]
    }
}

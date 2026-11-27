import Foundation

/// Checks for the browser cards (see BrowserTampering.swift): foreign settings are named in plain words and never
/// counted when an organization manages the Mac or when they're Cool Head's own; a browser started by a script with an
/// extension is told apart from one opened from the Dock; and the text leaves the action to the options.
extension Fixture {
    static func browserTamperingChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let chrome = "/Applications/Google Chrome.app"

        // which settings count: hijack kinds yes, Cool Head's own memory limit no
        let set: Set<String> = ["ExtensionInstallForcelist", "DefaultSearchProviderSearchURL", "TotalMemoryLimitMb"]
        let words = BrowserTampering.foreign { set.contains($0) }
        let mine = BrowserTampering.foreign { ["TotalMemoryLimitMb", "HighEfficiencyModeEnabled", "MemorySaverModeSavings"].contains($0) }
        let e1 = BrowserTampering.parseEnrollment("Enrolled via DEP: No\nMDM enrollment: No\n") == false
            && BrowserTampering.parseEnrollment("Enrolled via DEP: No\nMDM enrollment: Yes (User Approved)\n") == true
        let p1 = words == ["force an extension", "set the search engine"] && mine.isEmpty && e1
        review.append(("browser-policy-reads", p1, "foreign: \(words); Cool Head's own: \(mine)"))

        // the card: on an unmanaged Mac only, naming what they do
        let policy = BrowserTampering.cards(policies: [("Google Chrome", chrome, words)], managed: false, scripted: [])
        let managed = BrowserTampering.cards(policies: [("Google Chrome", chrome, words)], managed: true, scripted: [])
        let clean = BrowserTampering.cards(policies: [("Google Chrome", chrome, mine)], managed: false, scripted: [])
        let c1 = policy.first?.card.headline == "Google Chrome uses settings that Cool Head did not make."
            && policy.first?.card.explanation.hasPrefix("They force an extension and set the search engine.") == true
            && policy.first?.card.fixes.first?.kind == .openPage(chrome, "chrome://policy")
            && managed.isEmpty && clean.isEmpty
        review.append(("browser-policy-card", c1, policy.first.map { $0.card.headline + " " + $0.card.explanation } ?? "none"))

        // started by a script with an extension, versus opened from the Dock (launchd), versus no extension
        let exe = chrome + "/Contents/MacOS/Google Chrome"
        let s = BrowserTampering.scripted(pid: 4100, path: exe, args: [exe, "--load-extension=" + NSHomeDirectory() + "/Downloads/helper-ext,/tmp/b"], parentPID: 4000, parentName: "node")
        let dock = BrowserTampering.scripted(pid: 4101, path: exe, args: [exe, "--load-extension=/tmp/a"], parentPID: 1, parentName: "launchd")
        let plain = BrowserTampering.scripted(pid: 4102, path: exe, args: [exe, "--restore-last-session"], parentPID: 4000, parentName: "node")
        let helper = BrowserTampering.scripted(pid: 4103, path: chrome + "/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
                                               args: ["--load-extension=/tmp/a"], parentPID: 4100, parentName: "Google Chrome")
        let card = s.map { BrowserTampering.cards(policies: [], managed: false, scripted: [$0]) } ?? []
        let s1 = s?.folder == NSHomeDirectory() + "/Downloads/helper-ext" && s?.shown == "~/Downloads/helper-ext" && s?.parent == "node" && dock == nil && plain == nil && helper == nil
            && card.first?.card.headline == "Google Chrome was started by a script, with an extension loaded."
            && card.first?.card.fixes.first?.kind == .reveal(NSHomeDirectory() + "/Downloads/helper-ext", "If you do not recognize it, quit Google Chrome, then move the folder to the Trash.")
            && card.first?.card.fixes.last?.caution == true
            && card.first?.details.contains("Extension folder: ~/Downloads/helper-ext") == true
        review.append(("browser-scripted-card", s1, card.first.map { $0.card.headline + " " + $0.card.explanation } ?? "none"))

        // the text gives the verdict and the evidence; the options carry the action
        let all = policy + card
        let w1 = all.allSatisfy { c in c.card.fixes.allSatisfy { !(c.card.headline + " " + c.card.explanation).contains($0.title) } }
        review.append(("browser-wording", w1, "\(all.count) cards: no option title in the text"))

        // this Mac: reads quickly, as any user
        let t = Date()
        let live = BrowserTampering.read()
        let took = Date().timeIntervalSince(t)
        review.append(("browser-live-read", took < 2, String(format: "%.2f s; managed: %@; browsers with foreign settings: %d; started by a script: %d",
                                                             took, live.managed ? "yes" : "no", live.policies.filter { !$0.foreign.isEmpty }.count, live.scripted.count)))
        return review
    }

    /// For `coolhead wording` and screenshots: each browser card, made up.
    static func browserTamperingSamples(_ now: Date) -> [(String, Card)] {
        let chrome = "/Applications/Google Chrome.app"
        let policy = BrowserTampering.cards(policies: [("Google Chrome", chrome, ["force an extension", "set the search engine"])], managed: false, scripted: [])
        let scripted = BrowserTampering.cards(policies: [], managed: false, scripted: [
            BrowserTampering.Scripted(pid: 4100, browser: "Google Chrome", bundle: chrome, parent: "node", folder: NSHomeDirectory() + "/Downloads/helper-ext")])
        return [("browser-policy", policy.first?.card), ("browser-scripted", scripted.first?.card)].compactMap { k, c in c.map { (k, $0) } }
    }
}

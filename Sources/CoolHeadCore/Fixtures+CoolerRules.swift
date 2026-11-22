import Foundation

/// Checks for "every time" (CoolerRules): when a rule slows something, that trusting and always slowing are opposites,
/// what a rule matches, and what a card says about something that already has one.
extension Fixture {
    static func coolerRulesSamples(_ now: Date) -> [(String, Card)] { [] }

    static func coolerRulesChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let app = "app:com.example.huddle", job = "script:/Users/x/tools/export.py"

        // an app: full speed while in front and for a few seconds after you switch away; slowed after that. A job: always.
        let inFront = CoolerRules.slowNow(key: app, frontKey: app, leftFrontAt: nil, now: now)
        let justLeft = CoolerRules.slowNow(key: app, frontKey: "app:com.example.mail", leftFrontAt: now.addingTimeInterval(-2), now: now)
        let leftAWhile = CoolerRules.slowNow(key: app, frontKey: "app:com.example.mail", leftFrontAt: now.addingTimeInterval(-10), now: now)
        let neverFront = CoolerRules.slowNow(key: app, frontKey: nil, leftFrontAt: nil, now: now)
        let jobAlways = CoolerRules.slowNow(key: job, frontKey: job, leftFrontAt: now, now: now)
        review.append(("every-time-app-in-front-full-speed", !inFront && !justLeft && leftAWhile && neverFront && jobAlways,
                       "in front \(inFront); 2 seconds after leaving \(justLeft); 10 seconds after \(leftAWhile); never in front \(neverFront); a job \(jobAlways)"))

        // stored in a throwaway set, never the app's own settings: adding a rule stops trusting it, trusting removes the rule
        let suite = "coolhead.selftest.\(UUID().uuidString)"
        let saved = Trust.defaults
        if let d = UserDefaults(suiteName: suite) { Trust.defaults = d }
        Trust.add(app, name: "Huddle")
        CoolerRules.add(app, name: "Huddle")
        let ruleRemovesTrust = CoolerRules.contains(app) && !Trust.contains(app)
        Trust.add(app, name: "Huddle")
        let trustRemovesRule = Trust.contains(app) && !CoolerRules.contains(app)
        CoolerRules.add(job, name: "export.py")
        CoolerRules.remove(job)
        let removed = !CoolerRules.contains(job) && CoolerRules.all.isEmpty
        Trust.defaults = saved
        UserDefaults.standard.removePersistentDomain(forName: suite)
        review.append(("every-time-opposite-of-trust", ruleRemovesTrust && trustRemovesRule && removed,
                       "a rule stops trusting \(ruleRemovesTrust); trusting removes the rule \(trustRemovesRule); removed \(removed)"))

        // what a rule matches: a script by its own location, whichever folder it was started from; an app's helper by its app
        let s1 = Trust.key(path: "/opt/homebrew/bin/python3", name: "python3", args: ["python3", "tools/export.py"], cwd: "/Users/x")
        let s2 = Trust.key(path: "/opt/homebrew/bin/python3", name: "python3", args: ["python3", "/Users/x/tools/export.py", "--all"], cwd: "/")
        let helper = Trust.key(path: "/Applications/Huddle Example.app/Contents/Frameworks/Huddle Helper.app/Contents/MacOS/Huddle Helper",
                               name: "Huddle Helper", args: [], cwd: nil)
        let macOS = Trust.key(path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", name: "Finder", args: [], cwd: nil)
        review.append(("every-time-matches", s1 == job && s2 == job && helper == "app:/Applications/Huddle Example.app" && macOS == nil,
                       "relative \(s1 ?? "nil"); full \(s2 ?? "nil"); helper \(helper ?? "nil"); macOS's own \(macOS ?? "nil")"))

        // a card about something with a rule says so and doesn't offer Run it cooler again
        let e = Evidence.sample(name: "render", path: "/Users/x/bin/render", start: now.addingTimeInterval(-3 * 3600), cores: 2)
        let c = Card.make(e, now: now, busySince: now.addingTimeInterval(-2 * 3600), warm: true)
        let ruled = c.underRule(app: false)
        let offeredBefore = c.fixes.contains { $0.kind == .cooler }
        let ok = offeredBefore && !ruled.fixes.contains { $0.kind == .cooler } && ruled.explanation.hasSuffix(CoolerRules.cardLine(app: false))
            && ruled.headline == c.headline
        review.append(("every-time-card-says-so", ok, "offered before \(offeredBefore); after: \(ruled.explanation)"))
        return review
    }
}

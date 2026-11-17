import Foundation

/// Two signs that something other than the person is steering their browser (rules 2 and 3 in the research), read
/// without a password (tested 16 November 2026, macOS 26.6.2): settings that force an extension, a search provider, a
/// home page or a proxy, on a Mac no organization manages; and a browser started by a script with an extension loaded
/// from a folder. Each card says "looks like", never "is malware", and Cool Head never removes another party's setting:
/// it shows where to look. The text gives the verdict and the evidence; the option carries the action.
public enum BrowserTampering {
    /// The Chromium browsers whose user-level policies Cool Head reads, by preferences domain.
    public static let browsers: [(name: String, domain: String, bundle: String, executable: String)] = [
        ("Google Chrome", "com.google.Chrome", "/Applications/Google Chrome.app", "Google Chrome"),
        ("Microsoft Edge", "com.microsoft.Edge", "/Applications/Microsoft Edge.app", "Microsoft Edge"),
        ("Brave", "com.brave.Browser", "/Applications/Brave Browser.app", "Brave Browser"),
    ]

    /// What the foreign settings do, in plain words, from the policy names that hijacking adware uses (Malwarebytes,
    /// April 2018). Cool Head's own memory-limit keys are never counted (see ChromeLimit).
    static let kinds: [(keys: [String], words: String)] = [
        (["ExtensionInstallForcelist", "ExtensionSettings"], "force an extension"),
        (["DefaultSearchProviderEnabled", "DefaultSearchProviderSearchURL", "DefaultSearchProviderName"], "set the search engine"),
        (["HomepageLocation", "HomepageIsNewTabPage", "NewTabPageLocation", "RestoreOnStartup", "RestoreOnStartupURLs"], "set the home page"),
        (["ProxyMode", "ProxyServer", "ProxySettings", "ProxyPacUrl"], "send its traffic through a proxy"),
    ]

    /// What foreign policies a browser has: each kind's words, in order. `has` says whether a policy name is set.
    public static func foreign(_ has: (String) -> Bool) -> [String] {
        kinds.filter { $0.keys.contains(where: has) }.map(\.words)
    }

    /// Whether an organization manages this Mac: enrolled in device management (`profiles status -type enrollment`), or
    /// a managed-preferences folder from one.
    public static func parseEnrollment(_ text: String) -> Bool {
        text.split(separator: "\n").contains { l in
            (l.contains("MDM enrollment:") || l.contains("Enrolled via DEP:")) && l.contains("Yes")
        }
    }

    /// A browser started by something other than the person, with an extension loaded from a folder.
    public struct Scripted: Equatable {
        public var pid: Int32; public var browser: String; public var bundle: String; public var parent: String; public var folder: String
        public init(pid: Int32, browser: String, bundle: String, parent: String, folder: String) {
            self.pid = pid; self.browser = browser; self.bundle = bundle; self.parent = parent; self.folder = folder
        }
        /// The folder as Cool Head shows it: the home folder as ~, so the account's name never appears.
        public var shown: String { (folder as NSString).abbreviatingWithTildeInPath }
    }
    /// From a process's path, arguments and parent's name: a browser's main program started with `--load-extension` by
    /// anything but launchd (the Dock, Finder and Spotlight all start apps through it).
    public static func scripted(pid: Int32, path: String, args: [String], parentPID: Int32, parentName: String) -> Scripted? {
        guard parentPID > 1,
              let b = browsers.first(where: { path.hasSuffix("/Contents/MacOS/" + $0.executable) }),
              let arg = args.first(where: { $0.hasPrefix("--load-extension=") }) else { return nil }
        let first = String(arg.dropFirst("--load-extension=".count).split(separator: ",").first ?? "")
        return Scripted(pid: pid, browser: b.name, bundle: b.bundle, parent: parentName, folder: first)
    }

    // MARK: Cards

    public static func cards(policies: [(browser: String, bundle: String, foreign: [String])], managed: Bool, scripted: [Scripted]) -> [LiveCard] {
        var out: [LiveCard] = []
        // settings Cool Head didn't make, on a Mac no organization manages (rule 3)
        if !managed, let p = policies.first(where: { !$0.foreign.isEmpty }) {
            let f = p.foreign
            let what = f.count == 1 ? f[0] : f.count == 2 ? "\(f[0]) and \(f[1])" : f.dropLast().joined(separator: ", ") + ", and " + f.last!
            var lc = LiveCard(id: "browser-policy-\(p.browser)", pid: nil, card: Card(
                state: .unknown,
                headline: "\(p.browser) is managed by settings Cool Head didn't make.",
                explanation: "They \(what). Your Mac isn't managed by an organization, so they didn't come from an employer or school. Adware sets these to keep its changes; it may also be software you installed on purpose.",
                fixes: [Fix(id: "policy-page", title: "See what's set in \(p.browser)",
                            consequence: "Its policy page lists each setting and where it came from.",
                            kind: .openPage(p.bundle, "chrome://policy"), recommended: true),
                        Fix(id: "profiles", title: "Check for a profile", consequence: "Settings can also come from a profile someone installed. Remove one you don't recognize there.",
                            kind: .openPage("/System/Applications/System Settings.app", "x-apple.systempreferences:com.apple.Profiles-Settings.extension"))]),
                details: ["Browser: \(p.browser)", "Settings that " + what, "Managed by an organization: no"],
                reportSubject: "browser policies from an unknown source")
            lc.causeKey = "browser-policy"
            lc.displaySubject = p.browser
            out.append(lc)
        }
        // a browser a script started with an extension loaded (rule 2): developers do this; adware has too
        if let s = scripted.first {
            var lc = LiveCard(id: "browser-scripted-\(s.pid)", pid: s.pid, card: Card(
                state: .unknown,
                headline: "\(s.browser) was started by a script, with an extension loaded.",
                explanation: "Started by \(s.parent) rather than from the Dock or Finder, it loaded an extension from a folder instead of an extension store. Developers do this to test extensions; adware has done it to slip one in.",
                fixes: [Fix(id: "reveal-extension", title: "Show the extension's folder", consequence: "Opens it in Finder, so you can see what it is.",
                            kind: .reveal(s.folder, "If you don't recognize it, quit \(s.browser), then move the folder to the Trash."), recommended: true),
                        Fix(id: "quit", title: "Quit \(s.browser)", consequence: "Closes its windows. Opening it from the Dock starts it without the extension.", kind: .quitApp(s.bundle)).losingWork()]),
                details: ["Browser: \(s.browser), process \(s.pid)", "Started by: \(s.parent)", "Extension folder: \(s.shown)"],
                reportSubject: "a browser started by a script with an extension loaded")
            lc.causeKey = "browser-scripted"
            lc.displaySubject = s.browser
            out.append(lc)
        }
        return out
    }

    /// Reads it all, off the main thread: each browser's policy names, whether the Mac is managed, and each running
    /// browser's arguments and parent.
    public static func read() -> (policies: [(browser: String, bundle: String, foreign: [String])], managed: Bool, scripted: [Scripted]) {
        let policies = browsers.map { b in
            (b.name, b.bundle, foreign { CFPreferencesCopyAppValue($0 as CFString, b.domain as CFString) != nil })
        }
        let enrolled = Hardware.run("/usr/bin/profiles", ["status", "-type", "enrollment"]).map { parseEnrollment(String(decoding: $0, as: UTF8.self)) } ?? false
        let managed = enrolled || FileManager.default.fileExists(atPath: "/Library/Managed Preferences/" + NSUserName())
        var scripted: [Scripted] = []
        for pid in Proc.allPIDs() {
            guard let path = Proc.path(pid), browsers.contains(where: { path.hasSuffix("/Contents/MacOS/" + $0.executable) }),
                  let b = Proc.bsd(pid) else { continue }
            let parent = Proc.path(b.ppid).map { ($0 as NSString).lastPathComponent } ?? Proc.bsd(b.ppid)?.name ?? "another program"
            if let s = BrowserTampering.scripted(pid: pid, path: path, args: Proc.args(pid), parentPID: b.ppid, parentName: parent) { scripted.append(s) }
        }
        return (policies, managed, scripted)
    }
}

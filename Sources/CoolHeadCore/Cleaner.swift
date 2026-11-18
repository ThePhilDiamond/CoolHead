import AppKit
import Foundation

/// The Cleaner tool: things left behind that can go to the Trash (Phil, 18 November 2026: "Can we add a broom "cleaner"
/// tool that does a quick scan for things like orphaned preference panes where the app was already uninstalled but the
/// prefs still show in System Settings?"). The research behind each rule is in the side-session notes,
/// research_graph/cleaner-leftovers/synthesis.md (18 November 2026).
///
/// Every find moves to the Trash, never deleted outright, and Cool Head keeps its own list of what it moved so it can
/// put each back (Finder's Put Back is unreliable for items an app moves: an open Apple bug). Nothing Apple signed,
/// nothing in macOS's own folders, and nothing inside an app is ever offered. A find Cool Head can't be sure of is
/// marked Caution and never ticked for the person.
public enum Cleaner {
    /// Where a find sits on the page (Phil, 18 November 2026: "The first section one-button should be stuff that
    /// definitely isn't needed and has no impact, trash. Then the second section, something like "Deep Clean", where you
    /// can select things should auto-check the stuff that rebuilds and have the "check these first" as options to
    /// check."; "things that would need to rebuild could be inaccessible if needed without network (e.g.,
    /// homebrew/xcode), so they go in the advanced/deep clean section").
    public enum Group: String, CaseIterable {
        /// Quick clean: nothing uses it and nothing has to rebuild it; done with one click.
        case quick
        /// Deep clean, ticked: rebuilds itself, which may need the internet.
        case rebuilds
        /// Deep clean, not ticked: probably left behind, but Cool Head can't be sure; or needs a password.
        case check
        public var title: String {
            switch self {
            case .quick: return "Quick clean"
            case .rebuilds: return "Rebuilds itself"
            case .check: return "Check these first"
            }
        }
    }

    /// One thing to clear.
    public struct Find: Identifiable, Equatable {
        public let id: String
        public let group: Group
        /// What it is, in a few words.
        public let title: String
        /// Cool Head's verdict and its one-line disclaimer.
        public let detail: String
        /// Space it takes on disk; nil when too small to matter.
        public let bytes: UInt64?
        /// Cool Head can't be sure nothing still uses it.
        public let caution: Bool
        /// Moving it needs an administrator's password (it's in a folder macOS keeps for all users).
        public let needsAdmin: Bool
        /// Why it can't be done now ("Chrome is open"), or nil.
        public let blocked: String?
        /// What moves to the Trash.
        public let paths: [String]
        /// A background helper's label, stopped (`launchctl bootout`) before its plist moves.
        public let agentLabel: String?
        public init(id: String, group: Group, title: String, detail: String, bytes: UInt64?, caution: Bool = false,
                    needsAdmin: Bool = false, blocked: String? = nil, paths: [String] = [], agentLabel: String? = nil) {
            self.id = id; self.group = group; self.title = title; self.detail = detail; self.bytes = bytes
            self.caution = caution; self.needsAdmin = needsAdmin; self.blocked = blocked; self.paths = paths; self.agentLabel = agentLabel
        }
    }

    /// What kinds of thing a list holds, for the sentence above it ("2 settings panes in the System Settings sidebar").
    public static func kinds(_ finds: [Find]) -> [String] {
        func n(_ prefix: String) -> Int { finds.filter { $0.id.hasPrefix(prefix) }.count }
        var out: [String] = []
        let panes = n("pane:"), agents = n("agent:"), folders = n("caches:"), installers = n("install:"), downloads = n("download:")
        if panes > 0 { out.append(panes == 1 ? "a settings pane in the System Settings sidebar" : "\(panes) settings panes in the System Settings sidebar") }
        if agents > 0 { out.append(agents == 1 ? "a background helper whose program is gone" : "\(agents) background helpers whose program is gone") }
        if folders > 0 { out.append(folders == 1 ? "a deleted app's caches" : "\(folders) deleted apps' caches") }
        if installers > 0 { out.append(installers == 1 ? "an old macOS installer" : "\(installers) old macOS installers") }
        if downloads > 0 { out.append(downloads == 1 ? "an installer in Downloads" : "\(downloads) installers in Downloads") }
        return out
    }

    /// The verdict at the top of the page.
    public static func verdict(_ finds: [Find]) -> (title: String, meaning: String) {
        guard !finds.isEmpty else {
            return ("Nothing to clear", "Nothing left behind by deleted apps, and nothing large that rebuilds itself.")
        }
        let total = finds.filter { $0.blocked == nil }.compactMap(\.bytes).reduce(0, +)
        return (total >= 50_000_000 ? "About \(MemoryAdvice.diskGB(total)) to clear" : "A few things to clear",
                "Everything goes to the Trash, so you can put it back. The space returns when you empty the Trash.")
    }

    // MARK: where it looks

    /// The places a scan reads, and what it knows about this Mac; the selftest points these at a folder of made-up files.
    public struct Roots {
        public var home: String
        /// The folder macOS keeps for all users ("/Library").
        public var library: String
        /// Where apps are installed: each is listed, and the folders inside it one level down.
        public var applications: [String]
        public var now: Date
        /// Bundle IDs of the apps open now.
        public var running: Set<String>
        /// Managed by an organization: nothing in the shared folders is offered.
        public var enrolled: Bool
        /// macOS's major version, to tell an older installer.
        public var macOSMajor: Int
        /// Whether macOS knows an app with this bundle ID anywhere (Launch Services).
        public var registered: (String) -> Bool
        public init(home: String, library: String, applications: [String], now: Date = Date(), running: Set<String> = [],
                    enrolled: Bool = false, macOSMajor: Int, registered: @escaping (String) -> Bool = { _ in false }) {
            self.home = home; self.library = library; self.applications = applications; self.now = now; self.running = running
            self.enrolled = enrolled; self.macOSMajor = macOSMajor; self.registered = registered
        }

        /// This Mac: the open apps, Launch Services, and whether an organization manages it.
        public static func thisMac() -> Roots {
            let home = NSHomeDirectory()
            let enrolled = Hardware.run("/usr/bin/profiles", ["status", "-type", "enrollment"])
                .map { BrowserTampering.parseEnrollment(String(decoding: $0, as: UTF8.self)) } ?? true   // unreadable: treat as managed
            return Roots(home: home, library: "/Library", applications: ["/Applications", home + "/Applications"],
                         running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                         enrolled: enrolled || FileManager.default.fileExists(atPath: "/Library/Managed Preferences/" + NSUserName()),
                         macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                         registered: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        }
    }

    /// Everything a scan finds, in the page's order. Seconds at most; run it off the main thread.
    public static func scan(_ r: Roots) -> [Find] {
        let apps = installedApps(r)
        var out: [Find] = []
        out += brokenAgents(r)
        out += oldLogs(r)
        out += savedState(r, apps: apps)
        out += rebuilds(r)
        out += panes(r, apps: apps)
        out += orphanCaches(r, apps: apps)
        out += oldInstallers(r)
        return out
    }

    // MARK: what's installed (the "owner gone" test, failing closed)

    /// The apps on this Mac: their bundle IDs and where they are. Nil when Applications can't be read, and then nothing
    /// is called left behind (a scan that can't see what's installed mustn't guess).
    public struct Installed {
        public var ids: Set<String>
        public var paths: [String]
        /// Claimed by an installed, open, or registered app: the same ID, or one inside the other (an app's helper).
        func claims(_ id: String, _ r: Roots) -> Bool {
            let lower = id.lowercased()
            if r.running.contains(id) || r.registered(id) { return true }
            return ids.contains { a in let l = a.lowercased(); return l == lower || l.hasPrefix(lower + ".") || lower.hasPrefix(l + ".") }
        }
    }

    static func installedApps(_ r: Roots) -> Installed? {
        let fm = FileManager.default
        guard let first = r.applications.first, let top = try? fm.contentsOfDirectory(atPath: first) else { return nil }
        var paths: [String] = []
        for root in r.applications {
            let names = root == first ? top : ((try? fm.contentsOfDirectory(atPath: root)) ?? [])
            for n in names {
                let p = root + "/" + n
                if n.hasSuffix(".app") { paths.append(p); continue }
                // a vendor's folder of apps, or Utilities, one level down
                var dir: ObjCBool = false
                if fm.fileExists(atPath: p, isDirectory: &dir), dir.boolValue {
                    for m in (try? fm.contentsOfDirectory(atPath: p)) ?? [] where m.hasSuffix(".app") { paths.append(p + "/" + m) }
                }
            }
        }
        return Installed(ids: Set(paths.compactMap { Bundle(path: $0)?.bundleIdentifier }), paths: paths)
    }

    /// Not touched for a month: its own date and every item one level inside it.
    static func quiet(_ path: String, _ r: Roots, days: Double = 30) -> Bool {
        let fm = FileManager.default
        let cutoff = r.now.addingTimeInterval(-days * 86_400)
        func old(_ p: String) -> Bool { ((try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date).map { $0 < cutoff } ?? false }
        guard old(path) else { return false }
        return ((try? fm.contentsOfDirectory(atPath: path)) ?? []).allSatisfy { old(path + "/" + $0) }
    }

    /// Looks like a bundle ID (reverse DNS): "com.spotify.client", not "Google" or "Homebrew", and never Apple's.
    static func looksLikeID(_ name: String) -> Bool {
        name.split(separator: ".").count >= 2 && !name.contains(" ") && !name.lowercased().hasPrefix("com.apple.")
    }

    // MARK: Quick clean

    /// A background helper whose program is gone can't start anything, so removing it changes nothing. Only the person's
    /// own LaunchAgents folder (the shared folders need a password). Not: Apple's labels, helpers started through an app
    /// bundle (BundleProgram) or by an interpreter or `open` (the program isn't the first argument), or programs on
    /// another disk (it may just be unplugged).
    static let interpreters: Set<String> = ["sh", "bash", "zsh", "csh", "tcsh", "dash", "env", "open", "osascript", "python",
                                            "python3", "perl", "ruby", "node", "java"]
    static func missingProgram(_ plist: [String: Any]) -> String? {
        guard let label = plist["Label"] as? String, !label.lowercased().hasPrefix("com.apple."), plist["BundleProgram"] == nil else { return nil }
        guard let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first,
              program.hasPrefix("/"), !program.hasPrefix("/Volumes/"),
              !interpreters.contains((program as NSString).lastPathComponent) else { return nil }
        return FileManager.default.fileExists(atPath: program) ? nil : program
    }

    static func brokenAgents(_ r: Roots) -> [Find] {
        let folder = r.home + "/Library/LaunchAgents"
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted().compactMap { name in
            guard name.hasSuffix(".plist") else { return nil }
            let path = folder + "/" + name
            guard let d = NSDictionary(contentsOfFile: path) as? [String: Any], missingProgram(d) != nil,
                  let label = d["Label"] as? String else { return nil }
            return Find(id: "agent:" + label, group: .quick, title: "\(helperName(label))'s background helper",
                        detail: "It starts a program that's been deleted, so it does nothing.", bytes: nil,
                        paths: [path], agentLabel: label)
        }
    }

    /// A readable name from a label: the part after the vendor's domain ("com.dropbox.DropboxMacUpdate.agent" → "Dropbox").
    static func helperName(_ label: String) -> String {
        let parts = label.split(separator: ".").map(String.init)
        let vendor = parts.count >= 2 ? parts[1] : label
        return vendor.prefix(1).uppercased() + vendor.dropFirst()
    }

    /// Log files and crash reports in the person's own Logs folder, not written for 30 days: apps only ever read their
    /// newest. Shown only when they add up to a megabyte.
    static func oldLogs(_ r: Roots) -> [Find] {
        let folder = r.home + "/Library/Logs"
        let cutoff = r.now.addingTimeInterval(-30 * 86_400)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys) else { return [] }
        var paths: [String] = [], total: UInt64 = 0
        for case let u as URL in e {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                  let d = v.contentModificationDate, d < cutoff else { continue }
            paths.append(u.path); total += UInt64(v.totalFileAllocatedSize ?? 0)
        }
        guard total >= 1_000_000 else { return [] }
        return [Find(id: "logs", group: .quick, title: "Logs and crash reports over 30 days old",
                     detail: "Apps only ever read their newest ones.", bytes: total, paths: paths)]
    }

    /// Windows macOS saved so an app could reopen them, for apps that are gone and not opened for a month.
    static func savedState(_ r: Roots, apps: Installed?) -> [Find] {
        guard let apps else { return [] }
        let folder = r.home + "/Library/Saved Application State"
        var paths: [String] = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted() where name.hasSuffix(".savedState") {
            let id = String(name.dropLast(".savedState".count))
            let path = folder + "/" + name
            guard looksLikeID(id), !apps.claims(id, r), quiet(path, r) else { continue }
            paths.append(path)
        }
        guard !paths.isEmpty else { return [] }
        let bytes = paths.compactMap { Leftovers.size(of: $0) }.reduce(0, +)
        return [Find(id: "saved-state", group: .quick, title: "Saved windows of deleted apps",
                     detail: "Kept so an app reopens its windows, but these apps are gone.", bytes: bytes, paths: paths)]
    }

    // MARK: Deep clean, ticked: rebuilds itself

    /// Worth offering: at least 100 MB.
    public static let worthClearing: UInt64 = 100_000_000

    static func rebuilds(_ r: Roots) -> [Find] {
        let h = r.home
        let items: [(id: String, title: String, detail: String, path: String, app: (id: String, name: String)?)] = [
            ("deriveddata", "Xcode's build data", "Xcode rebuilds it, so each project's next build takes longer.",
             h + "/Library/Developer/Xcode/DerivedData", ("com.apple.dt.Xcode", "Xcode")),
            ("homebrew", "Homebrew's downloads", "Downloaded again the next time they're needed, which needs the internet.",
             h + "/Library/Caches/Homebrew", nil),
            ("npm", "npm's downloads", "Downloaded again the next time they're needed, which needs the internet.",
             h + "/.npm/_cacache", nil),
            ("chrome-cache", "Chrome's cache", "Pages load a little slower once. Bookmarks, passwords, and sign-ins aren't touched.",
             h + "/Library/Caches/Google/Chrome", ("com.google.Chrome", "Chrome")),
        ]
        return items.compactMap { i in
            guard let bytes = Leftovers.size(of: i.path), bytes >= worthClearing else { return nil }
            let blocked = i.app.flatMap { r.running.contains($0.id) ? "\($0.name) is open" : nil }
            // what's inside goes; the folder stays, as each tool expects
            let inside = ((try? FileManager.default.contentsOfDirectory(atPath: i.path)) ?? []).map { i.path + "/" + $0 }
            return Find(id: i.id, group: .rebuilds, title: i.title, detail: i.detail, bytes: bytes, blocked: blocked, paths: inside)
        }
    }

    // MARK: Deep clean, not ticked: check these first

    /// Settings panes in the System Settings sidebar whose developer has nothing else on this Mac: no app, no helper, no
    /// driver, nothing signed by the same developer. "Intel-only" and "unsigned" aren't signs of a left-behind pane (both
    /// real panes on the Mac this was built on are Intel-only, one unsigned, and both their apps are installed). Always
    /// Caution: some panes are the whole product, with no app.
    static func panes(_ r: Roots, apps: Installed?) -> [Find] {
        guard let apps else { return [] }
        var out: [Find] = []
        let folders = [(r.home + "/Library/PreferencePanes", false)] + (r.enrolled ? [] : [(r.library + "/PreferencePanes", true)])
        var teams: Set<String>?
        let others = vendorItems(r)
        for (folder, shared) in folders {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted() where name.hasSuffix(".prefPane") {
                let path = folder + "/" + name
                guard let id = Bundle(path: path)?.bundleIdentifier, looksLikeID(id), Disguise.signer(path) != .apple else { continue }
                let parts = id.lowercased().split(separator: ".").map(String.init)
                let vendor = parts.prefix(2).joined(separator: ".")
                if apps.claims(id, r) || apps.ids.contains(where: { $0.lowercased().hasPrefix(vendor + ".") }) { continue }
                // a helper, driver, or support folder from the same developer, by its domain or its name ("telestream")
                if others.contains(where: { $0.hasPrefix(vendor + ".") || $0.hasPrefix(parts[1]) }) { continue }
                if let t = teamID(path) {
                    if teams == nil { teams = Set(apps.paths.compactMap(teamID)) }
                    if teams!.contains(t) { continue }
                }
                out.append(Find(id: "pane:" + id, group: .check, title: "\((name as NSString).deletingPathExtension) settings pane",
                                detail: "In the System Settings sidebar, but nothing else from its developer is on this Mac. Keep it if you still use what it set up.",
                                bytes: Leftovers.size(of: path), caution: true, needsAdmin: shared, paths: [path]))
            }
        }
        return out
    }

    /// Names of what a developer installs besides apps: helpers, drivers, file systems, support folders (lower-cased).
    static func vendorItems(_ r: Roots) -> [String] {
        let fm = FileManager.default
        let folders = [r.home + "/Library/LaunchAgents", r.home + "/Library/Application Support",
                       r.library + "/LaunchAgents", r.library + "/LaunchDaemons", r.library + "/PrivilegedHelperTools",
                       r.library + "/Extensions", r.library + "/Filesystems", r.library + "/Audio/Plug-Ins/HAL",
                       r.library + "/Application Support"]
        return folders.flatMap { (try? fm.contentsOfDirectory(atPath: $0)) ?? [] }.map { $0.lowercased() }
    }

    /// The developer's Team ID from a bundle's code signature; nil when unsigned.
    static func teamID(_ path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return nil }
        return d[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Caches folders named for an app that's gone, not touched for a month, at least 50 MB. Never Containers, Group
    /// Containers, or Application Support: those can hold documents (and reading them makes macOS ask).
    static func orphanCaches(_ r: Roots, apps: Installed?) -> [Find] {
        guard let apps else { return [] }
        let folder = r.home + "/Library/Caches"
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted().compactMap { id in
            let path = folder + "/" + id
            guard looksLikeID(id), !apps.claims(id, r), quiet(path, r), let bytes = Leftovers.size(of: path), bytes >= 50_000_000 else { return nil }
            return Find(id: "caches:" + id, group: .check, title: "Caches of \(id)",
                        detail: "No app on this Mac uses this name. If the app comes back, it makes these again.",
                        bytes: bytes, caution: true, paths: [path])
        }
    }

    /// macOS installers older than the macOS this Mac runs. Apple lets you download them again; some people keep one to
    /// make a startup disk. Not offered on a managed Mac.
    static let macOSNames: [String: Int] = ["Big Sur": 11, "Monterey": 12, "Ventura": 13, "Sonoma": 14, "Sequoia": 15, "Tahoe": 26]
    static func oldInstallers(_ r: Roots) -> [Find] {
        guard !r.enrolled, let folder = r.applications.first else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted().compactMap { name in
            guard name.hasPrefix("Install macOS "), name.hasSuffix(".app") else { return nil }
            let release = String(name.dropFirst("Install macOS ".count).dropLast(4))
            guard let major = macOSNames[release], major < r.macOSMajor else { return nil }
            let path = folder + "/" + name
            return Find(id: "install:" + release, group: .check, title: (name as NSString).deletingPathExtension,
                        detail: "This Mac runs a newer macOS, and Apple lets you download it again. Keep it if you make startup disks from it.",
                        bytes: Leftovers.size(of: path), needsAdmin: true, paths: [path])
        }
    }

    // MARK: Downloads, only when the person chooses the folder

    /// In a folder the person chose: identical second downloads ("Report (1).pdf" beside "Report.pdf"), which go in Quick
    /// clean because the other copy stays; and installers (.dmg, .pkg) not changed for 30 days and not open now, which
    /// Cool Head can't tell are installed, so they're for the person to check.
    public static func scanDownloads(_ folder: String, now: Date = Date(), mounted: Set<String>? = nil) -> [Find] {
        let fm = FileManager.default
        let open = mounted ?? mountedImages()
        let names = Set((try? fm.contentsOfDirectory(atPath: folder)) ?? [])
        var out: [Find] = []
        for name in names.sorted() {
            let path = folder + "/" + name
            guard let a = try? fm.attributesOfItem(atPath: path), a[.type] as? FileAttributeType == .typeRegular else { continue }
            let size = (a[.size] as? NSNumber)?.uint64Value ?? 0
            if let original = secondDownload(name), names.contains(original),
               fm.contentsEqual(atPath: path, andPath: folder + "/" + original) {
                out.append(Find(id: "copy:" + name, group: .quick, title: name,
                                detail: "An identical second download of \(original), which stays.", bytes: size, paths: [path]))
                continue
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if ["dmg", "pkg", "mpkg"].contains(ext), !open.contains(path),
               let d = a[.modificationDate] as? Date, now.timeIntervalSince(d) > 30 * 86_400 {
                out.append(Find(id: "download:" + name, group: .check, title: name,
                                detail: "An installer downloaded \(Int(now.timeIntervalSince(d) / 86_400)) days ago. You can download it again if you need it.",
                                bytes: size, caution: true, paths: [path]))
            }
        }
        return out
    }

    /// "Report (1).pdf" → "Report.pdf", the name a browser gives a second download; nil for any other name.
    static func secondDownload(_ name: String) -> String? {
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        guard let r = base.range(of: #" \(\d+\)$"#, options: .regularExpression) else { return nil }
        let original = String(base[..<r.lowerBound])
        return ext.isEmpty ? original : original + "." + ext
    }

    /// Disk images open now (`hdiutil info`), so one in use is never offered.
    public static func mountedImages() -> Set<String> {
        guard let data = Hardware.run("/usr/bin/hdiutil", ["info", "-plist"]),
              let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = d["images"] as? [[String: Any]] else { return [] }
        return Set(images.compactMap { $0["image-path"] as? String })
    }

    // MARK: moving to the Trash, and back

    /// What Cool Head moved, so it can put each back: the original path and where it is in the Trash. Kept in Cool Head's
    /// own settings until the item leaves the Trash (put back, or the Trash emptied).
    public struct Moved: Codable, Equatable, Hashable {
        public let from: String
        public let to: String
        public let admin: Bool
        public let at: Date
        /// Its size when it moved, for "Moved 3 items (1.2 GB)"; nil in lists saved before sizes were kept.
        public var bytes: UInt64? = nil
    }

    /// Space a file or folder takes; a link counts as itself, not what it points to. Nil when it isn't there.
    public static func size(_ path: String) -> UInt64? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        if a[.type] as? FileAttributeType == .typeDirectory { return Leftovers.size(of: path) }
        return (a[.size] as? NSNumber)?.uint64Value
    }
    public static let movedKey = "cleanerMoved"

    public static func movedList(_ defaults: UserDefaults = .standard) -> [Moved] {
        let all = defaults.data(forKey: movedKey).flatMap { try? JSONDecoder().decode([Moved].self, from: $0) } ?? []
        return all.filter { FileManager.default.fileExists(atPath: $0.to) }
    }
    static func remember(_ items: [Moved], _ defaults: UserDefaults = .standard) {
        let all = Array((movedList(defaults) + items).suffix(200))
        defaults.set(try? JSONEncoder().encode(all), forKey: movedKey)
    }
    static func forget(_ item: Moved, _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(movedList(defaults).filter { $0 != item }), forKey: movedKey)
    }

    /// Safe to move: still there, inside one of the places a scan reads once every link on the way is followed (a link
    /// planted in a scanned folder can't lead the move somewhere else), and never in macOS's own folders. A link that is
    /// itself the item moves as a link: its target stays where it is (Homebrew's cache is mostly links).
    static func safe(_ path: String, home: String, library: String = "/Library", applications: String = "/Applications") -> Bool {
        guard !path.contains("/../"), (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return false }
        func real(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        let parent = real((path as NSString).deletingLastPathComponent) + "/"
        if parent.hasPrefix("/System/") || parent.hasPrefix(real(library) + "/Apple/") { return false }
        let roots = [real(home) + "/Library/", real(home) + "/.npm/", real(home) + "/Downloads/", real(library) + "/PreferencePanes/"]
        if roots.contains(where: { parent.hasPrefix($0) }) { return true }
        // a macOS installer sits directly in Applications
        return parent == real(applications) + "/" && (path as NSString).lastPathComponent.hasPrefix("Install macOS ")
    }

    /// Moves a find's files to the Trash, after stopping its helper; what moved, for Put back, and what didn't. Items
    /// that need a password aren't moved here (the app runs them as a one-shot job).
    public static func trash(_ f: Find, home: String = NSHomeDirectory(), defaults: UserDefaults = .standard) -> (moved: [Moved], failed: [String]) {
        guard !f.needsAdmin else { return ([], f.paths) }
        if let label = f.agentLabel { BackgroundAgents.launchctl(["bootout", "\(BackgroundAgents.domain)/\(label)"]) }
        var moved: [Moved] = [], failed: [String] = []
        for p in f.paths {
            guard safe(p, home: home) else { failed.append(p); continue }
            var to: NSURL?
            let bytes = size(p)
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: &to)
                if let u = to as URL? { moved.append(Moved(from: p, to: u.path, admin: false, at: Date(), bytes: bytes)) }
            } catch { failed.append(p) }
        }
        remember(moved, defaults)
        return (moved, failed)
    }

    /// Puts an item back where it was, if nothing has taken its place. Items moved with a password need one to go back,
    /// so those are left to Finder.
    @discardableResult
    public static func putBack(_ m: Moved, defaults: UserDefaults = .standard) -> Bool {
        guard !m.admin, !FileManager.default.fileExists(atPath: m.from),
              (try? FileManager.default.moveItem(atPath: m.to, toPath: m.from)) != nil else { return false }
        forget(m, defaults)
        return true
    }

    /// For the one-shot job: where in the person's Trash each item needing a password goes (a free name).
    public static func adminMoves(_ f: Find, home: String = NSHomeDirectory()) -> [(from: String, to: String)] {
        guard f.needsAdmin else { return [] }
        return f.paths.filter { safe($0, home: home) }.map { p in
            let name = (p as NSString).lastPathComponent
            var to = home + "/.Trash/" + name, n = 2
            while FileManager.default.fileExists(atPath: to) {
                to = home + "/.Trash/" + (name as NSString).deletingPathExtension + " \(n)." + (name as NSString).pathExtension; n += 1
            }
            return (p, to)
        }
    }
    /// The job's command: each name passed as its own argument, never parsed by the shell (`sh -c '…' sh from to …`).
    public static func adminArguments(_ moves: [(from: String, to: String)]) -> [String] {
        ["/bin/sh", "-c", "while [ $# -ge 2 ]; do /bin/mv -n \"$1\" \"$2\"; shift 2; done", "sh"] + moves.flatMap { [$0.from, $0.to] }
    }
    /// What the job moved, with each item's size measured before it moved (`sizes`, by original path).
    @discardableResult
    public static func rememberAdmin(_ moves: [(from: String, to: String)], sizes: [String: UInt64] = [:], defaults: UserDefaults = .standard) -> [Moved] {
        let done = moves.filter { FileManager.default.fileExists(atPath: $0.to) }.map { Moved(from: $0.from, to: $0.to, admin: true, at: Date(), bytes: sizes[$0.from]) }
        remember(done, defaults)
        return done
    }

    /// Under this, an item folds with the other small ones (Phil, 18 November 2026: "I think we should group items under
    /// 50MB by default and have an expand button").
    public static let smallItem: UInt64 = 50_000_000

    /// A list split into what shows and what folds into one line: items under 50 MB (or of no known size) fold when
    /// there are two or more of them; one alone shows, since its line would take the same room.
    public static func split<T>(_ items: [T], bytes: (T) -> UInt64?) -> (shown: [T], folded: [T]) {
        let small = items.filter { (bytes($0) ?? 0) < smallItem }
        guard small.count >= 2 else { return (items, []) }
        return (items.filter { (bytes($0) ?? 0) >= smallItem }, small)
    }

    /// The folded line: "17 smaller items under 50 MB each, 87 MB in total", and in Deep clean how many are ticked.
    public static func foldedLine(_ n: Int, bytes: UInt64, ticked: Int = 0) -> String {
        "\(n) smaller items under 50 MB each" + (bytes > 0 ? ", \(Fmt.fileSize(bytes)) in total" : "") + (ticked > 0 ? "; \(ticked) ticked" : "")
    }

    /// "3 items (1.2 GB)", or "1 item" when no size is known: what a count of moved things says, everywhere it's shown.
    public static func count(_ n: Int, bytes: UInt64) -> String {
        (n == 1 ? "1 item" : "\(n) items") + (bytes > 0 ? " (\(Fmt.fileSize(bytes)))" : "")
    }

    // MARK: made-up finds, for screenshots (COOLHEAD_SNAPSHOT_CLEANER), never this Mac's

    /// Made-up things Cool Head moved, for screenshots of the list it can put back.
    public static func sampleMoved(now: Date = Date()) -> [Moved] {
        [Moved(from: "/Users/you/Library/Logs/Example", to: "/Users/you/.Trash/Example", admin: false, at: now, bytes: 270_000_000),
         Moved(from: "/Users/you/Downloads/Report (1).pdf", to: "/Users/you/.Trash/Report (1).pdf", admin: false, at: now, bytes: 2_400_000),
         Moved(from: "/Users/you/Library/LaunchAgents/com.example.helper.plist", to: "/Users/you/.Trash/com.example.helper.plist", admin: false, at: now, bytes: 612)]
    }

    public static func sample() -> [Find] {
        [
            Find(id: "agent:com.dropbox.DropboxMacUpdate.agent", group: .quick, title: "Dropbox's background helper",
                 detail: "It starts a program that's been deleted, so it does nothing.", bytes: nil),
            Find(id: "logs", group: .quick, title: "Logs and crash reports over 30 days old",
                 detail: "Apps only ever read their newest ones.", bytes: 270_000_000),
            Find(id: "saved-state", group: .quick, title: "Saved windows of deleted apps",
                 detail: "Kept so an app reopens its windows, but these apps are gone.", bytes: 12_000_000),
            Find(id: "copy:Report (1).pdf", group: .quick, title: "Report (1).pdf",
                 detail: "An identical second download of Report.pdf, which stays.", bytes: 2_400_000),
            Find(id: "deriveddata", group: .rebuilds, title: "Xcode's build data",
                 detail: "Xcode rebuilds it, so each project's next build takes longer.", bytes: 6_100_000_000),
            Find(id: "homebrew", group: .rebuilds, title: "Homebrew's downloads",
                 detail: "Downloaded again the next time they're needed, which needs the internet.", bytes: 2_000_000_000),
            Find(id: "chrome-cache", group: .rebuilds, title: "Chrome's cache",
                 detail: "Pages load a little slower once. Bookmarks, passwords, and sign-ins aren't touched.",
                 bytes: 1_800_000_000, blocked: "Chrome is open"),
            Find(id: "pane:com.telestream.flip4mac", group: .check, title: "Flip4Mac WMV settings pane",
                 detail: "In the System Settings sidebar, but nothing else from its developer is on this Mac. Keep it if you still use what it set up.",
                 bytes: 18_000_000, caution: true, needsAdmin: true),
            Find(id: "pane:com.growl.prefpanel", group: .check, title: "Growl settings pane",
                 detail: "In the System Settings sidebar, but nothing else from its developer is on this Mac. Keep it if you still use what it set up.",
                 bytes: 9_000_000, caution: true),
            Find(id: "caches:com.spotify.client", group: .check, title: "Caches of com.spotify.client",
                 detail: "No app on this Mac uses this name. If the app comes back, it makes these again.",
                 bytes: 640_000_000, caution: true),
            Find(id: "install:Sequoia", group: .check, title: "Install macOS Sequoia",
                 detail: "This Mac runs a newer macOS, and Apple lets you download it again. Keep it if you make startup disks from it.",
                 bytes: 14_900_000_000, needsAdmin: true),
        ]
    }
}

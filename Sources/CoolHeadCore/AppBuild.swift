import AppKit
import Darwin
import Foundation

/// What a busy app is built on, where that matters on this macOS (research rules 19 and 20).
///
/// - **Rosetta (rule 20).** An Intel-only app runs translated through Rosetta. All Intel software except legacy games
///   won't open in macOS 28; on 27, Settings ▸ General lists the Intel apps affected, and "Open using Rosetta" is
///   ignored (Apple, macOS 27 release notes; MacRumors and AppleInsider on Apple's timeline). A universal app set to
///   "Open using Rosetta" on 26 runs translated though it needn't. Translation is read from the kernel's process flags
///   (P_TRANSLATED, readable for every process); Intel-only from the program file's own header.
/// - **Old Electron (rule 19).** On macOS 26.0 and 26.1, apps built on Electron older than 36.9.2, 37.6.0, 38.2.0 or
///   39.0.0 made WindowServer's graphics work hard and lagged the whole Mac (Electron PR 48376; Michael Tsai; The
///   Register; AppleInsider). Read from the app's Electron Framework version; said only on those macOS versions.
public enum AppBuild {
    public enum Rosetta: Equatable {
        case intelOnly          // only an Intel build: runs through Rosetta
        case setToRosetta       // has an Apple silicon build, but runs translated ("Open using Rosetta")
    }

    /// What is known about one busy app, and the apps with an old Electron for a busy WindowServer.
    public struct Facts: Equatable {
        public var rosetta: Rosetta?
        public var oldElectron: [String] = []
        /// The macOS major and minor version these facts are judged on.
        public var macOS: (major: Int, minor: Int) = (0, 0)
        public init(rosetta: Rosetta? = nil, oldElectron: [String] = [], macOS: (major: Int, minor: Int) = AppBuild.macOS) {
            self.rosetta = rosetta; self.oldElectron = oldElectron; self.macOS = macOS
        }
        public static func == (a: Facts, b: Facts) -> Bool { a.rosetta == b.rosetta && a.oldElectron == b.oldElectron && a.macOS == b.macOS }
    }

    public static var macOS: (major: Int, minor: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion)
    }

    // MARK: Rosetta

    /// Running translated, from the kernel's flags for the process (P_TRANSLATED); nil where it can't be read.
    public static func translated(_ pid: pid_t) -> Bool? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_proc.p_flag & 0x0002_0000 != 0
    }

    /// The processor types a program file is built for, from its own header: "x86_64", "arm64", or both.
    public static func architectures(_ path: String) -> Set<String> {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        return architectures(header: h.readData(ofLength: 4096))
    }

    public static func architectures(header d: Data) -> Set<String> {
        func be(_ at: Int) -> UInt32 { at + 4 <= d.count ? d[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) } : 0 }
        func le(_ at: Int) -> UInt32 { at + 4 <= d.count ? d[at..<at + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } : 0 }
        func name(_ cpu: UInt32) -> String? { cpu == 0x0100_0007 ? "x86_64" : cpu == 0x0100_000C ? "arm64" : nil }
        let magic = be(0)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {          // universal: a list of builds, big-endian
            let n = Int(be(4)), step = magic == 0xCAFE_BABE ? 20 : 32
            guard n < 16 else { return [] }                         // Java class files share the magic number
            return Set((0..<n).compactMap { name(be(8 + $0 * step)) })
        }
        if le(0) == 0xFEED_FACF || le(0) == 0xFEED_FACE { return Set([name(le(4))].compactMap { $0 }) }
        return []
    }

    /// For a busy process: an Intel-only app, or a universal one running translated; nil for anything else.
    public static func rosetta(translated: Bool?, architectures: Set<String>) -> Rosetta? {
        if architectures == ["x86_64"] { return .intelOnly }
        if translated == true && architectures.contains("arm64") { return .setToRosetta }
        return nil
    }

    /// For a busy app on this Mac (nothing for macOS's own programs); the program's header is read once per file.
    public static func facts(_ e: Evidence, isWindowServer: Bool) -> Facts? {
        var f = Facts()
        if e.script == nil, let p = e.path, !CaseReport.isMacOS(p), e.appBundle != nil {
            let archs = archCache.with { c in c[p] ?? { let a = architectures(p); c[p] = a; return a }() }
            f.rosetta = rosetta(translated: translated(e.pid), architectures: archs)
        }
        if isWindowServer {
            f.oldElectron = oldElectron(running: NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL?.path },
                                        macOS: f.macOS)
        }
        return f.rosetta == nil && f.oldElectron.isEmpty ? nil : f
    }
    static let archCache = Locked<[String: Set<String>]>([:])

    // MARK: Electron

    /// The version of Electron inside an app, from its framework's own details; nil when it isn't built on Electron.
    public static func electronVersion(app bundle: String) -> String? {
        let plist = bundle + "/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist"
        guard let d = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleVersion"] as? String
    }

    /// Older than the fix for macOS 26's lag: 36.9.2, 37.6.0, 38.2.0, or any 39 and later.
    public static func electronLags(_ version: String) -> Bool {
        let p = version.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        let fixed: [Int: [Int]] = [36: [36, 9, 2], 37: [37, 6, 0], 38: [38, 2, 0]]
        if p[0] >= 39 { return false }
        guard let f = fixed[p[0]] else { return true }              // 35 and earlier never got the fix
        return p.prefix(3).lexicographicallyPrecedes(f)
    }

    /// The macOS versions the Electron lag affects: 26.0 and 26.1.
    public static func electronWindow(_ v: (major: Int, minor: Int)) -> Bool { v.major == 26 && v.minor < 2 }

    /// Running apps with an Electron that lags this macOS (only read on 26.0 and 26.1), by name.
    public static func oldElectron(running bundles: [String], macOS v: (major: Int, minor: Int) = macOS) -> [String] {
        guard electronWindow(v) else { return [] }
        return bundles.filter { electronVersion(app: $0).map(electronLags) == true }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }.sorted()
    }

    // MARK: the card

    static let systemSettings = "/System/Applications/System Settings.app"

    /// What is added to a busy app's card: a sentence, and an option. On 27, Apple's own list in Settings is the place
    /// to look; before it, a search for the developer's Apple silicon version. Nothing for macOS's own programs.
    public static func addition(_ f: Facts, app: String) -> (sentence: String, fix: Fix)? {
        switch f.rosetta {
        case .intelOnly:
            if f.macOS.major >= 27 {
                return (" It's an Intel app, so it won't open in macOS 28; Settings lists the Intel apps affected.",
                        Fix.openApp("intel", "See which Intel apps are affected", bundle: systemSettings,
                                    steps: "Choose General. macOS lists the Intel apps that won't open in macOS 28."))
            }
            return (" It's an Intel app, running through Rosetta, and it won't open in macOS 28.",
                    Fix(id: "intel", title: "Look for an Apple silicon version", consequence: "Search the web for “\(app) Apple silicon”.",
                        kind: .lookUp("\(app) Apple silicon")))
        case .setToRosetta:
            guard f.macOS.major < 27 else { return nil }            // 27 ignores the setting and runs it natively
            return (" It's set to open using Rosetta, so it runs translated though it has an Apple silicon version.",
                    Fix.guide("native", "Run it natively", "Turns off Open using Rosetta.",
                              steps: ["Quit \(app).", "In Finder, select \(app) and choose \(Fmt.path("File", "Get Info")).", "Turn off \(Fmt.ui("Open using Rosetta")), then open it again."]))
        case nil:
            return nil
        }
    }

    /// For a busy WindowServer: the apps whose old Electron makes macOS 26.0 and 26.1 work it hard.
    public static func electronAddition(_ f: Facts) -> (sentence: String, fix: Fix)? {
        guard electronWindow(f.macOS), !f.oldElectron.isEmpty else { return nil }
        let n = f.oldElectron
        let names = Fmt.list(n)
        let them = f.oldElectron.count == 1 ? "it" : "them"
        return (" \(names) \(f.oldElectron.count == 1 ? "is" : "are") built on an older Electron that makes macOS \(f.macOS.major).\(f.macOS.minor) draw slowly: update \(them).",
                Fix.guide("electron", "Update \(names)", "Newer versions fix the slowdown.",
                          steps: ["Open \(names).", "Check for updates in \(f.oldElectron.count == 1 ? "its" : "each one's") menu, or download the latest version from its developer."],
                          recommended: true).fixingTheCause())
    }
}


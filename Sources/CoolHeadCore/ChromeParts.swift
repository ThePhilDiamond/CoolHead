import Foundation

/// Chrome's memory by part, read from outside with no permission: tabs Chrome marks as hidden, tabs on screen, Chrome's
/// own program, and its graphics process, and when Chrome was opened (the Chrome plan's fourth stage: advice that needs
/// nothing installed; Phil, 21 November 2026: "Do it all").
///
/// Chrome puts a tab process with nothing on screen in macOS's background band (scheduling priority 4; research node
/// N-029 F1), and Cool Head already reads that priority for Run it cooler (Proc.schedulingPriority). Seen on Phil's Mac,
/// 21 November 2026: 9 tab processes at 4, others at 46, 47, and 97. So the memory of the processes at 4 is memory in tabs
/// the person isn't looking at, which unloading or closing those tabs gives back without touching the one they're on.
/// Known errors, said in Nerdy stuff: a hidden tab playing sound or using the camera stays out of the band, and several
/// tabs of one site can share a process.
public struct ChromeParts: Equatable {
    public var hiddenBytes: UInt64 = 0
    public var hiddenCount = 0
    public var shownBytes: UInt64 = 0
    public var shownCount = 0
    public var extensionBytes: UInt64 = 0        // Chrome's extensions, each in its own process
    public var extensionCount = 0
    public var browserBytes: UInt64 = 0          // Chrome's own program, the process with no --type
    public var gpuBytes: UInt64 = 0
    public var openSince: Date?                  // when Chrome's own program started
    public init() {}

    /// Believable only when Chrome is setting the mark here: some tab processes in the band and some out of it.
    public var markWorks: Bool { hiddenCount > 0 && shownCount > 0 }

    public struct Process {
        public let path: String?
        public let args: [String]
        public let footprint: UInt64
        public let priority: Int?
        public let start: Date?
        public let cooled: Bool                  // slowed by Cool Head's own Run it cooler, which puts it at 4 too
        public init(path: String?, args: [String], footprint: UInt64, priority: Int?, start: Date?, cooled: Bool = false) {
            self.path = path; self.args = args; self.footprint = footprint; self.priority = priority; self.start = start; self.cooled = cooled
        }
    }

    public static let hiddenPriority = 4
    /// Hidden tabs worth a sentence on the card, and worth closing tab groups for.
    public static let worthSaying: UInt64 = 500_000_000
    public static let worthGroups: UInt64 = 1_000_000_000
    /// Chrome's own program or its graphics process this big has grown, and only a restart gives that back (research
    /// node N-025 F4); open this long, a restart is worth mentioning (inferred thresholds, no source gives numbers).
    public static let grown: UInt64 = 2_000_000_000
    public static let openLong: TimeInterval = 3 * 24 * 3600

    /// Pure, for the selftest. `bundle`: Chrome's app path.
    public static func read(_ procs: [Process], bundle: String) -> ChromeParts {
        var p = ChromeParts()
        for pr in procs {
            guard let path = pr.path, path.hasPrefix(bundle + "/") else { continue }
            let type = pr.args.first { $0.hasPrefix("--type=") }
            switch type {
            case nil where path.hasSuffix("/Contents/MacOS/Google Chrome"):
                p.browserBytes += pr.footprint
                p.openSince = pr.start
            case "--type=gpu-process":
                p.gpuBytes += pr.footprint
            case "--type=renderer" where pr.args.contains("--extension-process"):
                p.extensionBytes += pr.footprint; p.extensionCount += 1
            case "--type=renderer" where !pr.args.contains("--pdf-renderer"):
                if let pri = pr.priority, pri <= hiddenPriority, !pr.cooled { p.hiddenBytes += pr.footprint; p.hiddenCount += 1 }
                else { p.shownBytes += pr.footprint; p.shownCount += 1 }
            default: break
            }
        }
        return p
    }

    /// For Chrome's memory card.
    public var hiddenSentence: String? {
        guard markWorks, hiddenBytes >= ChromeParts.worthSaying else { return nil }
        return "About \(Fmt.bytes(hiddenBytes)) of Chrome's memory is in tabs you aren't looking at, so closing those gives it back without touching the tab you're on."
    }

    /// Extensions hold memory unloading tabs never reaches: on Phil's Mac, 21 November 2026, 19 extension processes held
    /// 1.6 GB of Chrome's 5.6 GB (29%), against 54% in tabs (Phil: "I want to make sure we're not just dealing with one
    /// tiny subsection of the problem"). Cool Head can't tell which extension is which from outside; Chrome's Task
    /// Manager names each, with its memory.
    public static let extensionsWorthSaying: UInt64 = 500_000_000
    public var extensionSentence: String? {
        guard extensionBytes >= ChromeParts.extensionsWorthSaying else { return nil }
        return "Chrome's extensions are using \(Fmt.bytes(extensionBytes)), which closing tabs doesn't give back."
    }

    /// For Nerdy stuff: the evidence, and its known errors.
    public var facts: [String] {
        let ext = extensionCount > 0 ? ["Chrome's extensions: \(Fmt.bytes(extensionBytes)) in \(extensionCount) \(extensionCount == 1 ? "process" : "processes")."] : []
        guard markWorks else { return ext }
        return ext + ["Chrome's tabs: \(Fmt.bytes(hiddenBytes)) in \(hiddenCount) processes Chrome marks as hidden, \(Fmt.bytes(shownBytes)) in \(shownCount) on screen or busy. A hidden tab playing sound or using the camera counts as on screen, and tabs of one site can share a process."]
    }

    /// Chrome's own program or graphics process has grown: the one kind of memory only a restart gives back.
    public var grownPart: (name: String, bytes: UInt64)? {
        if browserBytes >= ChromeParts.grown, browserBytes >= gpuBytes { return ("Chrome's own program", browserBytes) }
        if gpuBytes >= ChromeParts.grown { return ("Chrome's graphics process", gpuBytes) }
        return nil
    }

    public func openFor(now: Date) -> TimeInterval? { openSince.map { now.timeIntervalSince($0) } }
}

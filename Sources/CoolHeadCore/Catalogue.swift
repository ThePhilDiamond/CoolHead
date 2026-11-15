import Foundation

/// The catalogue of known patterns: what a busy process is, whether that is normal, how long is normal, and what to do.
/// Every entry names its source, and has a recorded example in `Fixtures.swift` that `coolhead selftest` checks.
/// See docs/DIAGNOSIS.md for how to add one.
public struct Pattern {
    public enum Symptom: String { case heat, battery, slow, memory, sleep }

    public let id: String
    /// Process names it matches, exactly, ignoring case.
    public var names: [String] = []
    /// Or: part of the executable's path, for apps whose helpers have many names.
    public var pathContains: [String] = []
    public let symptoms: [Symptom]
    /// What it is doing, as the start of a sentence: "Spotlight is indexing your files".
    public let doing: String
    /// When this is expected: "after a macOS update or when many files change".
    public let normal: String
    /// Busy longer than this, it is worth a look.
    public let usualHours: Double
    /// False for things that run until stopped (a virtual machine), so the card doesn't promise an end.
    public var endsOnItsOwn = true
    /// What to do when it has gone on longer than usual.
    public var whenLong: String = "Look it up"
    /// What acting would risk, shown under the action.
    public var risk: String? = nil
    /// Where the claim comes from: an Apple support article, a man page, or a test anyone can repeat.
    public let source: String
    /// True once someone has checked the source says what the entry says (link it in the pull request).
    public var checked = false

    public func matches(name: String, path: String?) -> Bool {
        let n = name.lowercased()
        if names.contains(where: { $0.lowercased() == n }) { return true }
        if let p = path, pathContains.contains(where: { p.contains($0) }) { return true }
        return false
    }

    public static func match(name: String, path: String?) -> Pattern? {
        catalogue.first { $0.matches(name: name, path: path) }
    }
}

extension Pattern {
    public static let catalogue: [Pattern] = [
        Pattern(id: "spotlight", names: ["mds", "mds_stores", "mdworker", "mdworker_shared", "corespotlightd", "mdsync"],
                symptoms: [.heat, .battery], doing: "Spotlight is indexing your files",
                normal: "after a macOS update or when many files change", usualHours: 3,
                risk: "Stopping it only makes macOS start again later.",
                source: "Apple: If Spotlight is slow or indexing; man mds"),
        Pattern(id: "photos-analysis", names: ["photoanalysisd", "mediaanalysisd", "photolibraryd", "mediaanalysisd-access"],
                symptoms: [.heat, .battery], doing: "Photos is analysing your library (faces, objects, text)",
                normal: "after importing photos, mostly while plugged in", usualHours: 6,
                source: "Apple: People and pets in Photos on Mac"),
        Pattern(id: "kernel-task", names: ["kernel_task"], symptoms: [.heat],
                doing: "macOS is keeping the chip cool by holding it idle",
                normal: "when the Mac is hot; it is a symptom, not the cause", usualHours: 1,
                whenLong: "Find what is heating the Mac",
                source: "Apple: If kernel_task is using a large percentage of your Mac CPU"),
        Pattern(id: "windowserver", names: ["WindowServer"], symptoms: [.heat, .battery],
                doing: "macOS is drawing the screen", normal: "with external displays, screen recording or many windows",
                usualHours: 1000, endsOnItsOwn: false, source: "Test: CPU rises with a second display or a screen recording running"),
        Pattern(id: "time-machine", names: ["backupd", "backupd-helper"], symptoms: [.heat, .slow],
                doing: "Time Machine is backing up", normal: "for a while after many files change", usualHours: 3,
                source: "Apple: Back up your Mac with Time Machine"),
        Pattern(id: "icloud-sync", names: ["bird", "cloudd", "nsurlsessiond"], symptoms: [.heat, .battery],
                doing: "iCloud is syncing", normal: "after adding or changing many files in iCloud Drive", usualHours: 3,
                source: "man bird; Test: CPU rises while a large folder uploads to iCloud Drive"),
        Pattern(id: "file-provider", names: ["fileproviderd"], symptoms: [.heat, .battery],
                doing: "A cloud drive (iCloud, Google Drive, Dropbox or OneDrive) is syncing files",
                normal: "after many files change", usualHours: 3,
                source: "Apple developer documentation: File Provider; Test: CPU rises during a cloud drive sync"),
        Pattern(id: "software-update", names: ["softwareupdated", "com.apple.MobileSoftwareUpdate.UpdateBrainService"],
                symptoms: [.heat], doing: "macOS is preparing a software update", normal: "before an update installs",
                usualHours: 2, source: "man softwareupdate"),
        Pattern(id: "security-checks", names: ["trustd", "syspolicyd", "XprotectService", "XProtect", "amfid"],
                symptoms: [.heat], doing: "macOS is checking apps and files for safety",
                normal: "after installing or updating apps", usualHours: 1,
                source: "Apple Platform Security guide: Gatekeeper and XProtect"),
        Pattern(id: "siri-suggestions", names: ["duetexpertd", "coreduetd", "knowledgeconstructiond", "suggestd", "biomesyncd"],
                symptoms: [.heat, .battery], doing: "macOS is learning your habits for Siri suggestions",
                normal: "in short bursts, mostly while idle", usualHours: 1,
                source: "DiagnosticReports: cpu_resource reports name these when they exceed macOS's own CPU limit"),
        Pattern(id: "energy-logging", names: ["PerfPowerServices"], symptoms: [.heat, .battery],
                doing: "macOS is recording energy use", normal: "briefly; it should use very little", usualHours: 0.5,
                source: "Test: should stay under 5% of one core; reports of it stuck at 150% for a day exist"),
        Pattern(id: "crash-report", names: ["ReportCrash", "spindump", "osanalyticshelper"], symptoms: [.heat],
                doing: "macOS is writing a report about an app that crashed or hung", normal: "for a minute after a crash",
                usualHours: 0.25, source: "man ReportCrash; man spindump"),
        Pattern(id: "apple-intelligence", names: ["mlhostd", "modelmanagerd", "intelligenceplatformd", "generativeexperiencesd"],
                symptoms: [.heat, .battery], doing: "Apple Intelligence is running or preparing its on-device models",
                normal: "after an update or when it is in use", usualHours: 2,
                source: "Test: CPU rises after a macOS update while models download and prepare"),
        Pattern(id: "permissions", names: ["tccd"], symptoms: [.heat],
                doing: "macOS is checking app permissions", normal: "briefly, when apps ask for access", usualHours: 0.25,
                source: "man tccd"),
        Pattern(id: "docker-vm", pathContains: ["Docker.app/Contents/", "com.docker."], symptoms: [.heat, .battery, .memory],
                doing: "Docker's virtual machine is running", normal: "while containers run; it keeps running after they stop",
                usualHours: 1000, endsOnItsOwn: false, whenLong: "Quit Docker if no containers are running",
                risk: "Quitting Docker stops every container.",
                source: "Docker Desktop for Mac documentation: resource usage"),
    ]
}

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
    /// When it's normal, as a full sentence, written by hand.
    public let usually: String
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
        // a name alone could be anyone's program; it counts only for macOS's own copy (or when the path is unknown)
        if names.contains(where: { $0.lowercased() == n }) { return path.map(CaseReport.isMacOS) ?? true }
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
                usually: "Spotlight indexes after a macOS update, or when many files change.", usualHours: 3,
                risk: "Stopping it only makes macOS start again later.",
                source: "Apple: If Spotlight is slow or indexing; man mds"),
        Pattern(id: "photos-analysis", names: ["photoanalysisd", "mediaanalysisd", "photolibraryd", "mediaanalysisd-access"],
                symptoms: [.heat, .battery], doing: "Photos is analysing your library (faces, objects, text)",
                usually: "Photos does this after you import photos, mostly while your Mac is plugged in.", usualHours: 6,
                source: "Apple: People and pets in Photos on Mac"),
        Pattern(id: "kernel-task", names: ["kernel_task"], symptoms: [.heat],
                doing: "macOS is keeping the chip cool by holding it idle",
                usually: "macOS does this when your Mac is hot. It's a sign of the heat, not the cause.", usualHours: 1,
                whenLong: "Find what is heating the Mac",
                source: "Apple: If kernel_task is using a large percentage of your Mac CPU"),
        Pattern(id: "windowserver", names: ["WindowServer"], symptoms: [.heat, .battery],
                doing: "macOS is drawing the screen", usually: "It works harder with external displays, screen recording, or many windows open.",
                usualHours: 1000, endsOnItsOwn: false, source: "Test: CPU rises with a second display or a screen recording running"),
        Pattern(id: "time-machine", names: ["backupd", "backupd-helper"], symptoms: [.heat, .slow],
                doing: "Time Machine is backing up", usually: "A backup can take a while after many files change.", usualHours: 3,
                source: "Apple: Back up your Mac with Time Machine"),
        Pattern(id: "background-downloads", names: ["nsurlsessiond"], symptoms: [.battery],
                doing: "macOS is downloading or uploading something for an app (App Store, iCloud, or another app)",
                usually: "This happens while updates, backups or syncs transfer.", usualHours: 3,
                source: "Apple developer documentation: URLSession background transfers"),
        Pattern(id: "icloud-sync", names: ["bird", "cloudd"], symptoms: [.heat, .battery],
                doing: "iCloud is syncing", usually: "This happens after you add or change many files in iCloud Drive.", usualHours: 3,
                source: "man bird; Test: CPU rises while a large folder uploads to iCloud Drive"),
        Pattern(id: "file-provider", names: ["fileproviderd"], symptoms: [.heat, .battery],
                doing: "A cloud drive (iCloud, Google Drive, Dropbox or OneDrive) is syncing files",
                usually: "This happens after many files change.", usualHours: 3,
                source: "Apple developer documentation: File Provider; Test: CPU rises during a cloud drive sync"),
        Pattern(id: "software-update", names: ["softwareupdated", "com.apple.MobileSoftwareUpdate.UpdateBrainService"],
                symptoms: [.heat], doing: "macOS is preparing a software update", usually: "This happens before an update installs.",
                usualHours: 2, source: "man softwareupdate"),
        Pattern(id: "security-checks", names: ["trustd", "syspolicyd", "XprotectService", "XProtect", "amfid"],
                symptoms: [.heat], doing: "macOS is checking apps and files for safety",
                usually: "This happens after you install or update apps.", usualHours: 1,
                source: "Apple Platform Security guide: Gatekeeper and XProtect"),
        Pattern(id: "siri-suggestions", names: ["duetexpertd", "coreduetd", "knowledgeconstructiond", "suggestd", "biomesyncd"],
                symptoms: [.heat, .battery], doing: "macOS is learning your habits for Siri suggestions",
                usually: "It works in short bursts, mostly while your Mac is idle.", usualHours: 1,
                source: "DiagnosticReports: cpu_resource reports name these when they exceed macOS's own CPU limit"),
        Pattern(id: "energy-logging", names: ["PerfPowerServices"], symptoms: [.heat, .battery],
                doing: "macOS is recording energy use", usually: "It should take a moment and use very little.", usualHours: 0.5,
                source: "Test: should stay under 5% of one core; reports of it stuck at 150% for a day exist"),
        Pattern(id: "crash-report", names: ["ReportCrash", "spindump", "osanalyticshelper"], symptoms: [.heat],
                doing: "macOS is writing a report about an app that crashed or hung", usually: "It takes about a minute after a crash.",
                usualHours: 0.25, source: "man ReportCrash; man spindump"),
        Pattern(id: "apple-intelligence", names: ["mlhostd", "modelmanagerd", "intelligenceplatformd", "generativeexperiencesd"],
                symptoms: [.heat, .battery], doing: "Apple Intelligence is running or preparing its on-device models",
                usually: "This happens after an update, or while you use it.", usualHours: 2,
                source: "Test: CPU rises after a macOS update while models download and prepare"),
        Pattern(id: "permissions", names: ["tccd"], symptoms: [.heat],
                doing: "macOS is checking app permissions", usually: "It takes a moment, when an app asks for access.", usualHours: 0.25,
                source: "man tccd"),
        // Docker's own page (Resource Saver mode, read 16 November 2026): on by default, it stops the virtual machine when
        // no containers have run for 5 minutes. The entry had said the machine keeps running after they stop.
        Pattern(id: "docker-vm", pathContains: ["Docker.app/Contents/", "com.docker."], symptoms: [.heat, .battery, .memory],
                doing: "Docker's virtual machine is running", usually: "It runs while your containers do, and for 5 minutes after the last one stops.",
                usualHours: 1000, whenLong: "Quit Docker if no containers are running",
                risk: "Quitting Docker stops every container.",
                source: "Docker Desktop documentation: Resource Saver mode (on by default; stops the virtual machine 5 minutes after the last container stops)",
                checked: true),
        // Entries from the research graph (16 November 2026), each with the macOS versions it was reported on. Those
        // resting on forum reports alone say "likely" where they name a cause. No fix was found for any of them in macOS 26
        // or 27, and the 27 release notes say nothing about sleep, sound, contacts or messages. The Aerial entry matches
        // only macOS 14 and 15: macOS 26.6.2 has no idleassetsd (checked 16 November 2026).
        // A process that works for an app (macOS's sound service hosting another company's sound add-on) is named
        // with the app behind it, the general rule these cases share. Left out: Finder's memory growth on
        // macOS 14, which Howard Oakley (June 2026) says macOS 26 no longer shows.
        Pattern(id: "sound", names: ["coreaudiod"], symptoms: [.heat, .sleep],
                doing: "macOS is handling sound for your apps",
                usually: "It works while apps play or record sound, and keeps your Mac awake while they do.", usualHours: 0.25,
                endsOnItsOwn: false, whenLong: "Quit apps that add sound devices or effects",
                risk: "A virtual microphone, or an app that hides the orange microphone dot, is the likely cause. Its sound stops until you open it again.",
                source: "Forum reports (research nodes N-001, N-007, N-010): coreaudiod holds the Mac awake for an app with sound open, named by pmset -g assertions as Created for PID (Mozilla bug 1821102; Apple Developer Forums 130042); on macOS 15.4, coreaudiod at 150% CPU from Recording Indicator Utility and a Boom 3D virtual microphone (Apple Community 256028976). All versions in scope."),
        Pattern(id: "contacts-sync", names: ["peopled", "contactsd", "CallHistorySyncHelper"], symptoms: [.heat, .battery],
                doing: "macOS is syncing your contacts",
                usually: "It takes a few minutes after contacts change or you add an account.", usualHours: 0.25,
                whenLong: "Remove Contacts widgets",
                risk: "A Contacts widget is the likely cause on macOS 26.4 and later. If it goes on, turn off Contacts for one account at a time in Internet Accounts; its contacts come back when you turn it on again.",
                source: "Forum reports (research nodes N-001, N-010): peopled at 70 to 80% CPU with CallHistorySyncHelper on macOS 26.4 and 26.5, eased by removing the Contacts widget (Apple Community 256271160, 256300560); contactsd looping while syncing Exchange or Google contacts on 26.1 and 26.3 (Apple Developer Forums 809986; Apple Community 256251080)."),
        Pattern(id: "messages-sync", names: ["IMDPersistenceAgent", "imagent"], symptoms: [.heat, .battery],
                doing: "Messages is syncing with iCloud",
                usually: "It catches up after a macOS update, or when you turn on Messages in iCloud.", usualHours: 2,
                whenLong: "Turn off Messages in iCloud for a while",
                risk: "In Messages, choose Settings, then iMessage. Older messages may not show on this Mac until you turn it on again and it catches up.",
                source: "Forum reports (research node N-010): IMDPersistenceAgent at 30 to 50% CPU, with imagent, from macOS 14 to 26.0.1, stopped by turning off Messages in iCloud (Apple Community 255187752; MacRumors 2413538). Likely, not certain."),
        Pattern(id: "aerial-downloads", names: ["idleassetsd"], symptoms: [.heat, .battery],
                doing: "macOS is downloading Aerial wallpaper and screen saver videos",
                usually: "It downloads them after you choose one, or after a macOS update. They can take 10 GB or more.", usualHours: 1,
                whenLong: "Choose a still wallpaper and screen saver",
                risk: "This likely stops new downloads, though some people saw them go on.",
                source: "Forum reports (research node N-001): idleassetsd downloading Aerial videos of about 10 GB and up to 62 GB on macOS 14 and 15 (Apple Community 255329956, 255818132; MacRumors 2392675). macOS 26 has no idleassetsd; where it downloads Aerials wasn't traced."),
        Pattern(id: "displaylink", pathContains: ["DisplayLink Manager.app/Contents/"], symptoms: [.heat, .battery],
                doing: "DisplayLink Manager is drawing your extra screens",
                usually: "It draws every frame on the processor, so it works while things move on those screens.", usualHours: 0.5,
                endsOnItsOwn: false, whenLong: "Quit and reopen DisplayLink Manager",
                risk: "Screens connected through DisplayLink go dark until it's running again.",
                source: "DisplayLink forum reports (research node N-007): DisplayLink Manager 14.1 to 15.0 at 60 to 180% CPU on macOS 15 to 26.3, about 13% on 14.0, and lower after restarting it (threads 69747, 67695). Likely, not certain."),
        Pattern(id: "local-ai-model", pathContains: ["Ollama.app/Contents/", "/Cellar/ollama/", "LM Studio.app/Contents/"],
                symptoms: [.heat, .battery, .memory],
                doing: "A local AI model is running",
                usually: "It works hard while it writes an answer, then keeps the model in memory: 5 minutes in Ollama, an hour in LM Studio.", usualHours: 1,
                whenLong: "Stop the model if you aren't using it",
                risk: "Quit the app, or unload the model in it. Anything using the model gets no answers until it loads again, which takes a few seconds.",
                source: "Ollama FAQ (keeps a model loaded 5 minutes after the last request; ollama stop unloads it); LM Studio docs (models loaded on request unload after 60 minutes idle; models loaded by hand stay) (research node N-013)"),
    ]
}

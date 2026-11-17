import AppKit
import Darwin
import Foundation

/// Credit the work to the app it serves (research rule 4). macOS does some work for apps in its own helper processes:
/// WebKit's processes show, draw and load web pages for any app that shows them (Safari, Mail, and apps with a web view,
/// such as Google Drive's), and services such as the video decoder work for whichever app asks. macOS records which
/// app is responsible for each process (the record it uses to decide whose permissions a helper has), and Cool Head
/// reads it to name that app. Checked on this Mac, 17 November 2026: WebKit's processes credited to Google Drive and
/// BetterTouchTool, the video decoder to the wallpaper.
public enum Served {
    typealias Lookup = @convention(c) (pid_t) -> pid_t
    /// macOS's lookup of the responsible process (exported by its system library, undocumented): nil if a release drops it.
    static let lookup: Lookup? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Lookup.self) }

    /// The process responsible for this one, when it's another.
    public static func responsible(_ pid: pid_t) -> pid_t? {
        guard let f = lookup else { return nil }
        let r = f(pid)
        return r > 1 && r != pid ? r : nil
    }

    /// The app a macOS helper is working for: the responsible process's app, by where the app is installed. Only for
    /// macOS's XPC services (programs inside an .xpc bundle in /System), which run on an app's behalf: a command such
    /// as /usr/bin/python3 started from Terminal has Terminal as its responsible app too, but it's the person's job, not
    /// Terminal's. nil for anything else (an app's own helpers are credited by their path), for work done for macOS
    /// itself, and when it can't be read.
    public static func app(pid: pid_t, path: String?) -> String? {
        guard let path, isService(path), let r = responsible(pid), r != getpid(),
              let b = NSRunningApplication(processIdentifier: r)?.bundleURL?.path ?? Proc.path(r).flatMap(Evidence.bundle),
              opened(b) else { return nil }
        return b
    }

    /// An app the person opens: one in an Applications folder (Safari and Mail included), not part of macOS's own
    /// workings (the Dock, a wallpaper extension), which Cool Head never offers to quit.
    public static func opened(_ bundle: String) -> Bool {
        guard bundle.hasSuffix(".app") else { return false }
        return ["/Applications/", NSHomeDirectory() + "/Applications/", "/System/Applications/",
                "/System/Volumes/Preboot/Cryptexes/App/System/Applications/"].contains { bundle.hasPrefix($0) }
    }

    public static func isService(_ path: String) -> Bool { path.hasPrefix("/System/") && path.contains(".xpc/") }

    /// The app's name, from its bundle: "Google Drive".
    public static func name(_ bundle: String) -> String { ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension }

    public static func isSafari(_ bundle: String) -> Bool { name(bundle).hasPrefix("Safari") }

    /// What a macOS service is doing for the app, for the ones known by name.
    static func doing(_ e: Evidence) -> String? {
        let s = e.name + " " + (e.path ?? "")
        if s.contains("VTDecoderXPCService") { return "decoding video" }
        if s.contains("VTEncoderXPCService") { return "encoding video" }
        if s.contains("MTLCompilerService") { return "preparing its graphics" }
        return nil
    }

    /// Quitting the app: what it costs, said the same way as on the memory card (see MemoryAdvice.quitRisks); sync apps
    /// stop syncing. Recommended unless quitting loses work, which also marks it Caution.
    static func quit(_ bundle: String) -> Fix {
        let app = name(bundle)
        let cost = MemoryAdvice.quitRisks[app]
        let sync = SyncApps.app(bundle: bundle) != nil
        let words = cost?.words ?? (sync ? "Stops syncing until you open it again." : "It asks about anything unsaved.")
        let f = Fix(id: "quit", title: "Quit \(app)", consequence: words, kind: .quitApp(bundle), recommended: cost?.losesWork != true)
        return cost?.losesWork == true ? f.losingWork() : f
    }
}

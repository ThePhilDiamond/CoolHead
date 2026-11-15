import Darwin
import Foundation

/// Everything gathered about one process: the facts a person would otherwise be asked to look up.
public struct Evidence {
    public struct Ancestor {
        public let pid: pid_t
        public let name: String
        public let path: String?
        public let args: [String]
    }

    public struct Lock {
        public let path: String
        public let note: String?      // a short lock file's own text, which often names the holder
    }

    public let pid: pid_t
    public let name: String
    public let path: String?
    public let args: [String]
    public let cwd: String?
    public let start: Date?
    public let mine: Bool
    /// Cores in use over the sample, where 1.0 is one whole core.
    public let coresNow: Double
    /// Cores used on average since it started.
    public let coresAverage: Double
    /// Share of its CPU time spent on the performance cores, 0 to 1.
    public let performanceShare: Double?
    public let memoryBytes: UInt64
    public let ancestors: [Ancestor]            // parent first, up to launchd
    public let writing: [String]                // regular files open for writing
    public let locks: [Lock]
    public let progress: Progress?
    /// Bytes it wrote to disk during the sample: a sign it is still producing something.
    public let bytesWrittenDuringSample: UInt64
    /// The latest change to any file it is writing.
    public let lastOutput: Date?
    /// The last line of the file it most recently wrote (usually its log).
    public let lastLine: String?
    /// True when a file other than a log changed in the last 10 minutes: it seems to save results as it goes.
    public let savesAsItGoes: Bool
    /// When its real work began: its lock file's own start time when the lock names it, else its start.
    public let workStart: Date?

    /// Samples the process twice, `interval` seconds apart, to measure CPU now.
    public static func gather(pid: pid_t, interval: TimeInterval = 1.0) -> Evidence? {
        guard let b = Proc.bsd(pid) else { return nil }
        let u1 = Proc.usage(pid)
        let t1 = Date()
        Thread.sleep(forTimeInterval: interval)
        let u2 = Proc.usage(pid)
        let dt = Date().timeIntervalSince(t1)
        var now = 0.0, avg = 0.0, pshare: Double?
        if let a = u1, let z = u2 {
            now = max(0, z.cpuSeconds - a.cpuSeconds) / dt
            let life = Date().timeIntervalSince(b.start)
            if life > 0 { avg = z.cpuSeconds / life }
            if z.cpuSeconds > 0 { pshare = min(1, z.pCoreSeconds / z.cpuSeconds) }
        }

        var chain: [Ancestor] = []
        var p = b.ppid
        while p > 1, chain.count < 12, let pb = Proc.bsd(p) {
            chain.append(Ancestor(pid: p, name: pb.name, path: Proc.path(p), args: Proc.args(p)))
            p = pb.ppid
        }
        if p == 1 { chain.append(Ancestor(pid: 1, name: "launchd", path: "/sbin/launchd", args: [])) }

        let files = Proc.openFiles(pid)
        let regular = files.filter { !$0.path.hasPrefix("/dev/") && !isCode($0.path) }
        var writing = Array(Set(regular.filter { $0.writable && !$0.path.hasSuffix(".lock") }.map(\.path))).sorted()
        // stdout and stderr redirected to a file count as writing, whatever the open flags say
        for f in regular where (f.fd == 1 || f.fd == 2) && !writing.contains(f.path) { writing.append(f.path) }
        let locks = Array(Set(regular.filter { $0.path.hasSuffix(".lock") }.map(\.path))).sorted().map {
            Lock(path: $0, note: smallText($0))
        }
        let progress = Progress.find(in: writing)
        let written = max(0, Int64(bitPattern: (u2?.diskWritten ?? 0) &- (u1?.diskWritten ?? 0)))
        var newest: (Date, String)?
        var saves = false
        for w in writing {
            guard let m = (try? FileManager.default.attributesOfItem(atPath: w))?[.modificationDate] as? Date else { continue }
            if newest == nil || m > newest!.0 { newest = (m, w) }
            if !isLog(w) && Date().timeIntervalSince(m) < 600 { saves = true }
        }
        let last = newest.flatMap { lastLineOf($0.1) }
        var workStart: Date? = b.start
        for l in locks {
            guard let n = l.note, n.contains("\(pid)"), let t = isoTime(in: n), t > b.start else { continue }
            workStart = t
        }

        return Evidence(pid: pid, name: b.name, path: Proc.path(pid), args: Proc.args(pid), cwd: Proc.cwd(pid),
                        start: b.start, mine: b.uid == getuid(), coresNow: now, coresAverage: avg,
                        performanceShare: pshare, memoryBytes: u2?.footprint ?? 0, ancestors: chain,
                        writing: writing, locks: locks, progress: progress,
                        bytesWrittenDuringSample: UInt64(written), lastOutput: newest?.0, lastLine: last,
                        savesAsItGoes: saves, workStart: workStart)
    }

    static func isCode(_ path: String) -> Bool {
        path.hasSuffix(".dylib") || path.hasSuffix(".so") || path.contains(".framework/") || path.hasSuffix(".car")
            || path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/") || path.hasPrefix("/private/var/db/")
    }

    static func isLog(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["log", "txt", "out", "err", ""].contains(ext) || path.contains("/Logs/")
    }

    static func lastLineOf(_ path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 2048 ? size - 2048 : 0)
        guard let d = try? h.readToEnd(), let t = String(data: d, encoding: .utf8) else { return nil }
        return t.split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The first local ISO time in a text, such as 2026-11-14T13:44:55.
    static func isoTime(in text: String) -> Date? {
        guard let r = text.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(text[r]))
    }

    /// The text of a lock file if it is short and readable: lock files often say who holds them.
    static func smallText(_ path: String) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = a[.size] as? NSNumber, size.intValue > 0, size.intValue < 400,
              let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension Evidence {
    /// The script a language runtime is running, if any: "build.py" for `python build.py index`.
    public var script: String? {
        let runtimes = ["python", "Python", "node", "ruby", "perl", "bash", "sh", "zsh", "deno", "bun", "php"]
        let exe = (path.map { ($0 as NSString).lastPathComponent }) ?? name
        guard runtimes.contains(where: { exe.lowercased().hasPrefix($0.lowercased()) }) else { return nil }
        for a in args.dropFirst() where !a.hasPrefix("-") {
            let last = (a as NSString).lastPathComponent
            if last.contains(".") || a.contains("/") { return last }
        }
        return nil
    }

    /// The script and its first plain argument: "build.py index".
    public var task: String {
        guard let s = script else { return name }
        let rest = args.dropFirst().drop { ($0 as NSString).lastPathComponent != s }.dropFirst()
        if let verb = rest.first(where: { !$0.hasPrefix("-") && !$0.contains("/") }) { return "\(s) \(verb)" }
        return s
    }

    /// The project folder it runs in: the top of its git repository, or its working folder.
    public var project: String? {
        guard var dir = cwd, dir != "/", dir != NSHomeDirectory() else { return nil }
        let start = dir
        while dir != "/" && dir != NSHomeDirectory() {
            if FileManager.default.fileExists(atPath: dir + "/.git") { return (dir as NSString).lastPathComponent }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return (start as NSString).lastPathComponent
    }

    /// The app bundle the process belongs to, from its own path or its parents': "Claude", "Terminal".
    public var app: String? { Evidence.appName(path) }

    static func appName(_ path: String?) -> String? {
        guard let path, let r = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<r.lowerBound])
        return (bundle as NSString).lastPathComponent
    }

    /// Who started it, in plain words.
    public var startedBy: String {
        for a in ancestors {
            if let app = Evidence.appName(a.path) { return app }
            let n = a.name.lowercased()
            if ["sh", "bash", "zsh", "fish"].contains(n), let i = a.args.firstIndex(of: "-c"), i + 1 < a.args.count {
                let detached = ancestors.last?.pid == 1 && ancestors.count <= ancestors.firstIndex(where: { $0.pid == a.pid })! + 2
                return detached ? "a background command whose launcher has exited" : "a shell command"
            }
            if a.pid == 1 { return "macOS (launchd)" }
        }
        return "macOS (launchd)"
    }

    /// The shell command line that launched it, when one did.
    public var launchCommand: String? {
        for a in ancestors {
            if let i = a.args.firstIndex(of: "-c"), i + 1 < a.args.count { return a.args[i + 1] }
        }
        return nil
    }
}

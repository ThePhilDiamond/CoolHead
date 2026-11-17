import Foundation
import Security

public enum CoolHead {
    /// Kept in step with the VERSION file; scripts/build-app.sh checks they match.
    public static let version = "0.6.1"
}

/// The anonymised report behind "Share this case": what Cool Head saw about a process it couldn't explain, with
/// nothing that identifies the person, their files or their work.
///
/// What it holds: the kind of process (a macOS process or a signed app by name, otherwise only "a Python script" or
/// "a command-line tool"), how it behaved, what Cool Head concluded, and the kind of Mac.
/// What it never holds: paths, command lines, folder or file names, log lines, lock notes, user or project names,
/// process numbers. `coolhead selftest` checks this.
///
/// The person sees the exact text first. Nothing is sent by Cool Head: the text opens as a GitHub issue in their
/// browser, which they can edit and choose to submit.
public enum CaseReport {
    public static func make(_ e: Evidence, card: Card, mac: MacState, busySince: Date?, now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("**Process:** \(identity(e))")
        lines.append("**What Cool Head said:** \(stateWords(card.state))" + (Pattern.match(name: e.name, path: e.path, pid: e.pid).map { " (catalogue entry `\($0.id)`)" } ?? " (no catalogue entry)"))
        lines.append("**Busy for:** \(rough(now.timeIntervalSince(busySince ?? e.start ?? now)))")
        lines.append("**CPU:** about \(Fmt.cores(e.coresNow)) now, \(Fmt.cores(e.coresAverage)) on average since it started")
        if let p = e.performanceShare { lines.append("**On performance cores:** \(Int((p * 100).rounded()))% of its time") }
        lines.append("**Memory:** about \(roughGB(e.memoryBytes))")
        lines.append("**Writes files:** \(e.writing.isEmpty ? "no" : "yes")" + (e.savesAsItGoes ? ", saving results as it goes" : ""))
        lines.append("**Reports progress:** \(e.progress == nil ? "no" : "yes")")
        lines.append("**Started by:** \(startedKind(e))")
        lines.append("")
        lines.append("**Mac:** \(model()), \(mac.cores) cores (\(mac.performanceCores) performance, \(mac.efficiencyCores) efficiency), macOS \(macOS())")
        lines.append("**At the time:** heat \(mac.thermal), memory pressure \(mac.memoryPressure), " + (mac.onPower ? (mac.charging ? "charging" : "on power") : "on battery"))
        lines.append("**Cool Head:** \(CoolHead.version)")
        return lines.joined(separator: "\n")
    }

    /// The title for the GitHub issue.
    public static func title(_ e: Evidence, card: Card) -> String {
        "Case: \(identity(e, short: true)), \(stateWords(card.state))"
    }

    // MARK: - What a process may be called

    /// A macOS process keeps its name, and so does an app installed in an Applications folder that is signed by a
    /// developer: those are software anyone can have. Anything else is described only by its kind, because its
    /// name could be the person's own work (their own builds and their employer's tools are often signed too).
    /// No Team ID is ever included: for an individual developer it leads to their name.
    /// What a report may call this process (see `identity`).
    public static func subject(_ e: Evidence) -> String { identity(e, short: false) }

    static func identity(_ e: Evidence, short: Bool = false) -> String {
        if let p = e.path, isMacOS(p) { return short ? e.name : "\(e.name) (part of macOS)" }
        if let p = e.path, let app = e.app, inApplications(p), teamID(p) != nil {
            return short ? app : "\(app) (an app installed in Applications)"
        }
        if e.script != nil {
            let runtime = ((e.path ?? e.name) as NSString).lastPathComponent.lowercased()
            let lang = runtime.hasPrefix("python") ? "Python" : runtime.hasPrefix("node") ? "Node.js"
                : runtime.hasPrefix("ruby") ? "Ruby" : ["bash", "sh", "zsh"].contains(runtime) ? "shell" : "other"
            return "a \(lang) script (its name is withheld)"
        }
        if e.app != nil { return "an app (its name is withheld)" }
        return "a command-line tool (its name is withheld)"
    }

    static func inApplications(_ path: String) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    public static func isMacOS(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// The developer Team ID a program is signed with, or nil for unsigned and ad-hoc signed programs.
    static func teamID(_ path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any], let team = d[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { return nil }
        return team
    }

    public static func stateWords(_ s: JobState) -> String {
        switch s {
        case .working: return "working"
        case .waiting: return "waiting"
        case .stalled: return "looks stuck"
        case .unknown: return "can't tell"
        case .starting: return "just started"
        case .quiet: return "quiet"
        }
    }

    static func startedKind(_ e: Evidence) -> String {
        if e.ancestors.contains(where: { Evidence.appName($0.path) != nil }) { return "an app" }
        if e.launchCommand != nil { return "a shell command" }
        return "macOS (launchd)"
    }

    /// Rounded so a report can't be matched to a moment: under an hour to 10 minutes, then to the hour.
    static func rough(_ s: TimeInterval) -> String {
        let m = s / 60
        if m < 60 { return "about \(max(10, Int((m / 10).rounded()) * 10)) minutes" }
        let h = Int((m / 60).rounded())
        return h == 1 ? "about 1 hour" : "about \(h) hours"
    }

    static func roughGB(_ b: UInt64) -> String {
        let g = Double(b) / 1_073_741_824
        return g < 1 ? "\(max(100, Int((g * 10).rounded()) * 100)) MB" : String(format: "%.0f GB", g.rounded())
    }

    public static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        var chip = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &chip, nil, 0)
        var cbuf = [CChar](repeating: 0, count: max(chip, 1))
        sysctlbyname("machdep.cpu.brand_string", &cbuf, &chip, nil, 0)
        let m = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let c = String(decoding: cbuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return "\(m), \(c)"
    }

    public static func macOS() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    /// The GitHub "new issue" link with the report filled in, for the case issue form.
    public static func issueURL(title: String, report: String) -> URL? {
        var u = URLComponents(string: "https://github.com/ThePhilDiamond/CoolHead/issues/new")!
        u.queryItems = [URLQueryItem(name: "template", value: "case.yml"), URLQueryItem(name: "title", value: title),
                        URLQueryItem(name: "report", value: report)]
        return u.url
    }
}

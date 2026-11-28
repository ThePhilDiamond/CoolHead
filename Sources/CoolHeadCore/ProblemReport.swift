import Foundation

/// "Report a problem": the person's own words plus Cool Head's recent activity, for when a fix caused trouble or
/// Cool Head itself isn't working. Like the case report, the person sees every word first, and nothing is sent by
/// Cool Head: it opens as a GitHub issue in their browser, or is copied.
///
/// The activity comes from `Watcher.activity`, which is anonymised as it is written (processes are named only as
/// the case report would name them). The person's own words are theirs; the form asks them to leave out anything
/// private, because the issue will be public.
public enum ProblemReport {
    /// The most the title's few words can be, counted as they're typed, so titles stay readable in GitHub's list of
    /// issues; a count in the corner shows what's left.
    public static let summaryLimit = 60
    /// What went wrong with something Cool Head was managing, each finishing the title's sentence after what Cool Head
    /// did: "Chrome's memory limit caused an app to crash or quit". The title names what went wrong while Cool Head did
    /// it, not what Cool Head did, which would read as if that were the problem; several kinds of problem make reports
    /// clearer and more useful for troubleshooting. The last asks for a few words instead.
    public static let heldProblems = ["Caused an app to crash or quit", "Stopped something from working", "Caused lost work or data",
                                      "Did not help", "Made my Mac slower", "Something else"]
    /// The title of a report about something Cool Head was managing: what it did, then what went wrong, in full; with
    /// Something else, what it did and the person's few words.
    public static func heldTitle(doing: String, problem: String, summary: String) -> String {
        if problem == heldProblems.last {
            let s = tidy(summary)
            return "Problem: " + (s.isEmpty ? doing : "\(doing): \(s)")
        }
        return "Problem: \(doing) " + problem.prefix(1).lowercased() + problem.dropFirst()
    }
    static func tidy(_ summary: String) -> String {
        let s = summary.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return s.count > summaryLimit ? String(s.prefix(summaryLimit)).trimmingCharacters(in: .whitespaces) : s
    }
    public static let kinds = ["A fix caused trouble", "Cool Head is not working right", "Something else"]

    /// `about`: what Cool Head is holding back that the problem is with, when the person picked one.
    public static func make(kind: String, words: String, activity: [Watcher.LogEntry], cards: [LiveCard], mac: MacState,
                            about: String? = nil, problem: String? = nil, now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("**What happened:** \(kind)")
        if let about { lines.append("**With:** \(about)") }
        if let problem { lines.append("**What went wrong:** \(problem)") }
        lines.append("")
        lines.append("**Cool Head's activity in the last 6 hours** (times to the nearest 5 minutes):")
        let recent = activity.filter { now.timeIntervalSince($0.t) <= 6 * 3600 }.suffix(40)
        if recent.isEmpty { lines.append("- nothing recorded (Cool Head keeps this only while it is running)") }
        for e in recent { lines.append("- \(Fmt.clock(rounded(e.t))) \(e.text)") }
        lines.append("")
        lines.append("**Cards now:** " + (cards.isEmpty ? "none"
            : cards.map { $0.pid == nil ? $0.reportSubject : "\($0.reportSubject), \(CaseReport.stateWords($0.card.state))" }.joined(separator: "; ")))
        lines.append("**Mac:** \(CaseReport.model()), \(mac.cores) cores, macOS \(CaseReport.macOS()); heat \(mac.thermal), memory pressure \(mac.memoryPressure)")
        lines.append("**Cool Head:** \(CoolHead.version)")
        return lines.joined(separator: "\n")
    }

    static func rounded(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 300).rounded() * 300)
    }

    /// The issue's title: the person's few words, so reports don't all share one title. Spaces tidied, at most
    /// `summaryLimit` characters; the kind when nothing was typed.
    public static func title(kind: String, summary: String) -> String {
        let s = tidy(summary)
        return "Problem: " + (s.isEmpty ? kind : s)
    }

    /// The GitHub "new issue" link for the problem form, with the person's words and the report filled in.
    public static func issueURL(title: String, words: String, report: String) -> URL? {
        var u = URLComponents(string: "https://github.com/ThePhilDiamond/CoolHead/issues/new")!
        u.queryItems = [URLQueryItem(name: "template", value: "problem.yml"), URLQueryItem(name: "title", value: title),
                        URLQueryItem(name: "words", value: words), URLQueryItem(name: "report", value: report)]
        return u.url
    }
}

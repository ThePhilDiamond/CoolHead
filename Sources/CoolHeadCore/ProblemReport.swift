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
    /// issues (Phil, 19 November 2026: "Maybe limit the summary to characters? Show a character limit in the corner").
    public static let summaryLimit = 60
    public static let kinds = ["A fix caused trouble", "Cool Head isn't working right", "Something else"]

    /// `about`: what Cool Head is holding back that the problem is with, when the person picked one.
    public static func make(kind: String, words: String, activity: [Watcher.LogEntry], cards: [LiveCard], mac: MacState,
                            about: String? = nil, now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("**What happened:** \(kind)")
        if let about { lines.append("**With:** \(about)") }
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

    /// The issue's title: the person's few words, so reports don't all share one title (Phil, 19 November 2026: "Reporting
    /// an issue maybe needs a "describe your issue in five words or less" to generate unique titles? Otherwise they'll all
    /// be the same if there are multiple reports"). Spaces tidied, at most `summaryLimit` characters; the kind when
    /// nothing was typed.
    public static func title(kind: String, summary: String) -> String {
        var s = summary.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if s.count > summaryLimit { s = String(s.prefix(summaryLimit)).trimmingCharacters(in: .whitespaces) }
        return "Problem: " + (s.isEmpty ? kind : s)
    }

    /// The GitHub "new issue" link for the problem form, with the person's words and the report filled in.
    public static func issueURL(kind: String, summary: String = "", words: String, report: String) -> URL? {
        var u = URLComponents(string: "https://github.com/ThePhilDiamond/CoolHead/issues/new")!
        u.queryItems = [URLQueryItem(name: "template", value: "problem.yml"), URLQueryItem(name: "title", value: title(kind: kind, summary: summary)),
                        URLQueryItem(name: "words", value: words), URLQueryItem(name: "report", value: report)]
        return u.url
    }
}

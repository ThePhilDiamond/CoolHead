import Foundation

/// Progress a job reports about itself, read from the tail of a file it is writing (usually its log).
public struct Progress {
    public let file: String
    public let line: String
    public let done: Double?          // items done
    public let total: Double?         // items in all
    public let unit: String?          // "passages", "files"…
    public let minutesLeft: Double?   // the job's own estimate, when it gives one
    public let lineTime: Date         // when that line was written (the file's last change)
    /// The usual gap between its progress lines, in minutes, when the lines carry elapsed time ("9.2 min").
    public var typicalGapMinutes: Double? = nil

    public var fraction: Double? {
        guard let d = done, let t = total, t > 0 else { return nil }
        return min(1, d / t)
    }

    /// When the job should finish: its own estimate, counted from when it wrote the line.
    public var finish: Date? {
        guard let m = minutesLeft else { return nil }
        return lineTime.addingTimeInterval(m * 60)
    }

    static let ratio = try! NSRegularExpression(
        pattern: #"(\d[\d,]*)\s*(?:/|of)\s*(\d[\d,]*)\s*([A-Za-z]+)?"#)
    static let percent = try! NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d+)?)\s?%"#)
    static let left = try! NSRegularExpression(
        pattern: #"(?:about|~|eta[: ]*)?\s*(\d+(?:\.\d+)?)\s*(h|hr|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\s*(?:left|remaining|to go)"#,
        options: [.caseInsensitive])

    /// Looks through each file's last 16 KB, newest line first, for a progress line.
    public static func find(in files: [String]) -> Progress? {
        var best: Progress?
        for f in files {
            guard let p = read(f) else { continue }
            if best == nil || p.lineTime > best!.lineTime { best = p }
        }
        return best
    }

    static func read(_ path: String) -> Progress? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (a[.size] as? NSNumber)?.uint64Value, size > 0,
              let mtime = a[.modificationDate] as? Date,
              let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let tail: UInt64 = 16 * 1024
        try? h.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).suffix(200)
        for line in lines.reversed() {
            if var p = parse(line, file: path, time: mtime) {
                p.typicalGapMinutes = gap(lines.filter { parse($0, file: path, time: mtime) != nil })
                return p
            }
        }
        return nil
    }

    static let elapsed = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*min(?:utes?|s)?\b(?!\s*(?:left|remaining|to go))"#,
                                                  options: [.caseInsensitive])

    /// The median gap between consecutive progress lines' elapsed times, from the last 20 lines.
    static func gap(_ lines: [String]) -> Double? {
        let times: [Double] = lines.suffix(20).compactMap { l in
            let ns = l as NSString
            guard let m = elapsed.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return Double(ns.substring(with: m.range(at: 1)))
        }
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 2]
    }

    static func parse(_ line: String, file: String, time: Date) -> Progress? {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func num(_ r: NSRange) -> Double? {
            r.location == NSNotFound ? nil : Double(ns.substring(with: r).replacingOccurrences(of: ",", with: ""))
        }
        var done: Double?, total: Double?, unit: String?, minutes: Double?
        if let m = ratio.firstMatch(in: line, range: all), let d = num(m.range(at: 1)), let t = num(m.range(at: 2)),
           t > 0, d <= t, t > 1 {
            done = d; total = t
            if m.range(at: 3).location != NSNotFound { unit = ns.substring(with: m.range(at: 3)) }
        } else if let m = percent.firstMatch(in: line, range: all), let p = num(m.range(at: 1)), p <= 100 {
            done = p; total = 100; unit = "%"
        }
        if let m = left.firstMatch(in: line, range: all), let v = num(m.range(at: 1)) {
            let u = ns.substring(with: m.range(at: 2)).lowercased()
            minutes = u.hasPrefix("h") ? v * 60 : u.hasPrefix("s") ? v / 60 : v
            if m.range(at: 1).location > 0 && ns.substring(with: NSRange(location: m.range(at: 1).location - 1, length: 1)) == "-" { minutes = 0 }
        }
        guard done != nil || minutes != nil else { return nil }
        return Progress(file: file, line: line.trimmingCharacters(in: .whitespaces), done: done, total: total,
                        unit: unit, minutesLeft: minutes, lineTime: time)
    }
}

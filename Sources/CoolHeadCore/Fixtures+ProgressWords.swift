import Foundation

/// Checks for how a job's progress is said: what it's doing when its log says so, and never a guess when it doesn't.
extension Fixture {
    static func progressWordsSamples(_ now: Date) -> [(String, Card)] { [] }

    static func progressWordsChecks(_ now: Date) -> [(String, Bool, String)] {
        func p(_ line: String, _ done: Double?, _ total: Double?, _ unit: String?) -> Progress {
            Progress(file: "/Users/x/job.log", line: line, done: done, total: total, unit: unit, lineTime: now)
        }
        let backup = p("Backing up 950/1000 files", 950, 1000, "files").headline(who: "Archiver")
        let upload = p("uploading part 19 of 20 chunks", 19, 20, "chunks").headline(who: "Sender")
        let count = p("25600/26512 passages", 25600, 26512, "passages").headline(who: "Photo Export")
        let none = p("progress: 95%", 95, 100, nil).headline(who: "WhatsApp")
        let ok = backup == "Archiver is backing up: 95% done." && upload == "Sender is uploading: 95% done."
            && count == "Photo Export is 96% through 26,512 passages." && none == "WhatsApp is 95% done with something its log does not name."
        // a binary file read as a log (WhatsApp, 26 November 2026): its bytes are never progress or a line to show; a
        // run of base64 isn't a count with a unit; a real log line next to junk still reads
        let dir = NSTemporaryDirectory() + "coolhead-progress-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var binary = Data([0x6A, 0x00, 0xC3, 0x28, 0xFF, 0xFE, 0x01, 0x02]); binary.append(Data("\n50/100 items done\nFiewCLZfK98gxoC+Z/TibZU4mDwof6/iFAV7/7tHYUw=\n".utf8))
        let bin = dir + "/blob", b64 = dir + "/b64.txt", log = dir + "/job.log"
        FileManager.default.createFile(atPath: bin, contents: binary)
        FileManager.default.createFile(atPath: b64, contents: Data("FiewCLZfK98gxoC+Z/TibZU4mDwof6/iFAV7/7tHYUw=\n".utf8))
        // a real log: many plain lines, the progress line, then one garbled line (under 1% of its characters)
        let plain = (1...40).map { "step \($0) finished in 2.1 seconds" }.joined(separator: "\n")
        FileManager.default.createFile(atPath: log, contents: Data((plain + "\n25600/26512 passages, about 6 min left\ngarbled \u{FFFD}\u{FFFD} 3/4 parts\n").utf8))
        let fromLog = Progress.read(log)
        let binaryOK = Progress.read(bin) == nil && Evidence.lastLineOf(bin) == nil && Progress.read(b64) == nil
            && Progress.parse("7/7tHYUw", file: "", time: now) == nil && fromLog?.total == 26512 && fromLog?.unit == "passages"
            && Progress.parse("Backing up 950/1000 files", file: "", time: now)?.unit == "files"
        return [("progress-says-what", ok, [backup, upload, count, none].joined(separator: " | ")),
                ("progress-not-from-binary", binaryOK, "binary file: \(Progress.read(bin) == nil ? "no progress" : "progress"), no line \(Evidence.lastLineOf(bin) == nil); base64: \(Progress.read(b64) == nil ? "no progress" : "progress"); log beside junk: \(fromLog?.line ?? "none")")]
    }
}

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
            && count == "Photo Export is 96% through 26,512 passages." && none == "WhatsApp is 95% done with something its log doesn't name."
        return [("progress-says-what", ok, [backup, upload, count, none].joined(separator: " | "))]
    }
}

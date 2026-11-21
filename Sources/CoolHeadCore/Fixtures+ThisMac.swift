import Foundation

/// Checks for the This Mac page: the serial number, model, and disk space read on this Mac, and how space is worded.
/// The serial number itself is never printed here, since selftest output can be pasted into a report.
extension Fixture {
    static func thisMacChecks(_ now: Date) -> [(String, Bool, String)] {
        let serial = ThisMac.serial(), space = ThisMac.space()
        let made = ThisMac.Space(free: 12_340_000_000, total: 245_110_000_000)
        let tight = ThisMac.Space(free: 9_600_000_000, total: 245_110_000_000)
        let ok = serial != nil && space.map { $0.free <= $0.total && $0.total > 0 } == true
            && made.text == "12 GB free of 245 GB" && made.low && !ThisMac.Space(free: 64_000_000_000, total: 494_000_000_000).low
            && tight.text == "9.6 GB free of 245 GB" && abs(made.used - 0.9497) < 0.001
        return [("this-mac-reads", ok,
                 "serial \(serial == nil ? "not read" : "read (not shown)"); model \(ThisMac.modelName() == nil ? "not read" : "read"); "
                 + "space \(space.map { "read, \(Int(($0.used * 100).rounded()))% used" } ?? "not read"); made-up: \(made.text), \(tight.text)")]
    }
    static func thisMacSamples(_ now: Date) -> [(String, Card)] { [] }
}

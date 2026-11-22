import Foundation

/// Checks for the memory signals beyond macOS's pressure level: memory moved to the disk, and free space on the
/// startup disk.
extension Fixture {
    static func memorySignalsChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func mac(_ pressure: String, swappedMB: Double? = nil, freeGB: Double? = nil) -> MacState {
            var s = MacState(); s.memoryPressure = pressure; s.swapUsedMB = 2000; s.swapTotalMB = 3072
            s.swappedOutMB = swappedMB
            s.diskFreeBytes = freeGB.map { UInt64($0 * 1_000_000_000) }
            return s
        }
        // heavy swapping counts as tight memory even when macOS says normal; light swapping doesn't; macOS's own
        // warning and critical always count, and nothing is tight when memory is fine
        let levels = [mac("normal", swappedMB: 1400).memoryLevel, mac("normal", swappedMB: 600).memoryLevel, mac("normal").memoryLevel,
                      mac("warning").memoryLevel, mac("critical", swappedMB: 2000).memoryLevel, mac("unknown", swappedMB: 2000).memoryLevel]
        review.append(("memory-heavy-swap-counts", levels == ["warning", nil, nil, "warning", "critical", nil],
                       "normal with 1.4 GB moved, 600 MB, none; warning; critical; unknown: \(levels.map { $0 ?? "fine" })"))
        // the card says how much was moved to the disk, only when it's worth saying
        let slack = [MemGroup(key: "s", name: "Slack", kind: .app, bundle: "/Applications/Slack.app", bytes: 3_000_000_000, count: 5)]
        let moving = MemoryAdvice.card(slack, mac: mac("warning", swappedMB: 600), now: now)
        let quiet = MemoryAdvice.card(slack, mac: mac("warning", swappedMB: 40), now: now)
        review.append(("memory-says-what-moved", moving.explanation.hasPrefix("In the last 2 minutes, your Mac moved 600 MB of memory to its disk")
                       && !quiet.explanation.contains("In the last 2 minutes"), moving.explanation))
        // a nearly full startup disk is said, with Storage settings offered; a roomy one isn't, and nor is an unknown one
        let full = MemoryAdvice.card(slack, mac: mac("warning", freeGB: 12.4), now: now)
        let roomy = MemoryAdvice.card(slack, mac: mac("warning", freeGB: 45), now: now)
        let unknown = MemoryAdvice.card(slack, mac: mac("warning"), now: now)
        let noOne = MemoryAdvice.card([], mac: mac("critical", freeGB: 3), now: now)
        let offersDisk = { (c: Card) in c.fixes.contains { $0.id == "disk" && $0.doer == .you && !$0.recommended } }
        review.append(("memory-low-disk", full.explanation.contains("nearly full too (12 GB free)") && offersDisk(full)
                       && !roomy.explanation.contains("startup disk") && !offersDisk(roomy) && !offersDisk(unknown)
                       && noOne.explanation.contains("nearly full too (3.0 GB free)") && offersDisk(noOne),
                       full.explanation))
        // both are readable here without an administrator password
        let live = MacState.read()
        review.append(("memory-signals-readable", live.diskFreeBytes != nil && live.swapOutPages != nil,
                       "startup disk free \(live.diskFreeBytes.map { MemoryAdvice.diskGB($0) } ?? "unreadable"); swap-outs since startup \(live.swapOutPages.map(String.init) ?? "unreadable")"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func memorySignalsSamples(_ now: Date) -> [(String, Card)] { [] }
}

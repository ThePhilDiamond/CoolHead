import CoreAudio
import Foundation

/// Whether an app or job is playing sound or downloading right now, so Cool Head doesn't pause it until you plug in,
/// or stop it under a CPU limit, in the middle of either: a paused app's sound cuts out and its download stalls or
/// fails. An app counts as busy if any of its helpers is (Chrome plays sound and downloads from helper processes), so
/// the caller passes every process of the app's group.
///
/// Two readings, neither needs a prompt (checked on macOS 26, 22 November 2026):
/// - Sound: CoreAudio's list of processes using sound says whether each is playing right now
///   (`kAudioProcessPropertyIsRunningOutput`). It lists who is playing, not the sound itself. Where that list isn't
///   available, macOS's sound service holding the Mac awake "for" a process (`pmset -g assertions`, coreaudiod,
///   "Created for PID") stands in: that means sound is open, not that it's playing, so it errs toward not pausing.
/// - Downloading: bytes coming in, per process, from Apple's `nettop` (about a second a reading). Downloading means at
///   least `downloadRate` coming in, in every reading over at least `downloadSpan`, so an app checking for mail
///   isn't mistaken for a download. It can't tell a download from a stream or a sync; either way the app is left alone,
///   which is the safe side.
public enum BusyWith: Equatable {
    case sound, download

    /// At least 100 KB a second coming in...
    public static let downloadRate: Double = 100_000
    /// ...in every reading for at least 10 seconds.
    public static let downloadSpan: TimeInterval = 10
    /// Readings older than this are forgotten.
    static let keep: TimeInterval = 30

    /// One nettop reading: bytes that came in during that second, by process number.
    public struct Sample: Equatable {
        public var at: Date
        public var bytesIn: [pid_t: Double]
        public init(at: Date, bytesIn: [pid_t: Double]) { self.at = at; self.bytesIn = bytesIn }
    }

    // MARK: Deciding

    /// What holds this group back from being paused or stopped now, if anything: sound first, as it's the one a
    /// person notices at once. `playing` is CoreAudio's list (nil where it isn't available); `soundOpen` the processes
    /// macOS's sound service holds the Mac awake for.
    public static func reason(group: Set<pid_t>, playing: Set<pid_t>?, soundOpen: Set<pid_t>,
                              samples: [Sample], now: Date) -> BusyWith? {
        if playingSound(group: group, playing: playing, soundOpen: soundOpen) { return .sound }
        if downloading(group: group, samples: samples, now: now) { return .download }
        return nil
    }

    /// CoreAudio's list when there is one (open but silent doesn't count); otherwise sound open counts as playing.
    public static func playingSound(group: Set<pid_t>, playing: Set<pid_t>?, soundOpen: Set<pid_t>) -> Bool {
        if let playing { return !group.isDisjoint(with: playing) }
        return !group.isDisjoint(with: soundOpen)
    }

    /// Downloading: the group's bytes coming in are at least `downloadRate` in every reading of the last
    /// `downloadSpan` plus a little, and those readings span at least `downloadSpan`. Fewer readings than that, or one
    /// below the rate, isn't a download yet.
    public static func downloading(group: Set<pid_t>, samples: [Sample], now: Date) -> Bool {
        let recent = samples.filter { now.timeIntervalSince($0.at) <= downloadSpan + 5 && $0.at <= now }
            .sorted { $0.at < $1.at }
        guard let first = recent.first, let last = recent.last,
              last.at.timeIntervalSince(first.at) >= downloadSpan else { return false }
        return recent.allSatisfy { s in group.reduce(0) { $0 + (s.bytesIn[$1] ?? 0) } >= downloadRate }
    }

    /// The group's bytes coming in, in one reading.
    public static func rate(group: Set<pid_t>, in s: Sample) -> Double { group.reduce(0) { $0 + (s.bytesIn[$1] ?? 0) } }

    /// At the click on Pause until you plug in: sound is read again then, since it can start between readings; for a
    /// download, the latest reading at the download rate is enough, as there's no time to wait for 10 seconds of them
    /// and pausing a download is the worse mistake.
    public static func atClick(group: Set<pid_t>, playing: Set<pid_t>?, soundOpen: Set<pid_t>, downloadingNow: Bool) -> BusyWith? {
        if playingSound(group: group, playing: playing, soundOpen: soundOpen) { return .sound }
        return downloadingNow ? .download : nil
    }

    /// Adds a reading and forgets old ones.
    public static func remember(_ s: Sample, in samples: [Sample]) -> [Sample] {
        (samples + [s]).filter { s.at.timeIntervalSince($0.at) <= keep }
    }

    // MARK: Words

    /// On a card, in place of Pause until you plug in.
    public var cardLine: String {
        switch self {
        case .sound: return "Not paused while it's playing sound."
        case .download: return "Not paused while it's downloading."
        }
    }

    /// On the pinned line for something under a CPU limit.
    public var pinnedLine: String {
        switch self {
        case .sound: return "Full speed while it's playing sound."
        case .download: return "Full speed while it's downloading."
        }
    }

    // MARK: Reading

    /// The processes macOS's sound service holds the Mac awake for: sound open, playing or not.
    public static func soundOpen(_ holds: [PowerState.Hold]) -> Set<pid_t> {
        Set(holds.filter { $0.name == "coreaudiod" }.compactMap { $0.forPID })
    }

    /// The same, read now (`pmset -g assertions`); only needed where CoreAudio's list isn't available.
    public static func soundOpenNow() -> Set<pid_t> {
        guard let d = Hardware.run("/usr/bin/pmset", ["-g", "assertions"]) else { return [] }
        return soundOpen(PowerState.parseAssertions(String(decoding: d, as: UTF8.self)))
    }

    /// The processes playing sound right now, from CoreAudio; nil where macOS doesn't offer the list.
    public static func playingNow() -> Set<pid_t>? {
        func address(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var list = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &list, 0, nil, &size, &ids) == noErr else { return nil }
        var out: Set<pid_t> = []
        for id in ids {
            var output = address(kAudioProcessPropertyIsRunningOutput)
            var running: UInt32 = 0
            var rs = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &output, 0, nil, &rs, &running) == noErr, running == 1 else { continue }
            var pidAddress = address(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var ps = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &ps, &pid) == noErr, pid > 0 { out.insert(pid) }
        }
        return out
    }

    /// One reading of bytes coming in over a second, by process number, from Apple's nettop (any user can run it).
    public static func readDownloads(now: Date = Date()) -> Sample {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-L", "2", "-s", "1", "-d", "-n", "-x", "-J", "bytes_in,bytes_out"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Sample(at: now, bytesIn: [:]) }
        // it takes about a second; one that hangs is stopped
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Sample(at: now, bytesIn: bytesIn(nettop: String(decoding: data, as: UTF8.self)))
    }

    /// The second block of nettop's CSV ("name.pid,bytes_in,bytes_out,"): what came in during that second, by process.
    /// A name can hold commas and dots, so each row is read from the right.
    static func bytesIn(nettop: String) -> [pid_t: Double] {
        var blocks: [[Substring]] = []
        for line in nettop.split(separator: "\n") {
            if line.hasPrefix(",") { blocks.append([]) } else if !blocks.isEmpty { blocks[blocks.count - 1].append(line) }
        }
        var out: [pid_t: Double] = [:]
        for row in blocks.last ?? [] {
            let f = row.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 4, f[f.count - 1].isEmpty else { continue }
            let label = f[..<(f.count - 3)].joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = pid_t(label[label.index(after: dot)...]),
                  let bytes = Double(f[f.count - 3]), bytes > 0, bytes.isFinite else { continue }
            out[pid, default: 0] += bytes
        }
        return out
    }
}


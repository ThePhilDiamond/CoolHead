import Darwin
import Foundation
import IOKit

/// How much of the graphics chip each process uses, from the IORegistry, which any user can read with no permission
/// prompt. The approach comes from System Sentinel (https://github.com/andrewbakercloudscale/system-sentinel, MIT
/// License, Andrew Baker): each connection a process opens to the graphics chip (an IOAccelerator user client) says which
/// process made it ("IOUserClientCreator" = "pid 400, WindowServer") and, in "AppUsage", how much graphics-chip time it
/// has used ("accumulatedGPUTime", in nanoseconds). Two readings a few seconds apart give each process's share.
/// Tested on Apple Silicon (an M2 on macOS 26). On a Mac whose graphics driver doesn't publish AppUsage, nothing is
/// found and nothing changes.
public enum GPU {
    /// A process using this share of the graphics chip for over a minute becomes a suspect, like 0.5 cores of CPU.
    /// On the Mac it was built on, ordinary use (windows, Chrome, the Claude app) came to about 25% of the chip in all,
    /// most of it macOS drawing the screen (16%); half the chip for a minute is well past that.
    public static let busyShare = 0.5
    /// Below this, a process counts as quiet on the graphics chip again (the same half-way step as for CPU).
    public static let quietShare = 0.25

    /// Graphics-chip time each process has used, in nanoseconds, added up over all its connections to the chip.
    public static func times() -> [pid_t: UInt64] {
        var out: [pid_t: UInt64] = [:]
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(it) }
        var chip = IOIteratorNext(it)
        while chip != 0 {
            var clients: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(chip, kIOServicePlane, &clients) == KERN_SUCCESS {
                var c = IOIteratorNext(clients)
                while c != 0 {
                    if let creator = IORegistryEntryCreateCFProperty(c, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                       let pid = pid(creator: creator),
                       let usage = IORegistryEntryCreateCFProperty(c, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] {
                        out[pid, default: 0] &+= total(usage)
                    }
                    IOObjectRelease(c)
                    c = IOIteratorNext(clients)
                }
                IOObjectRelease(clients)
            }
            IOObjectRelease(chip)
            chip = IOIteratorNext(it)
        }
        return out
    }

    /// The process number in "pid 400, WindowServer".
    static func pid(creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        return pid_t(creator.dropFirst(4).prefix { $0.isNumber })
    }

    /// The graphics-chip time in one connection's AppUsage list, in nanoseconds.
    static func total(_ usage: [[String: Any]]) -> UInt64 {
        usage.reduce(0) { $0 &+ (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
    }

    /// The share of the graphics chip, 0 to 1, a process used between two readings `seconds` apart. A connection that
    /// closes takes its time with it, so a total that went down counts as none.
    public static func share(from a: UInt64, to b: UInt64, seconds: Double) -> Double {
        guard seconds > 0, b > a else { return 0 }
        return min(1, Double(b - a) / (seconds * 1e9))
    }
}

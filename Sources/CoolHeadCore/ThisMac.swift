import Foundation
import IOKit

/// This Mac's name, serial number, and startup disk space, for the This Mac page: for now, the space as free out of
/// total, with a button to macOS's own storage settings for the breakdown. All three are read without a password or a
/// macOS prompt. The serial number identifies the Mac, so it's shown on the page only: never in a problem report, the
/// shared database, or `coolhead` output (see SECURITY.md).
public enum ThisMac {
    /// "MacBook Air (M2, 2022)", from the device tree's product node; nil where there's none (Intel Macs).
    public static func modelName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The serial number, as About This Mac shows it.
    public static func serial() -> String? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let s = IORegistryEntryCreateCFProperty(entry, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        return s.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The startup disk's free space out of its size. Free is read as the memory card reads it (MacState), so the page
    /// and the card never give two numbers; low is the card's own line (MemoryAdvice.lowDiskBytes, 20 GB).
    public struct Space: Equatable {
        public let free: UInt64
        public let total: UInt64
        public init(free: UInt64, total: UInt64) { self.free = free; self.total = max(total, free) }
        public var low: Bool { free < MemoryAdvice.lowDiskBytes }
        /// How much is used, 0 to 1, for the bar.
        public var used: Double { total == 0 ? 0 : Double(total - free) / Double(total) }
        /// "12 GB free of 245 GB"
        public var text: String { "\(MemoryAdvice.diskGB(free)) free of \(MemoryAdvice.diskGB(total))" }
    }

    public static func space() -> Space? {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacity, let total = v.volumeTotalCapacity, free >= 0, total > 0 else { return nil }
        return Space(free: UInt64(free), total: UInt64(total))
    }

    /// macOS's own Storage page, with its breakdown (Documents, Applications, System Data, macOS) and recommendations:
    /// that breakdown comes from private parts of macOS, so Cool Head opens it rather than copying it.
    public static let storageSettings = "x-apple.systempreferences:com.apple.settings.Storage"
}

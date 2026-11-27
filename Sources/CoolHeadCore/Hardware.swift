import Darwin
import Foundation
import IOKit

/// Hardware checks that need no administrator password: the internal drive's own health record, the battery's condition
/// and why it isn't charging, crash restarts (kernel panics), and errors on the USB-C and MagSafe ports. Each is read the
/// way the signed-in user can read it, tested on an M2 MacBook Air with macOS 26.6.2 (an administrator account, without
/// sudo; a standard account is untested).
///
/// What can't be checked, said plainly where it matters: the memory can't be tested from inside macOS, and Apple
/// Diagnostics' results aren't saved anywhere an app can read. Apple silicon has no SMC or NVRAM to reset: a restart
/// does that job, and for a fault, Apple Diagnostics is the test (hold the power button until the startup options
/// appear, then press Command-D).
public struct HardwareReport {
    public var drive: DriveHealth?
    public var battery: BatteryHealth?
    public var crashes = CrashRestarts()
    public var ports: [PortErrors] = []
    public var appleSilicon = true
    /// Whether Time Machine has somewhere to back up to; nil: not read.
    public var timeMachine: TimeMachine? = nil
    /// The hottest of the chip's own temperature sensors, in °C (see `ChipTemperature`); nil where they can't be read.
    public var chipC: Double? = nil

    public init(drive: DriveHealth? = nil, battery: BatteryHealth? = nil, crashes: CrashRestarts = CrashRestarts(),
                ports: [PortErrors] = [], appleSilicon: Bool = true) {
        self.drive = drive; self.battery = battery; self.crashes = crashes; self.ports = ports; self.appleSilicon = appleSilicon
    }

    /// Reads everything. `profile` also asks System Information for the battery's condition and Maximum Capacity
    /// (about 0.15 s), which is worth doing once an hour, not every few minutes.
    public static func read(profile: Bool = true, now: Date = Date()) -> HardwareReport {
        var r = HardwareReport(drive: DriveHealth.read(), battery: BatteryHealth.read(profile: profile), crashes: CrashRestarts.read(now: now),
                               ports: PortErrors.read(), appleSilicon: (sysctlInt("hw.optional.arm64") ?? 0) == 1)
        r.timeMachine = TimeMachine.read()
        r.chipC = ChipTemperature.read()
        return r
    }
}

// MARK: - Backups

/// Whether Time Machine is set up, from `tmutil destinationinfo` (any user, about 0.01 s). When it last backed up isn't
/// read: Time Machine's settings file can't be opened without an administrator, and `tmutil latestbackup` tries to
/// mount the backup drive, which can stall on a network one (tested 16 November 2026, macOS 26.6.2, no destination set).
/// Sync apps (iCloud Drive, Google Drive, Dropbox, Box) aren't counted: they keep files the same everywhere, so a file
/// deleted or damaged here is deleted or damaged there too.
public enum TimeMachine: Equatable {
    case notSetUp, setUp
    public static func read() -> TimeMachine? {
        guard let out = Hardware.run("/usr/bin/tmutil", ["destinationinfo"]).map({ String(decoding: $0, as: UTF8.self) }) else { return nil }
        return out.contains("No destinations configured") ? .notSetUp : out.contains("Name") || out.contains("Kind") ? .setUp : nil
    }
}

// MARK: - The internal drive

/// The internal drive's own health record (NVMe SMART), through Apple's public plug-in for it
/// (IOKit/storage/nvme/NVMeSMARTLibExternal.h in the macOS SDK), which any user can open. Field meanings are the NVMe
/// specification's (section 5.10.1.2 of NVM Express 1.0c, which the header cites).
public struct DriveHealth: Equatable {
    public var criticalWarning: UInt8 = 0      // bit flags; 0 means none
    public var temperatureC: Int?              // reported in kelvin; 0 means not reported
    public var spare = 100                     // spare space left, percent
    public var spareThreshold = 0              // the drive warns below this
    public var percentUsed = 0                 // of its rated life; can pass 100
    public var dataUnitsWritten: UInt64 = 0    // each unit is 1,000 blocks of 512 bytes
    public var powerOnHours: UInt64 = 0
    public var unsafeShutdowns: UInt64 = 0
    public var mediaErrors: UInt64 = 0         // errors it couldn't correct
    public var errorLogEntries: UInt64 = 0

    public init() {}

    /// The 512-byte health record, as the drive returns it (little-endian).
    public static func parse(_ b: [UInt8]) -> DriveHealth? {
        guard b.count >= 192 else { return nil }
        // the counters are 128-bit; the low 64 bits are plenty for any drive
        func u64(_ o: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(b[o + $1]) << (8 * UInt64($1)) } }
        var d = DriveHealth()
        d.criticalWarning = b[0]
        let kelvin = Int(b[1]) | Int(b[2]) << 8
        d.temperatureC = kelvin > 0 ? kelvin - 273 : nil
        d.spare = Int(b[3]); d.spareThreshold = Int(b[4]); d.percentUsed = Int(b[5])
        d.dataUnitsWritten = u64(48); d.powerOnHours = u64(128); d.unsafeShutdowns = u64(144)
        d.mediaErrors = u64(160); d.errorLogEntries = u64(176)
        return d
    }

    public var bytesWritten: Double { Double(dataUnitsWritten) * 512_000 }
    /// The drive itself says something is wrong: a warning flag, or spare space below its own threshold.
    public var fault: Bool { criticalWarning != 0 || spare < spareThreshold }

    /// The warning flags in plain words (NVMe's critical-warning bits 0 to 4).
    public var warnings: [String] {
        [(0, "running out of spare space"), (1, "too hot or too cold"), (2, "less reliable than it should be"),
         (3, "read-only now"), (4, "backup power failed")].filter { criticalWarning & (1 << $0.0) != 0 }.map(\.1)
    }

    /// The facts behind a drive card.
    public var lines: [String] {
        var l = ["Health warnings: " + (warnings.isEmpty ? "none" : warnings.joined(separator: ", ")),
                 "Rated life used: \(percentUsed)%",
                 "Spare space: \(spare)% (it warns below \(spareThreshold)%)",
                 "Errors it couldn't correct: \(mediaErrors)",
                 "Written so far: about \(Hardware.size(bytesWritten))",
                 "Powered on for \(Hardware.count(powerOnHours)) hours",
                 "Times it lost power without shutting down: \(Hardware.count(unsafeShutdowns))"]
        if let t = temperatureC { l.append("Temperature: \(Fmt.temperature(Double(t)))") }
        return l
    }

    /// The internal drive's record, or nil if it has none this way (an Intel Mac's drive, say, or a future macOS that
    /// refuses).
    public static func read() -> DriveHealth? {
        // the drive advertises "NVMe SMART Capable" = Yes in the IORegistry
        let match = ["IOPropertyMatch": ["NVMe SMART Capable": true]] as CFDictionary
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var found: DriveHealth?
        var svc = IOIteratorNext(it)
        while svc != 0 {
            // the built-in drive is the one that matters; an external NVMe drive could also match, so keep the first
            if found == nil, let bytes = smartBytes(svc) { found = parse(bytes) }
            IOObjectRelease(svc)
            svc = IOIteratorNext(it)
        }
        return found
    }

    /// The plug-in's function table, laid out as IONVMeSMARTInterface in the SDK header: the COM basics, then version
    /// and revision, then SMARTReadData. Only the parts used here are declared.
    private struct SMARTInterface {
        var reserved: UnsafeMutableRawPointer?
        var queryInterface: @convention(c) (UnsafeMutableRawPointer?, REFIID, UnsafeMutablePointer<LPVOID?>?) -> HRESULT
        var addRef: @convention(c) (UnsafeMutableRawPointer?) -> ULONG
        var release: @convention(c) (UnsafeMutableRawPointer?) -> ULONG
        var version: UInt16
        var revision: UInt16
        var smartReadData: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn
    }

    private static func smartBytes(_ svc: io_service_t) -> [UInt8]? {
        // the header's UUIDs are C macros Swift can't import, so they're written out: kIOCFPlugInInterfaceID,
        // kIONVMeSMARTUserClientTypeID and kIONVMeSMARTInterfaceID
        guard let plugInID = CFUUIDGetConstantUUIDWithBytes(nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F),
              let clientID = CFUUIDGetConstantUUIDWithBytes(nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F),
              let interfaceID = CFUUIDGetConstantUUIDWithBytes(nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)
        else { return nil }
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(svc, clientID, plugInID, &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let table = plugIn.pointee?.pointee else { return nil }
        // IODestroyPlugInInterface stops the plug-in, which closes the drive's record, then releases it. Releasing alone
        // left the record open, and the drive lets only one program open it, so every later read failed until Cool
        // Head quit, and the page showed nothing about the drive.
        defer { IODestroyPlugInInterface(plugIn) }
        var raw: LPVOID?
        guard table.QueryInterface(plugIn, CFUUIDGetUUIDBytes(interfaceID), &raw) == S_OK, let raw else { return nil }
        let smart = raw.assumingMemoryBound(to: UnsafeMutablePointer<SMARTInterface>.self).pointee.pointee
        defer { _ = smart.release(raw) }
        var bytes = [UInt8](repeating: 0, count: 512)
        let result = bytes.withUnsafeMutableBytes { smart.smartReadData(raw, $0.baseAddress) }
        return result == kIOReturnSuccess ? bytes : nil
    }
}

// MARK: - The battery

/// The battery's condition and charging, from the AppleSmartBattery entry in the IORegistry (what `ioreg` and
/// `pmset -g batt` read) and, for the condition and Maximum Capacity as System Settings shows them, System Information.
/// The IORegistry's own capacity figures don't match System Settings (on the test Mac, 79% and 77% against its 81%), so
/// Maximum Capacity is taken from System Information rather than worked out.
public struct BatteryHealth: Equatable {
    public var condition: String?          // macOS's word, "Normal" when all is well
    public var maxCapacity: Int?           // percent of its original charge, as System Settings shows it
    public var cycles: Int?
    public var designCycles: Int?          // what Apple rates it for (1,000 on every Apple silicon MacBook)
    public var permanentFailure = 0        // non-zero: the battery's controller has recorded a permanent fault
    public var temperatureC: Double?
    public var percent: Int?
    public var onPower = false
    public var charging = false
    public var fullyCharged = false
    public var adapterWatts: Int?
    public var batteryWatts: Double?       // positive: charging; negative: draining
    public var notChargingReason: Int?     // macOS's own code, undocumented, so only shown as a fact

    public init() {}

    public var conditionNormal: Bool { condition.map { ["Normal", "Good"].contains($0) } ?? true }

    /// Why a Mac on power isn't charging, best guess first; nil when it is charging, is full, or isn't on power.
    public enum NotCharging: Equatable { case onHold(Int), tooWarm(Double), chargerTooWeak(Int?), unknown }
    public var notCharging: NotCharging? {
        guard onPower, !charging, !fullyCharged, let pct = percent, pct < 100 else { return nil }
        // the Mac using more than the charger gives drains the battery even plugged in
        if let w = batteryWatts, w < -1 { return .chargerTooWeak(adapterWatts) }
        // charging pauses while the battery is warm: one test on an M1 MacBook Air saw it stop at 44°C (Thomas Kaiser,
        // cited by Howard Oakley); 40°C leaves room for a warmer sensor elsewhere
        if let t = temperatureC, t >= 40 { return .tooWarm(t) }
        // Optimized Battery Charging holds at 80%; a Charge Limit (macOS 26.4 or later) at 80% to 100%
        if pct >= 78 { return .onHold(pct) }
        return .unknown
    }

    public var lines: [String] {
        var l: [String] = []
        if let c = condition { l.append("Condition: " + (conditionNormal ? "Normal" : c)) }
        if let m = maxCapacity { l.append("Maximum Capacity: \(m)%") }
        if let c = cycles { l.append("Charge cycles: \(Hardware.count(UInt64(c)))" + (designCycles.map { " (rated for \(Hardware.count(UInt64($0))))" } ?? "")) }
        if permanentFailure != 0 { l.append("Permanent fault recorded: yes") }
        if let t = temperatureC { l.append("Temperature: \(Fmt.temperature(t))") }
        if let p = percent { l.append("Charge: \(p)%" + (charging ? ", charging" : onPower ? ", on power, not charging" : "")) }
        if let w = adapterWatts { l.append("Charger: \(w) W") }
        if let w = batteryWatts, onPower, w < -1 { l.append(String(format: "Battery draining at %.0f W while plugged in", -w)) }
        if let r = notChargingReason, r != 0, notCharging != nil { l.append(String(format: "macOS's not-charging code: 0x%X", r)) }
        return l
    }

    /// nil on a Mac with no battery.
    public static func read(profile: Bool) -> BatteryHealth? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        guard (d["BatteryInstalled"] as? Bool) ?? true else { return nil }
        var b = BatteryHealth()
        func int(_ k: String, _ dict: [String: Any]? = nil) -> Int? { ((dict ?? d)[k] as? NSNumber)?.intValue }
        b.cycles = int("CycleCount")
        b.designCycles = int("DesignCycleCount9C")
        b.permanentFailure = int("PermanentFailureStatus") ?? 0
        if let t = int("Temperature") { b.temperatureC = Double(t) / 100 }      // hundredths of a degree
        b.percent = int("CurrentCapacity")
        if let cur = b.percent, let max = int("MaxCapacity"), max > 100 { b.percent = Int((Double(cur) / Double(max) * 100).rounded()) }
        b.onPower = (d["ExternalConnected"] as? Bool) ?? false
        b.charging = (d["IsCharging"] as? Bool) ?? false
        b.fullyCharged = (d["FullyCharged"] as? Bool) ?? false
        if let a = d["AdapterDetails"] as? [String: Any], let w = int("Watts", a), w > 0 { b.adapterWatts = w }
        if let v = int("Voltage"), let amps = (d["Amperage"] as? NSNumber)?.int64Value {
            b.batteryWatts = Double(v) / 1000 * Double(Int(truncatingIfNeeded: amps)) / 1000
        }
        if let c = d["ChargerData"] as? [String: Any] { b.notChargingReason = int("NotChargingReason", c) }
        if profile, let data = Hardware.run("/usr/sbin/system_profiler", ["-json", "SPPowerDataType"]) {
            (b.condition, b.maxCapacity) = parseProfile(data)
        }
        return b
    }

    /// The condition and Maximum Capacity from System Information's battery report (its JSON form, which says "Good"
    /// where the text form says "Normal").
    public static func parseProfile(_ data: Data) -> (condition: String?, maxCapacity: Int?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return (nil, nil) }
        for item in items {
            guard let h = item["sppower_battery_health_info"] as? [String: Any] else { continue }
            let condition = h["sppower_battery_health"] as? String
            let cap = (h["sppower_battery_health_maximum_capacity"] as? String).flatMap { Int($0.filter(\.isNumber)) }
            return (condition, cap)
        }
        return (nil, nil)
    }
}

// MARK: - Crash restarts (kernel panics)

/// The last kernel panic, and whether the restart that began this session followed one. macOS keeps a summary of the
/// last panic in /Library/Logs/DiagnosticReports/.contents.panic (readable by every user) and, for each startup, a
/// "breadcrumb" naming the panic report it wrote, empty when there was none (/var/db/com.apple.DumpPanic.
/// panicLogPathBreadcrumb, keyed by `kern.bootsessionuuid`). Howard Oakley describes both; Apple says most panics are
/// software, but damaged hardware or a faulty accessory can cause them.
public struct CrashRestarts: Equatable {
    public var lastText: String?               // the last panic's report, as macOS wrote it
    public var lastDate: Date?
    public var thisStartFollowedCrash: Bool?   // nil: can't tell
    public var recent: [Date]?                 // panic reports from the last 7 days; nil: the folder can't be read

    public init(lastText: String? = nil, lastDate: Date? = nil, thisStartFollowedCrash: Bool? = nil, recent: [Date]? = nil) {
        self.lastText = lastText; self.lastDate = lastDate; self.thisStartFollowedCrash = thisStartFollowedCrash; self.recent = recent
    }

    static let folder = "/Library/Logs/DiagnosticReports"
    static let breadcrumb = "/var/db/com.apple.DumpPanic.panicLogPathBreadcrumb"

    public static func read(now: Date = Date()) -> CrashRestarts {
        var c = CrashRestarts()
        let summary = folder + "/.contents.panic"
        if let data = FileManager.default.contents(atPath: summary),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            c.lastText = json["panic_string"] as? String
            c.lastDate = (try? FileManager.default.attributesOfItem(atPath: summary))?[.modificationDate] as? Date
        }
        if let uuid = sysctlString("kern.bootsessionuuid"), let data = FileManager.default.contents(atPath: breadcrumb),
           let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
           let entry = plist[uuid] as? String {
            c.thisStartFollowedCrash = !entry.isEmpty
        }
        // the full reports, named panic-full-<date>.panic, if this account may list the folder (an administrator can;
        // a standard account is untested)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: folder) {
            let weekAgo = now.addingTimeInterval(-7 * 86400)
            c.recent = names.filter { $0.hasPrefix("panic") && $0.hasSuffix(".panic") }.compactMap {
                (try? FileManager.default.attributesOfItem(atPath: folder + "/" + $0))?[.modificationDate] as? Date
            }.filter { $0 > weekAgo }
        }
        return c
    }

    /// Crashes in the last 7 days: the reports in the folder, or at least the last one if the folder can't be read.
    public func countThisWeek(now: Date) -> Int {
        let fromSummary = lastDate.map { now.timeIntervalSince($0) < 7 * 86400 } == true ? 1 : 0
        return max(recent?.count ?? 0, fromSummary)
    }

    /// What the report says caused it, as far as it can be read (Howard Oakley's reading rules).
    public enum Cause: Equatable { case stoppedResponding(String), kernelMemory, driver(String), unclear }
    public static func cause(_ text: String) -> Cause {
        // "userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds"
        if let r = text.range(of: "no successful checkins from ") {
            let name = text[r.upperBound...].prefix { !$0.isWhitespace && $0 != "(" }
            if !name.isEmpty { return .stoppedResponding(String(name)) }
        }
        if text.lowercased().contains("zone map") { return .kernelMemory }
        // a driver that isn't Apple's, listed under "Kernel Extensions in backtrace:" as "com.maker.driver(1.0)[...]"
        if let r = text.range(of: "Kernel Extensions in backtrace:") {
            for line in text[r.upperBound...].split(separator: "\n").prefix(12) {
                let id = line.trimmingCharacters(in: .whitespaces).prefix { $0 != "(" && $0 != "[" && !$0.isWhitespace }
                if id.contains("."), !id.hasPrefix("com.apple.") { return .driver(String(id)) }
            }
        }
        return .unclear
    }

    /// What the cause means, in plain words, for the crash card and the Hardware page alike: what stopped and whether
    /// that's usually software or hardware, since a bare "WindowServer stopped responding" needs explaining, along with
    /// what to do about it.
    public static func plainCause(_ c: Cause) -> [String] {
        switch c {
        case .stoppedResponding(let name):
            let what = name == "WindowServer" ? "WindowServer, the part of macOS that draws the screen," : name
            return ["\(what.prefix(1).uppercased() + what.dropFirst()) stopped responding, so macOS restarted.", "Software usually causes this, not hardware."]
        case .kernelMemory:
            return ["macOS ran out of its own working memory, which is usually a leak in software, often a driver."]
        case .driver(let id):
            return ["The report names \(id), a driver that Apple did not make.", "Update it from its maker, or remove it."]
        case .unclear:
            return ["The report from macOS does not show the cause of the last crash.", "Most crashes are software, but a faulty accessory or a hardware fault can cause them."]
        }
    }

    public var lines: [String] {
        var l: [String] = []
        if let d = lastDate { l.append("Last crash restart: \(Fmt.time(d))") } else { l.append("Last crash restart: none recorded") }
        if let first = lastText?.split(separator: "\n").first { l.append("Report: " + String(first).replacingOccurrences(of: #"^panic\([^)]*\): "#, with: "", options: .regularExpression)) }
        if let r = recent { l.append("Crash restarts in the last 7 days: \(r.count)") }
        if let t = thisStartFollowedCrash { l.append("This startup followed a crash: " + (t ? "yes" : "no")) }
        return l
    }
}

// MARK: - USB-C and MagSafe ports

/// Error counters on each port, from the IORegistry: each USB port's "port-statistics" (over-current, failed
/// enumeration, failed address) and "link-error-count", and each USB-C or MagSafe port controller's "Overcurrent Count".
/// All read 0 on the test Mac with nothing attached; what a real fault writes, and when the counters reset (they seem to
/// start again when a port powers up), is untested, so failures to connect are a note, not a warning.
public struct PortErrors: Equatable {
    public var name: String                // "USB-C port 1", "the MagSafe port", "a port on a hub"
    public var overCurrent = 0
    public var failedToConnect = 0
    public var linkErrors = 0

    public init(name: String, overCurrent: Int = 0, failedToConnect: Int = 0, linkErrors: Int = 0) {
        self.name = name; self.overCurrent = overCurrent; self.failedToConnect = failedToConnect; self.linkErrors = linkErrors
    }

    public var any: Bool { overCurrent + failedToConnect + linkErrors > 0 }

    /// Every port with a non-zero counter, one entry per port (a USB-C port's USB 2 and USB 3 halves count as one).
    public static func read() -> [PortErrors] {
        var byName: [String: PortErrors] = [:]
        var order: [String] = []
        func add(_ p: PortErrors) {
            if byName[p.name] == nil { order.append(p.name); byName[p.name] = PortErrors(name: p.name) }
            byName[p.name]!.overCurrent += p.overCurrent
            byName[p.name]!.failedToConnect += p.failedToConnect
            byName[p.name]!.linkErrors += p.linkErrors
        }
        each("AppleUSBHostPort") { d in
            let stats = d["port-statistics"] as? [String: Any] ?? [:]
            func n(_ k: String, _ dict: [String: Any]) -> Int { (dict[k] as? NSNumber)?.intValue ?? 0 }
            let name = (d["UsbCPortNumber"] as? NSNumber).map { "USB-C port \($0.intValue)" } ?? "a port on a hub"
            add(PortErrors(name: name, overCurrent: n("kPortStatOverCurrentCount", stats),
                           failedToConnect: n("kPortStatEnumerationFailureCount", stats) + n("kPortStatAddressFailureCount", stats),
                           linkErrors: n("link-error-count", d)))
        }
        each("IOAccessoryManager") { d in
            guard let over = (d["Overcurrent Count"] as? NSNumber)?.intValue else { return }
            let type = d["PortTypeDescription"] as? String ?? "USB-C"
            let number = (d["PortNumber"] as? NSNumber)?.intValue
            let name = type.hasPrefix("MagSafe") ? "the MagSafe port" : "\(type) port" + (number.map { " \($0)" } ?? "")
            add(PortErrors(name: name, overCurrent: over))
        }
        return order.compactMap { byName[$0] }.filter(\.any)
    }

    private static func each(_ cls: String, _ body: ([String: Any]) -> Void) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var svc = IOIteratorNext(it)
        while svc != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] { body(d) }
            IOObjectRelease(svc)
            svc = IOIteratorNext(it)
        }
    }
}

// MARK: - Cards

extension HardwareReport {
    /// This report with the battery's live temperature and charging (read every 10 seconds) when its heat level has
    /// changed since the report was read, so the battery's card, the heat dial, the snowflake, and the Power page agree
    /// within one sample rather than up to 10 minutes apart; nil when nothing changed.
    public func followingLive(_ mac: MacState) -> HardwareReport? {
        guard var b = battery, let t = mac.batteryTempC else { return nil }
        let was = b.temperatureC.map { HardwarePage.batteryHeatLevel($0, charging: b.charging) } ?? 0
        guard HardwarePage.batteryHeatLevel(t, charging: mac.charging) != was else { return nil }
        b.temperatureC = t; b.charging = mac.charging
        var r = self; r.battery = b
        return r
    }

    /// A card for each hardware finding worth showing, worst first. Nothing found, no cards: the panel stays as it is.
    public func cards(now: Date = Date()) -> [LiveCard] {
        var out: [LiveCard] = []
        func card(_ id: String, _ state: JobState, _ t: CardTemplate, _ fixes: [Fix], _ details: [String], subject: String,
                  serious: Bool = false, safety: Bool = false) {
            var c = LiveCard(id: "hardware-\(id)", pid: nil, card: Card(state: state, t, fixes: fixes), details: details)
            c.causeKey = "hardware-\(id)"
            c.serious = serious; c.safety = safety
            c.displaySubject = subject
            c.reportSubject = subject
            out.append(c)
        }
        let diagnostics = Hardware.diagnostics(appleSilicon: appleSilicon)
        let backup = Hardware.backUp

        // the drive is built into the Mac: if it fails, what's on it can be lost
        if let d = drive {
            let soldered = ["The drive is built into the Mac. If it fails, you can lose what is on it, and the repair is a new main board."]
            if d.fault {
                card("drive", .unknown, CardTemplate("the Mac's internal drive", .words("reports a fault"), .mayFail,
                                                     evidence: ["Its own health check warns that it is \(d.warnings.isEmpty ? "running out of spare space" : Fmt.list(d.warnings))."], effect: soldered),
                     [Hardware.recommend(backup), diagnostics], d.lines, subject: "the internal drive")
            } else if d.mediaErrors > 0 {
                card("drive", .unknown, CardTemplate("the Mac's internal drive", .words("found errors it cannot correct"), .mayFail,
                                                     evidence: ["Its own health check counted \(Hardware.count(d.mediaErrors)) of these errors in its life.",
                                                                "A few can be harmless, but they are often the first sign of a failing drive."],
                                                     effect: ["The drive is built into the Mac, so if it fails, you lose what is on it and need a new main board."]),
                     [Hardware.recommend(backup), Hardware.diagnostics(appleSilicon: appleSilicon, code: "A code that starts with VDH means a drive fault.")],
                     d.lines, subject: "the internal drive")
            } else if d.percentUsed >= 80 {
                card("drive", .quiet, CardTemplate("the Mac's internal drive", .words(d.percentUsed >= 100 ? "is past its rated life" : "is \(d.percentUsed)% of the way through its rated life"), .normalWear,
                                                   evidence: ["Drives wear a little with every write, but this one still works with no errors, and many drives run well past their rating."],
                                                   effect: ["Keep your backups current. When memory is full, macOS moves data to this drive, which adds to the wear."]),
                     [backup], d.lines, subject: "the internal drive")
            }
        }

        if let b = battery {
            let swollen = "If the case bulges, the lid does not close flat, or the trackpad feels raised, stop using the Mac and take it to Apple. A swollen battery is a fire risk."
            let check = Fix.guide("battery", "Check the battery with Apple's steps", "This shows Apple's steps. They take a few minutes, and the last step restarts the Mac.", steps: [
                "Choose \(Fmt.path("Apple menu", "System Settings", "Battery")), and click the ⓘ next to \(Fmt.ui("Battery Health")).",
                "Make sure \(Fmt.ui("Optimized Battery Charging")) is on.",
                "Charge with the adapter that came with the Mac, or one with as many watts.",
                "Shut down the Mac, close the lid for 30 seconds, then start it again.",
                "If it still says Service Recommended, run Apple Diagnostics and contact Apple.",
                swollen])
            if b.permanentFailure != 0 {
                card("battery", .unknown, CardTemplate("the battery", .words("recorded a fault"), .needsService,
                                                       evidence: ["Its controller marked a permanent failure, so it may not charge or hold a charge properly."],
                                                       effect: ["Have Apple check it. Apple Diagnostics names battery faults with a code that starts with PPT."]),
                     [diagnostics, Hardware.note(swollen)], b.lines, subject: "the battery")
            } else if !b.conditionNormal {
                card("battery", .unknown, CardTemplate("the battery", nil, .needsService,
                                                       evidence: ["macOS rates its condition as \(b.condition ?? "Service Recommended"), because it holds less charge than when it was new or does not work normally."],
                                                       effect: [(b.maxCapacity.map { "It holds \($0)% of its original charge, and Apple" } ?? "Apple") + " says the Mac is safe to keep using."]),
                     [Hardware.recommend(check), diagnostics], b.lines, subject: "the battery")
            } else if let m = b.maxCapacity, m < 80 {
                let rated = b.designCycles.map { "Apple rates it to keep 80% for \(Hardware.count(UInt64($0))) cycles" } ?? "Apple rates it to keep 80% for 1,000 cycles"
                card("battery", .quiet, CardTemplate("the battery", .words("holds \(m)% of its original charge"), .normalWear,
                                                     evidence: [rated + (b.cycles.map { ", and it is at \(Hardware.count(UInt64($0))) cycles." } ?? ".")],
                                                     effect: ["Batteries wear with use, so you get less time on battery. Below 80%, AppleCare replaces it."]),
                     [check], b.lines, subject: "the battery")
            }
            // plugged in but not charging: usually on purpose, so a calm card that says why
            if let why = b.notCharging {
                switch why {
                case .onHold(let pct):
                    card("charging", .quiet, CardTemplate("Charging", .words("is on hold at \(pct)%"), .normal,
                                                          evidence: ["Optimized Battery Charging, or a Charge Limit you set, probably holds it."],
                                                          effect: ["The hold slows battery wear, and your Mac charges to full before you usually unplug it."]),
                         [Fix.guide("full", "Charge to full now", "This charges to 100% once, then goes back to normal.", steps: ["Click the battery in the menu bar.", "Choose \(Fmt.ui("Charge to Full Now")). If it is not there, the hold is a Charge Limit. Change it in \(Fmt.path("System Settings", "Battery"))."])],
                         b.lines, subject: "charging")
                case .tooWarm(let t) where HardwarePage.batteryHeatLevel(t, charging: b.charging) == 0:
                    card("charging", .quiet, CardTemplate("the battery", .words("is too warm to charge"), .normal,
                                                          evidence: ["It is at \(Fmt.temperature(t)), and a Mac pauses charging while its battery is warm."],
                                                          effect: ["Charging starts again when it cools. Use the Mac on a hard surface, out of the sun, and give it a break from heavy work."]),
                         [], b.lines, subject: "charging")
                case .tooWarm:
                    break                       // the battery temperature card below says it, and that charging has paused
                case .chargerTooWeak(let w):
                    card("charging", .quiet, CardTemplate("the charger", .words("does not give enough power"), .batteryDrains,
                                                          evidence: ["Your Mac uses more power than " + (w.map { "the \($0) W charger" } ?? "the charger") + " gives."],
                                                          effect: ["Use a charger with more watts, or plug it straight into the Mac, not through a hub or display. You can also lower the load."]),
                         [], b.lines, subject: "charging")
                case .unknown:
                    card("charging", .quiet, CardTemplate("Your Mac", .words("is plugged in but does not charge"), nil,
                                                          evidence: ["The battery is not warm and not near a charge limit."],
                                                          effect: ["Try another cable, socket, or charger, then restart the Mac. If it still does not charge, run Apple Diagnostics."]),
                         [diagnostics], b.lines, subject: "charging")
                }
            }
        }

        // heat beyond the battery's or drive's own line needs a look, so it's warned on, as the heat dial shows it;
        // the battery's says when it has paused charging, in place of that card
        if let b = battery, let t = b.temperatureC, HardwarePage.batteryHeatLevel(t, charging: b.charging) > 0 {
            let hot = HardwarePage.batteryHeatLevel(t, charging: b.charging) == 2
            let paused = b.notCharging.map { if case .tooWarm = $0 { return true }; return false } ?? false
            card("battery-heat", .unknown, CardTemplate("the battery", .words("is \(hot ? "hot" : "warm"), at \(Fmt.temperature(t))"), .letItCool,
                                                        evidence: ["A battery is warm from \(Fmt.temperature(40)) and hot from \(Fmt.temperature(45)), and heat wears it faster."]
                                                            + (paused ? ["macOS paused charging until it cools."] : []),
                                                        effect: ["Use the Mac on a hard surface, out of the sun, and give it a break from heavy work."]),
                 [], b.lines, subject: "the battery's temperature", serious: hot, safety: true)
        }
        if let d = drive, let t = d.temperatureC, HardwarePage.driveHeatLevel(Double(t)) > 0 {
            card("drive-heat", .unknown, CardTemplate("the internal drive", .words("is warm, at \(Fmt.temperature(Double(t)))"), .letItCool,
                                                      evidence: ["Drives usually run cooler. Cool Head's line is \(Fmt.temperature(70))."],
                                                      effect: ["Long copies and a hot Mac warm it, and heat wears it faster. Give the Mac a break, out of the sun."]),
                 [], d.lines, subject: "the drive's temperature", safety: true)
        }

        // crash restarts: one after a crash is worth a look; several in a week more so
        let week = crashes.countThisWeek(now: now)
        if crashes.thisStartFollowedCrash == true || week >= 2 {
            let why = CrashRestarts.plainCause(crashes.lastText.map(CrashRestarts.cause) ?? .unclear)
            let t = week >= 2 ? CardTemplate("Your Mac", .words("crashed and restarted \(week) times this week"), .moreThanUsual)
                              : CardTemplate("Your Mac", .words("restarted because of a crash"), nil)
            // what macOS says caused it; after several in a week, that repeated crashes can point to hardware. The next
            // steps after Safe Mode are said on the options, where the reader acts on them
            let evidence = week >= 2 ? [why[0], "Most crashes are software, but crashes that keep happening can point to a faulty accessory or hardware."] : why
            let next = week >= 2 ? "Disconnect docks and hubs, then try Safe Mode." : "If it happens again, disconnect docks and hubs, then try Safe Mode."
            let safeMode = Fix.guide("safemode", "Try Safe Mode", "This starts the Mac with only Apple's software. If the crashes stop there, the cause is software you added. If they do not stop, run Apple Diagnostics.", steps: appleSilicon ? [
                "Save your work and shut down the Mac.",
                "Press and hold the power button until the startup options appear, then let go.",
                "Click your startup disk, then hold Shift and click Continue in Safe Mode.",
                "Use the Mac as usual, then restart normally to leave Safe Mode."] : [
                "Save your work and shut down the Mac.",
                "Press the power button, then at once press and hold Shift until the login window appears.",
                "Use the Mac as usual, then restart normally to leave Safe Mode."])
            card("crash", .unknown, CardTemplate(t.subject, t.reading, t.verdict, evidence: evidence, effect: [next]),
                 [safeMode, Hardware.diagnostics(appleSilicon: appleSilicon, note: "It also tests the memory, which Cool Head cannot.")],
                 crashes.lines, subject: "crash restarts")
        }

        // ports: too much power is Apple's "USB Devices Disabled"; failures to connect are a note
        for p in ports {
            if p.overCurrent > 0 {
                let magsafe = p.name.hasPrefix("the MagSafe")
                card("port-\(p.name)", .unknown, CardTemplate("a device", .words("asked \(p.name) for more power than it can give"), nil,
                                                              evidence: ["The port recorded this \(Hardware.times(p.overCurrent))."],
                                                              effect: [magsafe ? "Try another MagSafe cable or charger, and check the connector for dirt or damage."
                                                                               : "Each time, macOS turns the port off, and may show a USB Devices Disabled message."]),
                     magsafe ? [diagnostics] : [Hardware.recommend(Hardware.lessPower), diagnostics],
                     ["Port: \(p.name)", "Too much power asked for: \(Hardware.times(p.overCurrent))"], subject: p.name)
            } else {
                let n = p.failedToConnect + p.linkErrors
                card("port-\(p.name)", .quiet, CardTemplate("a device on \(p.name)", .words("failed to connect \(Hardware.times(n))"), nil,
                                                            evidence: ["The port counted each failed attempt after it last started."],
                                                            effect: ["A worn or loose cable is the usual cause, so try another cable or port. If devices keep dropping on every port, run Apple Diagnostics."]),
                     [diagnostics], ["Port: \(p.name)", "Failed to connect: \(Hardware.times(p.failedToConnect))", "Link errors: \(Hardware.times(p.linkErrors))"], subject: p.name)
            }
        }
        // worst first: needs a look before notes
        return out.enumerated().sorted { ($0.element.needsLook ? 0 : 1, $0.offset) < ($1.element.needsLook ? 0 : 1, $1.offset) }.map(\.element)
    }

    /// Every check in plain lines, for `coolhead hardware`: what was found, then what can't be checked.
    public func summary() -> [String] {
        var l: [String] = []
        l.append("Internal drive")
        l += drive.map { $0.lines } ?? ["  Its health record can't be read on this Mac."]
        l.append("Battery")
        l += battery.map { $0.lines } ?? ["  No battery."]
        l.append("Crash restarts")
        l += crashes.lines
        l.append("Ports")
        l += ports.isEmpty ? ["No errors counted on any USB-C or MagSafe port."] : ports.map { "\($0.name): too much power asked for \(Hardware.times($0.overCurrent)), failed to connect \(Hardware.times($0.failedToConnect)), link errors \(Hardware.times($0.linkErrors))" }
        l.append("Not checked")
        l += Hardware.limits(appleSilicon: appleSilicon)
        return l.map { ["Internal drive", "Battery", "Crash restarts", "Ports", "Not checked"].contains($0) ? $0 : "  " + $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Shared wording and small helpers for the hardware checks.
public enum Hardware {
    /// What Cool Head can't check, said plainly.
    public static func limits(appleSilicon: Bool) -> [String] {
        var l = ["The memory can't be tested from inside macOS; Apple Diagnostics is the test.",
                 "Apple Diagnostics' results aren't saved anywhere Cool Head can read."]
        if appleSilicon {
            l.append("Apple silicon Macs have no SMC or NVRAM to reset; a restart does that job.")
            l.append("To run Apple Diagnostics: shut down, hold the power button until the startup options appear, then press and hold Command-D.")
        } else {
            l.append("To run Apple Diagnostics: shut down, press the power button, then at once press and hold D.")
        }
        return l
    }

    /// Apple's hardware test. `note`: a sentence added to what it does, for the card that needs it (crashes: it tests
    /// the memory); `code`: what a code it shows means, as a last step, for the part the card is about (the drive).
    static func diagnostics(appleSilicon: Bool, note: String? = nil, code: String? = nil) -> Fix {
        Fix.guide("diagnostics", "Run Apple Diagnostics", "This shows how to run Apple's own hardware test." + (note.map { " " + $0 } ?? "")
                    + " It restarts the Mac and takes a few minutes, so save your work first.", steps: (appleSilicon ? [
            "Save your work and shut down the Mac.",
            "Press and hold the power button until the startup options appear, then let go.",
            "Press and hold Command-D until the test starts.",
            "Write down any code it shows, and give it to Apple."] : [
            "Save your work and shut down the Mac.",
            "Press the power button, then at once press and hold D until the test starts.",
            "Write down any code it shows, and give it to Apple."]) + [code].compactMap { $0 })
    }

    static let backUp = Fix.guide("backup", "Back up now", "This shows how to copy your files to another drive, so nothing is lost if this one fails.", steps: [
        "Connect your backup drive.",
        "Click the Time Machine icon in the menu bar and choose \(Fmt.ui("Back Up Now")).",
        "If you do not use Time Machine yet, set it up in \(Fmt.path("System Settings", "General", "Time Machine")).", "Or copy what matters to another drive."])

    static let lessPower = Fix.guide("power", "Give the device the power it needs", "This shows Apple's steps for a device that wants too much power.", steps: [
        "Unplug the device, then plug it in again.",
        "Try another port.",
        "If it is on a hub, plug it straight into the Mac.",
        "If the hub has its own power adapter, make sure it is connected to power."])

    static func note(_ text: String) -> Fix { Fix.guide("note", "Check for a swollen battery", "This shows the signs. If you see them, stop using the Mac.", steps: [text]) }

    static func recommend(_ f: Fix) -> Fix { var f = f; f.recommended = true; return f }

    static func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }

    static func count(_ n: UInt64) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func size(_ bytes: Double) -> String {
        bytes >= 1e12 ? String(format: "%.0f TB", bytes / 1e12) : String(format: "%.0f GB", bytes / 1e9)
    }

    /// Runs a macOS tool and returns what it printed, or nil if it fails or takes over 10 seconds.
    static func run(_ path: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + 10) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

// MARK: - The chip's temperature

/// The hottest of the chip's own temperature sensors, the "PMU tdie" sensors on Apple silicon, read through macOS's
/// sensor service (`IOHIDEventSystemClient`), which Apple doesn't document: its functions are looked up by name when
/// first used, as for `SLSEventIsAppUnresponsive` (see SECURITY.md). Read-only, and no permission is needed. If a
/// future macOS renames or removes them, this returns nil and the chip's temperature simply isn't shown, which is what
/// makes it safe to read. It never decides a card: macOS's own four thermal steps do.
public enum ChipTemperature {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

    private struct Functions {
        let create: Create, setMatching: SetMatching, copyServices: CopyServices
        let copyEvent: CopyEvent, getFloat: GetFloat, copyProperty: CopyProperty
    }
    private static let functions: Functions? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func f<T>(_ name: String, _ type: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: type) } }
        guard let a = f("IOHIDEventSystemClientCreate", Create.self), let b = f("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let c = f("IOHIDEventSystemClientCopyServices", CopyServices.self), let d = f("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let e = f("IOHIDEventGetFloatValue", GetFloat.self), let g = f("IOHIDServiceClientCopyProperty", CopyProperty.self)
        else { return nil }
        return Functions(create: a, setMatching: b, copyServices: c, copyEvent: d, getFloat: e, copyProperty: g)
    }()

    /// Temperature sensors (Apple's vendor usage page 0xff00, usage 5) and their temperature events (type 15).
    static let temperatureEvent: Int64 = 15

    /// Every temperature sensor's name and reading, in °C.
    public static func sensors() -> [(name: String, celsius: Double)] {
        guard let fn = functions, let client = fn.create(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
        _ = fn.setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = fn.copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        return services.compactMap { s in
            guard let name = fn.copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = fn.copyEvent(s, temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return (name, fn.getFloat(event, Int32(temperatureEvent << 16)))
        }
    }

    /// The hottest chip sensor: names containing "tdie", within what a chip can read (a sensor that isn't fitted reads
    /// below zero). Nil on a Mac without them, such as an Intel Mac, or if macOS stops providing them.
    public static func hottest(_ sensors: [(name: String, celsius: Double)]) -> Double? {
        sensors.filter { $0.name.contains("tdie") && (1...150).contains($0.celsius) }.map(\.celsius).max()
    }

    public static func read() -> Double? { hottest(sensors()) }
}

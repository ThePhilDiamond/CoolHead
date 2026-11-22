import Darwin
import Foundation
import IOKit

/// The whole Mac's state right now: heat, power, battery and memory.
public struct MacState {
    public var thermal: String = "unknown"           // nominal, fair, serious, critical (macOS's own words)
    public var batteryPercent: Int?
    public var charging = false
    public var onPower = false
    public var adapterWatts: Int?
    public var macWatts: Double?                      // what the Mac itself is using (SystemLoad)
    public var batteryWatts: Double?                  // positive: charging; negative: draining
    public var healthPercent: Int?                    // how much of its original charge the battery holds
    public var cycles: Int?
    public var batteryTempC: Double?
    public var memoryPressure = "unknown"             // normal, warning, critical
    public var swapUsedMB = 0.0
    public var swapTotalMB = 0.0
    /// Free space on the startup disk, not counting space macOS may or may not free (purgeable). Swap files share it,
    /// so when it runs out the Mac can't add more (Howard Oakley's test on macOS 26.6.2).
    public var diskFreeBytes: UInt64?
    /// Pages moved from memory to the swap files since startup; the Watcher turns them into `swappedOutMB`.
    public var swapOutPages: UInt64?
    /// Memory moved to the disk in about the last 2 minutes (set by the Watcher from `swapOutPages`).
    public var swappedOutMB: Double?
    public var memoryGB = 0.0
    public var cores = 0
    public var performanceCores = 0
    public var efficiencyCores = 0

    public static func read() -> MacState {
        var s = MacState()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: s.thermal = "nominal"
        case .fair: s.thermal = "fair"
        case .serious: s.thermal = "serious"
        case .critical: s.thermal = "critical"
        @unknown default: s.thermal = "unknown"
        }
        s.cores = sysctlInt("hw.ncpu") ?? 0
        s.performanceCores = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        s.efficiencyCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        s.memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        switch sysctlInt("kern.memorystatus_vm_pressure_level") {
        case 1: s.memoryPressure = "normal"
        case 2: s.memoryPressure = "warning"
        case 4: s.memoryPressure = "critical"
        default: break
        }
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 {
            s.swapUsedMB = Double(xsw.xsu_used) / 1_048_576
            s.swapTotalMB = Double(xsw.xsu_total) / 1_048_576
        }
        if let free = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity, free >= 0 {
            s.diskFreeBytes = UInt64(free)
        }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if r == KERN_SUCCESS { s.swapOutPages = vm.swapouts }
        s.readBattery()
        return s
    }

    /// Memory is tight: macOS says so (warning or critical), or the Mac is moving a lot of memory to its disk while
    /// macOS still says normal (one report, untested, says the level can stay normal during heavy swapping; research
    /// node N-002). "warning" or "critical", or nil when memory is fine.
    public var memoryLevel: String? {
        if memoryPressure == "warning" || memoryPressure == "critical" { return memoryPressure }
        if memoryPressure == "normal", let mb = swappedOutMB, mb >= MemoryAdvice.heavySwapMB { return "warning" }
        return nil
    }

    mutating func readBattery() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }
        func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
        batteryPercent = int("CurrentCapacity")
        // Intel MacBooks report capacity in mAh rather than percent
        if let cur = batteryPercent, let max = int("MaxCapacity"), max > 100 { batteryPercent = Int((Double(cur) / Double(max) * 100).rounded()) }
        charging = (d["IsCharging"] as? Bool) ?? false
        onPower = (d["ExternalConnected"] as? Bool) ?? false
        cycles = int("CycleCount")
        if let raw = int("AppleRawMaxCapacity"), let design = int("DesignCapacity"), design > 0 {
            healthPercent = Int((Double(raw) / Double(design) * 100).rounded())
        }
        if let t = int("Temperature") { batteryTempC = Double(t) / 100 }
        if let a = d["AdapterDetails"] as? [String: Any], let w = (a["Watts"] as? NSNumber)?.intValue, w > 0 {
            adapterWatts = w
        }
        if let v = int("Voltage"), let amps = (d["Amperage"] as? NSNumber)?.int64Value {
            batteryWatts = Double(v) / 1000 * Double(Int(truncatingIfNeeded: amps)) / 1000
        }
        if let p = d["PowerTelemetryData"] as? [String: Any], let load = (p["SystemLoad"] as? NSNumber)?.intValue {
            macWatts = Double(load) / 1000
        }
    }
}

func sysctlInt(_ name: String) -> Int? {
    var v: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
    return size == 4 ? Int(Int32(truncatingIfNeeded: v)) : Int(v)
}

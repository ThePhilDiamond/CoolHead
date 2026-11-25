import AppKit
import CoolHeadCore
import SwiftUI

/// The This Mac tool's page (Hardware until 20 November 2026): a verdict, then the drive, crash restarts, the ports and the temperatures, each with everything about it
/// together, then what Cool Head can't check (the memory among it) and how Apple's own test does. The battery has its
/// own page, and how the Mac is running is at the top of the panel. A problem still gets its own card in the list.
struct HardwareView: View {
    let close: () -> Void
    @State private var showDiagnostics = false
    @ObservedObject private var load = ChipLoad.shared

    /// This Mac's hardware report, or in a screenshot made-up hardware (never this Mac's own).
    var report: HardwareReport? {
        if let kind = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HARDWARE"], PanelView.sampleSnapshot || kind == "issue" {
            var r = HardwarePage.sample(kind); if !MacOutline.laptop { r.battery = nil }; return r
        }
        if PanelView.sampleSnapshot { var r = HardwarePage.sample(); if !MacOutline.laptop { r.battery = nil }; return r }
        // the chip's temperature is the heat dial's live one, not the report's (read up to 10 minutes ago)
        var r = HardwareWatch.shared.report
        if let c = load.chipC { r?.chipC = c }
        return r
    }

    /// Made up in a screenshot, never this Mac's own.
    private let model: String? = PanelView.sampleSnapshot ? (MacOutline.laptop ? "MacBook Air (M2, 2022)" : "Mac mini (M2, 2023)") : ThisMac.modelName()
    private let serial: String? = PanelView.sampleSnapshot ? "SAMPLE12345" : ThisMac.serial()
    private let space: ThisMac.Space? = PanelView.sampleSnapshot
        ? (ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_LOWDISK"] != nil ? ThisMac.Space(free: 12_400_000_000, total: 245_110_000_000)
                                                                                  : ThisMac.Space(free: 164_000_000_000, total: 494_380_000_000))
        : ThisMac.space()
    @State private var copiedSerial = false

    /// The week's spells of tight memory; made-up ones for screenshots (COOLHEAD_SNAPSHOT_PRESSURE).
    var pressureWeek: PressureHistory.Week {
        let list = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_PRESSURE"] != nil ? PressureHistory.sample() : PressureHistory.load()
        return PressureHistory.week(list, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text("This Mac") } icon: { ToolIcon(symbol: MacOutline.name, size: 13) }.font(.body.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            // which Mac, and its serial number with a copy button; on the page only
            if model != nil || serial != nil {
                HStack(spacing: 6) {
                    Text([model, serial.map { "Serial \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(Ink.muted).textSelection(.enabled)
                    if let serial {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(serial, forType: .string)
                            copiedSerial = true
                        } label: { Image(systemName: copiedSerial ? "checkmark" : "doc.on.doc").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(Ink.muted)
                        .help(copiedSerial ? "Copied" : "Copy the serial number")
                        .accessibilityLabel("Copy the serial number")
                    }
                }
                .font(.caption)
            }
            if let r = report {
                let v = HardwarePage.verdict(r)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: ["checkmark.circle.fill", "minus.circle.fill", "exclamationmark.triangle.fill"][min(v.level, 2)])
                        .font(.title3).foregroundStyle(NetworkView.color(v.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(.callout.weight(.semibold))
                        Text(v.meaning).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                storage
                VStack(spacing: 10) { ForEach(HardwarePage.parts(r), id: \.kind) { part($0) } }
            } else {
                Text("Checking the hardware…").foregroundStyle(Ink.muted)
                storage
            }
            Divider()
            // how often memory slowed this Mac this week, from the history kept for that one purpose (see PressureHistory)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory this week")
                    Text(([PressureHistory.weekLine(pressureWeek)] + [PressureHistory.chromeLine(pressureWeek)].compactMap { $0 }).joined(separator: " "))
                        .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .help("Cool Head keeps when memory was tight on this Mac for 30 days, only to tell whether memory is what slows it. No app names, and nothing leaves your Mac.")
            Divider()
            // what can't be read from inside macOS, the memory among it, and Apple's own test for it
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory and other parts")
                    Text("macOS doesn't let apps test these.").font(.caption).foregroundStyle(Ink.muted)
                }
                Spacer()
                Button(showDiagnostics ? "Hide" : "How to test them") { showDiagnostics.toggle() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Apple Diagnostics tests what Cool Head can't read from inside macOS, such as the memory.")
            }
            if showDiagnostics {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Hardware.limits(appleSilicon: report?.appleSilicon ?? true), id: \.self) {
                        Text($0).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    /// One part: its icon in its level's color, its name, how it is, then its figures and details, with room between
    /// them so it doesn't look cramped; whether the drive is backed up is its own row, the words at the left and the
    /// button to act at the right, as elsewhere on the page.
    /// How full the startup disk is, under the verdict.
    @ViewBuilder var storage: some View {
        if let space {
            // how full the startup disk is, free of total, and macOS's own breakdown one click away in its storage
            // settings, for now; low space points to the Cleaner
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive").foregroundStyle(space.low ? NetworkView.color(1) : Ink.text).frame(width: 18)
                    Text("Storage").font(.callout.weight(.semibold))
                    Spacer()
                    Text(space.text)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(space.low ? NetworkView.color(1) : Ink.accent.opacity(0.7))
                            .frame(width: max(6, g.size.width * space.used))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                HStack(spacing: 8) {
                    if space.low {
                        Text("Under 20 GB free can slow the Mac.").font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 0)
                    if space.low {
                        Button("Clean up") { Tools.shared.hardware = false; Tools.shared.cleaner = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help("Opens the Cleaner, which finds leftovers that are safe to delete.")
                    }
                    Button("Storage settings") { NSWorkspace.shared.open(URL(string: ThisMac.storageSettings)!) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("macOS's own Storage page shows what's using the space, by kind, with its suggestions.")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        
        }
    }

    func part(_ p: HardwarePage.Part) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: p.symbol).foregroundStyle(NetworkView.color(p.level)).frame(width: 18)
                Text(p.name).font(.callout.weight(.semibold))
                Spacer()
                Text(p.value).foregroundStyle(p.level > 0 ? NetworkView.color(p.level) : Ink.text)
            }
            if !p.tiles.isEmpty { HStack(spacing: 8) { ForEach(p.tiles, id: \.symbol) { FigureTile(t: $0) } } }
            if !p.lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.lines, id: \.self) {
                        Text(ui: $0).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, p.tiles.isEmpty ? 26 : 0)
            }
            if let backup = p.backup {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(Ink.muted)
                    Text(ui: backup).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    // nothing backs the drive up: one click to Time Machine's settings
                    if report?.timeMachine == .notSetUp {
                        Button("Set up Time Machine") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")!)
                        }
                        .buttonStyle(.bordered).controlSize(.small).fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// How the Mac is running, at the top of the panel whenever it opens, rather than only on the Hardware page: simple
/// visual cues for heat and heavy use that aren't busy or confusing. The menu bar icon's snowflake (whole, melting, in
/// flames) with a few words, and three dials, chip load, memory, and heat, each showing its step. Their meanings are in
/// the tooltips.
struct RunningStrip: View {
    let watcher: Watcher
    /// The cards on screen, so the snowflake shows the same level as the menu bar icon.
    let cards: [LiveCard]
    /// The panel's status ("1 to watch", "All calm"), the row's title, and its level, for VoiceOver.
    let title: String
    let level: Watcher.Level
    /// The scroll bar's room while the panel is wider, so the row's words and dials stay where they were.
    var extra: CGFloat = 0
    @ObservedObject private var load = ChipLoad.shared
    /// The dials are a setting, off to start: the snowflake and its words say how the Mac is without them, and someone
    /// who doesn't know or care what the figures mean gets less clutter.
    nonisolated static let gaugesKey = "showGauges"
    @AppStorage(RunningStrip.gaugesKey) private var showGauges = false

    var snapshot: String? { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_RUNNING"] }
    /// In a screenshot, made-up heat (never this Mac's own); nil means this Mac's.
    static var snapshotThermal: String? {
        switch ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_RUNNING"] {
        case "hot": return "serious"
        case "fire": return "critical"
        case .some: return "nominal"
        case nil: return PanelView.limitedSnapshot ? "nominal" : nil
        }
    }
    var running: HardwarePage.Running {
        let fans: HardwarePage.Fans? = switch snapshot {
        case "hot": HardwarePage.Fans.none
        case "fire": .rpm([5_200, 5_350])
        case .some: .rpm([1_200, 1_250])
        case nil: nil
        }
        return HardwarePage.running(thermal: RunningStrip.snapshotThermal ?? watcher.mac.thermal, signs: watcher.signs(cards), fans: fans)
    }
    /// The three dials: chip load, memory, and the heat of the part nearest its own limit.
    var gauges: [HardwarePage.Gauge] {
        // a screenshot's made-up memory follows its cards, so a "memory is tight" card never sits beside a green dial
        let signs = watcher.signs(cards)
        let memory = signs.memoryCritical ? HardwarePage.memory(pressure: "critical")
            : signs.memoryTight ? HardwarePage.memory(pressure: "warning") : nil
        let thermal = RunningStrip.snapshotThermal ?? watcher.mac.thermal
        // made-up chip temperatures in a screenshot; this Mac's own only once Cool Head reads them (see HardwareReport.chipC)
        let chipC: Double? = switch snapshot {
        case "hot": 92
        case "fire": 104
        case .some: 55
        case nil: PanelView.limitedSnapshot ? 55 : load.chipC
        }
        let parts = RunningStrip.partTemperatures()
        let heat = HardwarePage.heat(chipC: chipC, thermal: thermal, batteryC: parts.batteryC, charging: parts.charging,
                                     driveC: parts.driveC).map { [$0] } ?? []
        switch snapshot {
        case "hot": return [HardwarePage.chip(busy: 0.62), memory ?? HardwarePage.memory(pressure: "warning")] + heat
        case "fire": return [HardwarePage.chip(busy: 0.93), memory ?? HardwarePage.memory(pressure: "critical")] + heat
        case .some: return [HardwarePage.chip(busy: 0.18), memory ?? HardwarePage.memory(pressure: "normal")] + heat
        case nil:
            if PanelView.limitedSnapshot { return [HardwarePage.chip(busy: 0.18), memory ?? HardwarePage.memory(pressure: "normal")] + heat }
            return [HardwarePage.chip(busy: load.average.value), HardwarePage.memory(watcher.mac)] + heat
        }
    }

    /// The battery's and drive's temperatures: the battery's live reading (every 10 seconds, as on the Power page), else
    /// the hardware report's, and the drive's from the report (it changes slowly). Made up in a screenshot: a hot battery
    /// with COOLHEAD_SNAPSHOT_RUNNING=battery or a hardware-battery-hot sample, a warm one with battery-warm or a
    /// hardware-battery-warm sample, so a sample card never sits under a calmer row. One reading for the heat dial, the
    /// snowflake, the title, and the menu bar icon, so they never disagree.
    static func partTemperatures() -> (batteryC: Double?, charging: Bool, driveC: Double?) {
        let env = ProcessInfo.processInfo.environment
        let snap = env["COOLHEAD_SNAPSHOT_RUNNING"], samples = (env["COOLHEAD_SNAPSHOT_SAMPLES"] ?? "").split(separator: "|")
        if snap != nil || PanelView.limitedSnapshot {
            let hot = snap == "battery" || samples.contains("hardware-battery-hot")
            let warm = snap == "battery-warm" || samples.contains("hardware-battery-warm")
            return (hot ? 46 : warm ? 42 : 31, false, 34)
        }
        let report = HardwareWatch.shared.report, mac = Watcher.shared.mac
        return (mac.batteryTempC ?? report?.battery?.temperatureC, mac.batteryTempC != nil ? mac.charging : report?.battery?.charging ?? false,
                report?.drive?.temperatureC.map(Double.init))
    }
    /// The battery's or drive's own heat, for the watcher's level (see HardwarePage.PartHeat).
    static func partHeat() -> HardwarePage.PartHeat? {
        let p = partTemperatures()
        return HardwarePage.partHeat(batteryC: p.batteryC, charging: p.charging, driveC: p.driveC)
    }

    /// The sentence under the status. When the heat dial shows the battery or the drive, it names that part first, so the
    /// line beside a warm dial never says only "a normal temperature" (that sentence is the chip's).
    func meaning(_ r: HardwarePage.Running) -> String {
        guard let g = gauges.last, g.level > 0, g.name == "Battery temperature" || g.name == "Drive temperature" else { return r.meaning }
        let part = g.name == "Battery temperature" ? "The battery" : "The drive"
        let thermal = RunningStrip.snapshotThermal ?? watcher.mac.thermal
        let chip = thermal == "serious" || thermal == "critical" ? "and macOS is slowing the chip to cool it." : "and the chip is at full speed."
        return "\(part) is \(g.level >= 2 ? "hot" : "warm"), \(chip)"
    }

    var body: some View {
        let r = running
        // the first look with nothing yet needing a look: a faint snowflake and no green (see Watcher.firstLook)
        let looking = watcher.firstLook && level == .good
        HStack(spacing: 12) {
            Image(nsImage: Snowflake.image(icon: r.icon, scale: 2.2))
                .opacity(looking ? 0.4 : 1)
                .accessibilityLabel(looking ? "Taking a first look" : level == .good ? "All good" : level == .warning ? "Worth watching" : "Problem")
            VStack(alignment: .leading, spacing: 2) {
                // each part kept whole, so a line breaks only at the "·": "Running hot ·" over "1 to watch", never "1" over "to watch"
                Text(title.components(separatedBy: " · ").map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · "))
                    .font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(meaning(r)).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            // the three dials side by side, close together, with no headings: each label says what it is ("Chip load",
            // "Memory", "Chip temp"), which leaves the sentence beside them room to stay short
            if showGauges {
                HStack(spacing: 6) { ForEach(gauges, id: \.name) { gauge($0) } }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .padding(.trailing, extra)
        // a gentle wash of the level's color (green, yellow, or red), never the only sign: the snowflake's shape
        // (whole, melting, in flames) and the title's words say the same. None during the first look: no green before a reading
        .background(Color(nsColor: Badge.color(level)).opacity(looking ? 0 : 0.10))
        .background(BarFrost.bar)
        .onAppear { load.start() }
        .onDisappear { load.stop() }
    }

    /// A dial, like a car's temperature gauge: green, yellow, and red zones over the top half, the zone for its level
    /// full strength and the others faint, each with a border in its own color so all three stay distinct; the needle
    /// in the middle of the zone (the zone is the step: no position inside it is claimed, see HardwarePage.Gauge); the
    /// word or temperature under it, and the label under that. Where the needle points carries the level without color.
    /// Before the first reading, no needle and "…".
    func gauge(_ g: HardwarePage.Gauge) -> some View {
        let rOut: CGFloat = 23, rIn: CGFloat = 11, needle: CGFloat = 17, center = CGPoint(x: 23, y: 27)
        func band(_ i: Int) -> Path {
            Path { p in
                let a0 = Angle.degrees(180 + 60 * Double(i) + 1.5), a1 = Angle.degrees(180 + 60 * Double(i + 1) - 1.5)
                p.addArc(center: center, radius: rOut, startAngle: a0, endAngle: a1, clockwise: false)
                p.addArc(center: center, radius: rIn, startAngle: a1, endAngle: a0, clockwise: true)
                p.closeSubpath()
            }
        }
        return VStack(spacing: 3) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    band(i).fill(NetworkView.color(i).opacity(i == g.level ? 1 : 0.18))
                    band(i).stroke(NetworkView.color(i).opacity(i == g.level ? 1 : 0.7), lineWidth: 1)
                }
                if let at = g.needle {
                    Path { p in
                        let a = Angle.degrees(180 + 180 * at).radians
                        p.move(to: center)
                        p.addLine(to: CGPoint(x: center.x + needle * cos(a), y: center.y + needle * sin(a)))
                    }
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    Circle().fill(Color.primary).frame(width: 6, height: 6).position(center)
                }
                Text(g.text).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6).position(x: 23, y: 41)
            }
            .frame(width: 46, height: 46)
            // the part's icon beside its label, so the heat dial says whose heat it is
            HStack(spacing: 3) {
                if let s = g.symbol { Image(systemName: s).font(.system(size: 10, weight: .semibold)) }
                Text(g.label)
            }
            .font(.subheadline).foregroundStyle(Ink.muted).fixedSize()           // grey, like every label: the dial's color carries the level
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(g.spoken)
        .help(HardwarePage.help(g))
    }
}

/// The share of the chip's cores in use, from macOS's own counters, averaged over about the last 30 seconds, and the
/// chip's temperature (ChipTemperature), read every 3 seconds while the panel is open and not at all while it's closed.
@MainActor
final class ChipLoad: ObservableObject {
    /// One reading for the heat dial and the Hardware page's chip tile, so the two always agree. They didn't
    /// when the page showed the reading from its report, up to 10 minutes old, since the hottest sensor moves several
    /// degrees in seconds.
    static let shared = ChipLoad()
    /// Chip load over about the last 30 seconds (see HardwarePage.LoadAverage); empty until the second reading.
    @Published var average = HardwarePage.LoadAverage()
    /// The hottest chip sensor, for the heat dial (see ChipTemperature); nil where it can't be read.
    @Published var chipC: Double?
    private var last: (busy: UInt64, total: UInt64)?
    private var timer: Timer?

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { @MainActor in self.sample() } }
    }
    /// Stops reading and forgets the readings, so the next opening never shows an old load as now.
    func stop() { timer?.invalidate(); timer = nil; last = nil; average.clear() }

    private func sample() {
        // about a twentieth of a second, so off the main thread
        DispatchQueue.global(qos: .utility).async {
            let c = ChipTemperature.read()
            DispatchQueue.main.async { self.chipC = c }
        }
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard ok == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let busyTicks = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)          // user, system, nice
        let total = busyTicks + UInt64(t.2)                               // plus idle
        if let l = last, total > l.total { average.add(Double(busyTicks - l.busy) / Double(total - l.total)) }
        last = (busyTicks, total)
    }
}

/// The menu bar icon's Melting Snowflake, drawn at any size: 0 whole, 1 melting, 2 in flames.
enum Snowflake {
    static func image(icon: Int, scale k: CGFloat) -> NSImage {
        let level: Watcher.Level = icon >= 2 ? .issue : icon == 1 ? .warning : .good
        let img = NSImage(size: NSSize(width: 20 * k, height: 18 * k), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.scaleBy(x: k, y: k)
            MenuIcon.melting(level)
            return true
        }
        img.isTemplate = false
        return img
    }
}

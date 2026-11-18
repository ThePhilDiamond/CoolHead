import AppKit
import CoolHeadCore
import SwiftUI

/// The Hardware tool's page: a verdict, then the drive, crash restarts, the ports and the temperatures, each with everything about it
/// together, then what Cool Head can't check (the memory among it) and how Apple's own test does. The battery has its
/// own page, and how the Mac is running is at the top of the panel. A problem still gets its own card in the list.
struct HardwareView: View {
    let close: () -> Void
    @State private var showDiagnostics = false

    /// This Mac's hardware report, or in a screenshot made-up hardware (never this Mac's own).
    var report: HardwareReport? {
        if let kind = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HARDWARE"], PanelView.sampleSnapshot || kind == "issue" {
            return HardwarePage.sample(kind)
        }
        return PanelView.sampleSnapshot ? HardwarePage.sample() : HardwareWatch.shared.report
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Hardware", systemImage: "internaldrive").font(.body.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
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
                VStack(spacing: 10) { ForEach(HardwarePage.parts(r), id: \.kind) { part($0) } }
            } else {
                Text("Checking the hardware…").foregroundStyle(Ink.muted)
            }
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

    /// One part: its icon in its level's colour, its name, how it is, then its figures and details, with room between
    /// them; whether the drive is backed up is its own row, the words at the left and the button to act at the right, as
    /// elsewhere on the page (Phil, 17 November 2026: "text on the left, button to act on the right"; "improve the
    /// spacing so it doesn't look so cramped").
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

/// How the Mac is running, at the top of the panel whenever it opens (Phil, 16 November 2026: "Maybe the temperature
/// panes from the hardware screen renders should be persistent in the main pane instead?"; "Is there also a useful way to
/// clearly and concisely portray heavy resource use? ... simple intuitive visual cues without being busy or
/// confusing"): the menu bar icon's snowflake (whole, melting, in flames) with a few words, and two small gauges, the
/// chip and memory, coloured by level. Numbers and meanings are in the tooltips.
struct RunningStrip: View {
    let watcher: Watcher
    /// The cards on screen, so the snowflake shows the same level as the menu bar icon.
    let cards: [LiveCard]
    /// The panel's status ("1 to watch", "All calm"), the row's title, and its level, for VoiceOver.
    let title: String
    let level: Watcher.Level
    @StateObject private var load = ChipLoad()

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
    var gauges: [HardwarePage.Gauge] {
        // a screenshot's made-up memory follows its cards, so a "memory is tight" card never sits beside a green gauge
        let signs = watcher.signs(cards)
        let memory = signs.memoryCritical ? HardwarePage.memory(freePercent: 8, pressure: "critical")
            : signs.memoryTight ? HardwarePage.memory(freePercent: 22, pressure: "warning") : nil
        let thermal = RunningStrip.snapshotThermal ?? watcher.mac.thermal
        // made-up chip temperatures in a screenshot; this Mac's own only once Cool Head reads them (see HardwareReport.chipC)
        let chipC: Double? = switch snapshot {
        case "hot": 92
        case "fire": 104
        case .some: 55
        case nil: PanelView.limitedSnapshot ? 55 : load.chipC
        }
        let heat = HardwarePage.heat(chipC: chipC, thermal: thermal).map { [$0] } ?? []
        switch snapshot {
        case "hot": return [HardwarePage.chip(busy: 0.62), memory ?? HardwarePage.memory(freePercent: 22, pressure: "warning")] + heat
        case "fire": return [HardwarePage.chip(busy: 0.93), memory ?? HardwarePage.memory(freePercent: 8, pressure: "critical")] + heat
        case .some: return [HardwarePage.chip(busy: 0.18), memory ?? HardwarePage.memory(freePercent: 58, pressure: "normal")] + heat
        case nil:
            if PanelView.limitedSnapshot { return [HardwarePage.chip(busy: 0.18), memory ?? HardwarePage.memory(freePercent: 58, pressure: "normal")] + heat }
            return [HardwarePage.chip(busy: load.busy), HardwarePage.memory(freePercent: load.memoryFree, pressure: watcher.mac.memoryPressure)] + heat
        }
    }

    var body: some View {
        let r = running
        HStack(spacing: 12) {
            Image(nsImage: Snowflake.image(icon: r.icon, scale: 2.2))
                .accessibilityLabel(level == .good ? "All good" : level == .warning ? "Worth watching" : "Problem")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(r.meaning).font(.caption).foregroundStyle(Ink.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            ForEach(gauges, id: \.name) { gauge($0) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        // a gentle wash of the level's colour, never the only sign: the snowflake's shape (whole, melting, in flames)
        // and the title's words say the same (Phil, 17 November 2026: "a gentle background tint to the top bar for
        // green / yellow / red")
        .background(Color(nsColor: Badge.color(level)).opacity(0.10))
        .onAppear { load.start() }
        .onDisappear { load.stop() }
    }

    /// A gauge: a ring filled to its share in its level's colour, the percentage inside and the name under it, larger
    /// than the bars it replaced (Phil, 17 November 2026: "make the bars/text on the right a little bigger, maybe put the
    /// labels below and the percentage inside"). macOS's own gauge, so VoiceOver reads it as one.
    func gauge(_ g: HardwarePage.Gauge) -> some View {
        VStack(spacing: 3) {
            Gauge(value: Double(g.percent), in: 0...100) {
                Text(g.name)
            } currentValueLabel: {
                Text(g.text ?? "\(g.percent)%").font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(NetworkView.color(g.level))
            // macOS draws this gauge at a fixed size; smaller, so the title beside it keeps its room
            .scaleEffect(0.8).frame(width: 46, height: 46)
            Text(g.name).font(.caption).foregroundStyle(Ink.muted).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(g.text.map { "\(g.name) \($0)" } ?? "\(g.name) \(g.percent) percent")
    }
}

/// The share of the chip's cores in use, from macOS's own counters, the memory macOS counts as free when it judges
/// pressure (kern.memorystatus_level), and the chip's temperature (ChipTemperature), read every 3 seconds while the
/// panel is open and not at all while it's closed.
@MainActor
final class ChipLoad: ObservableObject {
    @Published var busy = 0.0
    @Published var memoryFree = 100
    /// The hottest chip sensor, for the Heat ring (see ChipTemperature); nil where it can't be read.
    @Published var chipC: Double?
    private var last: (busy: UInt64, total: UInt64)?
    private var timer: Timer?

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { @MainActor in self.sample() } }
    }
    func stop() { timer?.invalidate(); timer = nil; last = nil }

    private func sample() {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 { memoryFree = Int(level) }
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
        if let l = last, total > l.total { busy = Double(busyTicks - l.busy) / Double(total - l.total) }
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

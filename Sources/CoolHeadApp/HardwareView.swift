import AppKit
import CoolHeadCore
import SwiftUI

/// The Hardware tool's page: a verdict, then the drive, crash restarts and the ports, each with everything about it
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
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 6) { ForEach(HardwarePage.parts(r), id: \.kind) { part($0) } }
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

    /// One part: its icon in its level's colour, its name, how it is, and its details underneath.
    func part(_ p: HardwarePage.Part) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: p.symbol).foregroundStyle(NetworkView.color(p.level)).frame(width: 18)
                Text(p.name).font(.callout.weight(.semibold))
                Spacer()
                Text(p.value).foregroundStyle(p.level > 0 ? NetworkView.color(p.level) : Ink.text)
            }
            ForEach(p.lines, id: \.self) {
                Text($0).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
            // nothing backs the drive up: one click to Time Machine's settings
            if p.kind == .drive, report?.timeMachine == .notSetUp {
                Button("Set up Time Machine") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")!)
                }
                .buttonStyle(.bordered).controlSize(.small).padding(.leading, 26)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// How the Mac is running, at the top of the panel whenever it opens (Phil, 16 November 2026: "Maybe the temperature
/// panes from the hardware screen renders should be persistent in the main pane instead?"; "Is there also a useful way to
/// clearly and concisely portray heavy resource use? ... simple intuitive visual cues without being busy or
/// confusing"): the menu bar icon's snowflake (whole, melting, in flames) with a few words, and two small gauges, the
/// chip and memory, coloured by level. Numbers and meanings are in the tooltips.
struct RunningStrip: View {
    let watcher: Watcher
    @StateObject private var load = ChipLoad()

    var snapshot: String? { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_RUNNING"] }
    var running: HardwarePage.Running {
        switch snapshot {
        case "hot": return HardwarePage.running(thermal: "serious", fans: HardwarePage.Fans.none)
        case "fire": return HardwarePage.running(thermal: "critical", fans: .rpm([5_200, 5_350]))
        case .some: return HardwarePage.running(thermal: "nominal", fans: .rpm([1_200, 1_250]))
        case nil: return HardwarePage.running(thermal: PanelView.limitedSnapshot ? "nominal" : watcher.mac.thermal, fans: nil)
        }
    }
    var gauges: [HardwarePage.Gauge] {
        switch snapshot {
        case "hot": return [HardwarePage.chip(busy: 0.62), HardwarePage.memory(freePercent: 22, pressure: "warning")]
        case "fire": return [HardwarePage.chip(busy: 0.93), HardwarePage.memory(freePercent: 8, pressure: "critical")]
        case .some: return [HardwarePage.chip(busy: 0.18), HardwarePage.memory(freePercent: 58, pressure: "normal")]
        case nil:
            if PanelView.limitedSnapshot { return [HardwarePage.chip(busy: 0.18), HardwarePage.memory(freePercent: 58, pressure: "normal")] }
            return [HardwarePage.chip(busy: load.busy), HardwarePage.memory(freePercent: load.memoryFree, pressure: watcher.mac.memoryPressure)]
        }
    }

    var body: some View {
        let r = running
        HStack(spacing: 10) {
            Image(nsImage: Snowflake.image(icon: r.icon, scale: 1.4))
            VStack(alignment: .leading, spacing: 0) {
                Text(r.title).font(.callout.weight(.semibold))
                Text(r.meaning).font(.caption).foregroundStyle(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            ForEach(gauges, id: \.name) { gauge($0) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .onAppear { load.start() }
        .onDisappear { load.stop() }
    }

    /// A gauge: its name and percentage over a short bar, filled to that share in its level's colour. No tooltip: the
    /// colour, the words beside the snowflake and the cards below say whether it matters (Phil, 16 November 2026).
    func gauge(_ g: HardwarePage.Gauge) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(g.name).foregroundStyle(Ink.muted).fixedSize()
                Spacer(minLength: 0)
                Text("\(g.percent)%").monospacedDigit().foregroundStyle(Ink.text)
            }
            .font(.caption2)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(NetworkView.color(g.level)).frame(width: max(5, 76 * CGFloat(g.percent) / 100))
            }
            .frame(width: 76, height: 5)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(g.name) \(g.percent) percent")
    }
}

/// The share of the chip's cores in use, from macOS's own counters, and the memory macOS counts as free when it judges
/// pressure (kern.memorystatus_level), read every 3 seconds while the panel is open and not at all while it's closed.
@MainActor
final class ChipLoad: ObservableObject {
    @Published var busy = 0.0
    @Published var memoryFree = 100
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

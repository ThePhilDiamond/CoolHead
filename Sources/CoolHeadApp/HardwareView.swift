import AppKit
import CoolHeadCore
import SwiftUI

/// The Hardware tool's page: the drive, memory, fans, crash restarts and the ports, in the same shape as Test my network
/// and Battery (a verdict, a figure for each part, a status line), with how it's running now drawn as the menu bar
/// icon's snowflake, then what Cool Head can't check and how Apple's own test does. The battery has its own page. A
/// problem still gets its own card in the list.
struct HardwareView: View {
    let watcher: Watcher
    let close: () -> Void
    @State private var showDiagnostics = false

    var snapshotKind: String? { ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HARDWARE"] }

    /// This Mac's hardware report, or in a screenshot made-up hardware (never this Mac's own).
    var report: HardwareReport? {
        if let kind = snapshotKind, PanelView.sampleSnapshot || kind == "issue" { return HardwarePage.sample(kind) }
        return PanelView.sampleSnapshot ? HardwarePage.sample() : HardwareWatch.shared.report
    }
    /// How it's running: this Mac's thermal state, or in a screenshot a made-up one ("issue" is a fanless Mac running
    /// hot, "hot" a Mac with fans that's too hot).
    var running: HardwarePage.Running {
        if snapshotKind == "issue" { return HardwarePage.running(thermal: "serious", fans: HardwarePage.Fans.none) }
        if snapshotKind == "hot" { return HardwarePage.running(thermal: "critical", fans: .rpm([5_200, 5_350])) }
        if snapshotKind != nil || PanelView.sampleSnapshot { return HardwarePage.running(thermal: "nominal", fans: .rpm([1_200, 1_250])) }
        return HardwarePage.running(thermal: watcher.mac.thermal, fans: nil)
    }
    var memoryGB: Double { snapshotKind != nil || PanelView.sampleSnapshot ? 16 : watcher.mac.memoryGB }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Hardware", systemImage: "stethoscope").font(.body.weight(.semibold))
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
                runningBox
                HStack(alignment: .top, spacing: 8) { ForEach(HardwarePage.tiles(r, memoryGB: memoryGB), id: \.part) { tile($0) } }
                let s = HardwarePage.status(r)
                HStack(spacing: 8) {
                    Image(systemName: s.symbol).foregroundStyle(s.level > 0 ? NetworkView.color(s.level) : Ink.text)
                    Text(s.text)
                    Spacer()
                    if let d = s.detail { Text(d).font(.caption).foregroundStyle(Ink.muted).multilineTextAlignment(.trailing) }
                }
            } else {
                Text("Checking the hardware…").foregroundStyle(Ink.muted)
            }
            Divider()
            // what can't be read from inside macOS, and Apple's own test for it
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                Text("Memory and other parts")
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

    /// How it's running, with the menu bar icon's snowflake drawn large: whole when cool, melting when hot, in flames
    /// when too hot.
    var runningBox: some View {
        let r = running
        return HStack(alignment: .center, spacing: 12) {
            Image(nsImage: Snowflake.image(icon: r.icon, scale: 2.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.callout.weight(.semibold))
                Text(r.meaning).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if let f = r.fans {
                    Label(f, systemImage: "fan").font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    /// One figure, drawn as Battery draws its own.
    func tile(_ t: HardwarePage.Tile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: t.symbol).font(.caption.weight(.semibold)).foregroundStyle(NetworkView.color(t.level))
                Text(t.value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(t.unit).font(.caption2).foregroundStyle(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
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

import AppKit
import CoolHeadCore
import SwiftUI

/// The Hardware tool's page: the drive, the battery, crash restarts and the ports, in the same shape as Test my network
/// and Battery (a verdict, a figure for each part, a status line), then what Cool Head can't check and how Apple's own
/// test does. A problem still gets its own card in the list.
struct HardwareView: View {
    /// Opens the Battery page from the battery's figure, on a Mac with a battery.
    var openBattery: (() -> Void)? = nil
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
                HStack(alignment: .top, spacing: 8) { ForEach(HardwarePage.tiles(r), id: \.part) { tile($0) } }
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

    /// One figure, drawn as Battery draws its own; the battery's opens the Battery page.
    @ViewBuilder func tile(_ t: HardwarePage.Tile) -> some View {
        let body = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: t.symbol).font(.caption.weight(.semibold)).foregroundStyle(NetworkView.color(t.level))
                Text(t.value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Text(t.unit).font(.caption2).foregroundStyle(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        if t.part == .battery, let openBattery {
            Button(action: openBattery) { body }.buttonStyle(.plain).help("Open the Battery page")
        } else {
            body
        }
    }
}

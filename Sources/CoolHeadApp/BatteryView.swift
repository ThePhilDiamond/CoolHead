import AppKit
import CoolHeadCore
import SwiftUI

/// The Power tool's page (Battery until 20 November 2026): the battery's health and what it's doing now, what else
/// helps the battery last, and the week's energy use, all in one place, which keeps it tidy and succinct rather than
/// spread across places. A battery problem still gets its own card in the list as well.
struct BatteryView: View {
    let watcher: Watcher
    /// Whether the past week's energy use can be shown: this Mac's power log can be read, or it's a screenshot.
    var energy = PowerHistory.available || PanelView.sampleSnapshot
    let close: () -> Void

    /// This Mac's battery, or in a screenshot a made-up one (never this Mac's own).
    var battery: BatteryHealth? {
        PanelView.sampleSnapshot ? (MacOutline.laptop ? BatteryPage.sample : nil) : BatteryPage.merge(report: HardwareWatch.shared.report?.battery, mac: watcher.mac)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text("Power") } icon: { ToolIcon(symbol: PowerIcon.name, size: 13) }.font(.body.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            if let b = battery {
                // the answer, three figures and what it's doing now, as Test my network shows its result
                let v = BatteryPage.verdict(b)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: ["checkmark.circle.fill", "minus.circle.fill", "exclamationmark.triangle.fill"][min(v.level, 2)])
                        .font(.title3).foregroundStyle(NetworkView.color(v.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(.callout.weight(.semibold))
                        Text(v.meaning).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                let tiles = BatteryPage.tiles(b)
                if !tiles.isEmpty {
                    HStack(spacing: 8) { ForEach(tiles, id: \.symbol) { FigureTile(t: $0) } }
                }
                let s = BatteryPage.status(b)
                HStack(spacing: 8) {
                    Image(systemName: s.symbol).foregroundStyle(s.level > 0 ? NetworkView.color(s.level) : Ink.text)
                    Text(s.text)
                    Spacer()
                    if let d = s.detail { Text(d).font(.caption).foregroundStyle(Ink.muted).multilineTextAlignment(.trailing) }
                }
            } else if MacOutline.laptop {
                Text("Cool Head can't read the battery right now.").foregroundStyle(Ink.muted)
            } else {
                // a desktop: nothing to say about a battery, so the page is the week's energy use
                Text("This Mac has no battery.").foregroundStyle(Ink.muted)
            }
            // more battery life: Low Power Mode needs a password to switch, so it opens Battery settings (laptops only)
            let low = !PanelView.sampleSnapshot && ProcessInfo.processInfo.isLowPowerModeEnabled   // a screenshot shows "off"
            if MacOutline.laptop {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "leaf")
                    Text("Low Power Mode")
                    Text(low ? "On" : "Off").foregroundStyle(Ink.muted)
                    Spacer()
                    Button("Battery settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Low Power Mode slows the Mac a little and dims the screen so the battery lasts longer. Switching it needs your password, so Cool Head opens Battery settings.")
                }
            }
            // the week's energy use, here rather than in a Trends tool of its own (see EnergyWeek)
            if energy { EnergyWeek(sample: PanelView.sampleSnapshot ? .sample() : nil) }
            // no Nerdy stuff: every figure the hardware check reads is already in the sentences above, so it added
            // nothing. No Battery Saver switch: a
            // hungry job on battery gets its card instead (see Pauses.swift)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

}

/// One figure in a tile, drawn as Test my network draws its own: the Battery page's figures and the drive's.
struct FigureTile: View {
    let t: BatteryPage.Tile
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: t.symbol).font(.caption.weight(.semibold)).foregroundStyle(NetworkView.color(t.level))
                Text(t.value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(t.unit).font(.caption2).foregroundStyle(Ink.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// A switch drawn by Cool Head, its label first, filled with the accent color when on. macOS's own switch draws "on" in
/// gray unless its window belongs to the app in front, and the panel never makes Cool Head the app in front (it opens
/// without taking focus from what you're using), so the system switch looks off when it's on, with no fill. Every
/// switch in the panel uses this one.
struct PanelSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        HStack(alignment: .center, spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(on ? Ink.accent : Color.primary.opacity(0.2))
                .frame(width: 32, height: 18)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(Color.white).shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5).padding(2)
                }
                .animation(.easeOut(duration: 0.12), value: on)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "On" : "Off")
    }
}

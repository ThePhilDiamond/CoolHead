import AppKit
import CoolHeadCore
import SwiftUI

/// The Battery tool's page: the battery's health and what it's doing now, Battery Saver's switch, and what else helps
/// the battery last, all in one place (Phil, 16 November 2026: "that keeps it organized and tidy and succinct, rather
/// than having mixed data in mixed places"). A battery problem still gets its own card in the list as well.
struct BatteryView: View {
    let watcher: Watcher
    /// Opens Trends, where the past week's energy use is, when this Mac's power log can be read.
    var openTrends: (() -> Void)? = nil
    let close: () -> Void
    @AppStorage(BatteryMode.key) private var batterySaver = true

    /// This Mac's battery, or in a screenshot a made-up one (never this Mac's own).
    var battery: BatteryHealth? {
        PanelView.sampleSnapshot ? BatteryPage.sample : BatteryPage.merge(report: HardwareWatch.shared.report?.battery, mac: watcher.mac)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Battery", systemImage: "battery.75percent").font(.body.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            if let b = battery {
                section("Health") { Text(BatteryPage.health(b)) }
                section("Now") {
                    Text(BatteryPage.now(b))
                    if let t = BatteryPage.temperature(b) { Text(t).foregroundStyle(Ink.muted) }
                }
            } else {
                Text("Cool Head can't read the battery right now.").foregroundStyle(Ink.muted)
            }
            Divider()
            section("More battery life") {
                let low = !PanelView.sampleSnapshot && ProcessInfo.processInfo.isLowPowerModeEnabled   // a screenshot shows "off"
                Text("Low Power Mode is \(low ? "on" : "off"). It slows the Mac a little and dims the screen to make the battery last longer. Cool Head can't switch it without your password, so it opens Battery settings.")
                Button("Open Battery settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
                }
                .buttonStyle(.bordered).controlSize(.small)
                if let openTrends {
                    Button("See what used the most energy this week", action: openTrends)
                        .buttonStyle(.link).font(.callout)
                }
            }
            // no Nerdy stuff: every figure the hardware check reads is already in the sentences above (Phil, 16 November
            // 2026: "does the nerdy stuff section add detail? ... Otherwise can remove it")
            Divider()
            // the switch that used to be a setting, last on the page (Phil, 16 November 2026: "Battery saver at the bottom")
            Toggle(isOn: $batterySaver) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Saver").font(.callout.weight(.semibold))
                    Text("On battery, a really hungry job is flagged, and can be paused until you plug in. Nothing is lost.")
                        .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(PanelSwitch())
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(Ink.muted)
            content().fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A switch drawn by Cool Head, its label first, filled with the accent colour when on. macOS's own switch draws "on" in
/// grey unless its window belongs to the app in front, and the panel never makes Cool Head the app in front (it opens
/// without taking focus from what you're using), so the system switch looks off when it's on (Phil, 16 November 2026:
/// "the toggles seem to not show the fill when toggled \"on\""). Every switch in the panel uses this one.
struct PanelSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        HStack(alignment: .center, spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(on ? Color.accentColor : Color.primary.opacity(0.2))
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

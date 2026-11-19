import AppKit
import CoolHeadCore
import SwiftUI

/// Settings, in the panel like the other tools' pages, opened by the gear at the right end of the toolbar (Phil,
/// 17 November 2026: "The settings icon should be the right-most."). What Cool Head does first, then how it looks
/// (Phil, 16 November 2026: "icon style and labels are aesthetic choices, so should be grouped separately from the
/// other settings"), then About and Quit, so everything is in the panel and the right-click menu is only a shortcut.
struct SettingsView: View {
    @ObservedObject var tools = Tools.shared
    @AppStorage("notifications") private var notifications = true
    @AppStorage(Tools.labelsKey) private var labels = true
    @AppStorage("iconStyle") private var iconStyle = "badge"
    @AppStorage(RunningStrip.gaugesKey) private var gauges = false
    @State private var login = LoginItem.on
    @State private var automatic = Updater.shared.automatic
    let updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Settings", systemImage: "gearshape").font(.body.weight(.semibold))
                Spacer()
                Button { tools.settings = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            Text("General").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
            group {
                SettingSwitch(title: "Notifications", detail: "A quiet note when something needs a look.", on: $notifications)
                Divider()
                SettingSwitch(title: "Open at login", detail: nil, on: Binding(get: { login }, set: { LoginItem.set($0); login = LoginItem.on }))
                Divider()
                // each line under a setting is short, one line (Phil, 19 November 2026: "I don't like the many lines of text in
                // the settings pane explaining things. Can we do the same with less words?")
                // when it checks (Phil, 19 November 2026: "add a subtitle that "check for updates automatically" checks upon
                // opening the app and once daily"); Updater.schedule: a minute after launch, then every 24 hours
                SettingSwitch(title: "Check for updates automatically", detail: "When Cool Head opens, then daily.",
                              on: Binding(get: { automatic }, set: { updater.automatic = $0; automatic = $0 }))
                Divider()
                // the version, and checking now, here rather than in the toolbar (Phil, 17 November 2026: "the "Update"
                // label should say "update" not the version number, and maybe put the version number inside the update
                // icon? Or somewhere else?"; then, choosing between renders: "Update in Settings")
                HStack {
                    // what the number is, and how old (Phil, 19 November 2026: "Right now it just says the name and a number,
                    // which might not be clear to everyone")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cool Head version \(CoolHead.version)").font(.callout)
                        Text("Released \(CoolHead.releasedWords)").font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Text(updateWord).font(.caption).foregroundStyle(Ink.muted)
                    Button("Check Now") {
                        Task {
                            await updater.check(quiet: false)
                            if case .available = updater.phase { await updater.install() }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
            Text("Look").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
            group {
                Text("Menu bar icon").font(.callout)
                IconStylePicker(style: $iconStyle)
                Divider()
                SettingSwitch(title: "Show tool names", detail: "Off: point at a tool to see its name.", on: $labels)
                Divider()
                // off to start, for less to read at the top (Phil, 19 November 2026: "make the gauges in the top pane
                // optional as a setting for users who don't know what it means or care ... By default it should be off")
                SettingSwitch(title: "Show usage and temperature",
                              detail: "Gauges at the top of the panel.", on: $gauges)
            }
            HStack {
                Button("About Cool Head") { About.show() }.buttonStyle(.link).font(.callout)
                Spacer()
                Button("Quit Cool Head") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
        .onChange(of: iconStyle) { NotificationCenter.default.post(name: MenuIcon.changed, object: nil) }
    }

    /// A group of settings in one bordered box, as in System Settings.
    func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.edge, lineWidth: 1))
    }

    /// What the last check found, in a few words; nothing before a check.
    var updateWord: String {
        switch updater.phase {
        case .checking: return "Checking…"
        case .installing: return "Updating…"
        case .upToDate: return "Up to date"
        case .failed: return "Couldn't check"
        case .available(let v): return "\(v) ready"
        case .idle: return ""
        }
    }
}

/// A setting that's on or off: its name, a line on what it means where that isn't plain, and a switch.
struct SettingSwitch: View {
    let title: String
    let detail: String?
    @Binding var on: Bool

    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let detail { Text(detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Cool Head's own switch, filled when on whether or not Cool Head is the app in front, like every other switch
        // in the panel (Phil, 19 November 2026: "when it's not the focus pane, they're grey, but when focused, it should
        // be colored")
        .toggleStyle(PanelSwitch())
    }
}

/// The two menu bar icons, each at all three levels, to pick one by sight rather than by name (Phil, 17 November
/// 2026: "a welcome window that shows the user the different icon options"). The columns say what each level means.
struct IconStylePicker: View {
    @Binding var style: String
    static let levels: [(Watcher.Level, String)] = [(.good, "All good"), (.warning, "Worth watching"), (.issue, "Problem")]
    /// Each style's name, and how it shows the level besides color: both work without it (Phil, 19 November 2026: "add a
    /// subtitle that the melting snowflake icon is also color-blind friendly"; the badge's shapes do the same).
    static let styles: [(String, String, String)] = [("badge", "Status badge", "Shapes and colors"),
                                                    ("melting", "Melting snowflake", "Color-blind friendly")]

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(IconStylePicker.levels, id: \.1) { _, meaning in
                    Text(meaning).font(.caption2).foregroundStyle(Ink.muted).frame(width: 66)
                }
            }
            ForEach(IconStylePicker.styles, id: \.0) { key, name, how in
                let on = style == key
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(on ? Color.accentColor : Ink.muted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.callout)
                            Text(how).font(.caption2).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(IconStylePicker.levels, id: \.1) { level, _ in
                        Image(nsImage: MenuIcon.image(level: level, style: key)).frame(width: 66, height: 22)
                    }
                }
                .padding(.vertical, 3).padding(.leading, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor.opacity(0.12) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { style = key }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Menu bar icon: \(name). \(how)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

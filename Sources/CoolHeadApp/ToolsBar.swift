import AppKit
import CoolHeadCore
import IOKit
import SwiftUI
import UniformTypeIdentifiers

/// Along the bottom of the panel: the tools, each an icon with its name (the names can be hidden on the Settings page),
/// and each opening in the panel's middle. Opening one closes any other. Settings is the last, at the right end.
struct ToolsBar: View {
    let watcher: Watcher
    @ObservedObject var network = NetworkTester.shared
    @ObservedObject var tools = Tools.shared
    @AppStorage(Tools.labelsKey) private var labels = true
    /// A battery to show: this Mac's, or in a screenshot a made-up one.
    var hasBattery: Bool {
        MacOutline.laptop && (watcher.mac.batteryPercent != nil || HardwareWatch.shared.report?.battery != nil || PanelView.sampleSnapshot)
    }

    var body: some View {
        // seven tools fit the panel's width with their names when each is as narrow as its name allows
        HStack(spacing: labels ? 1 : 6) {
            // the order: This Mac, Power, Network, Cleaner. The left three mostly give information (Network has an action,
            // its test, but what it gives is information), and Cleaner, which changes things, comes last. Cleaner is a
            // different kind of tool, but no line sets it apart, since the order already makes that clear.
            // the hardware checks on one page, its icon the Mac itself, line drawn as a laptop or a desktop: the chip and
            // memory symbols have their own meanings in the panel, and a drive icon suits Cleaner better
            // called This Mac, which fits the bar ("My Mac" was the shorter fallback); it's as wide as "Hardware" was
            ToolButton(symbol: MacOutline.name, name: "This Mac", tip: "This Mac's hardware, serial number, and storage", labels: labels, on: tools.hardware) {
                let open = !tools.hardware
                closeAll()
                tools.hardware = open
            }
            // the Power page, after This Mac, since both are panes that show how the Mac is (it used to sit next to
            // Network). Called Power, not Battery, so the name fits a desktop too, where it has a plug in place of the
            // battery; a desktop's page is the week's energy use, so it's there when the power log can be read
            if hasBattery || (!MacOutline.laptop && (PowerHistory.available || PanelView.sampleSnapshot)) {
                ToolButton(symbol: PowerIcon.name, name: "Power",
                           tip: hasBattery ? "Battery health and energy use" : "What used the most energy this week",
                           labels: labels, on: tools.battery) {
                    let open = !tools.battery
                    closeAll()
                    tools.battery = open
                }
            }
            // a test carries on out of sight: while it runs, dashes fly around the globe's equator in a single ring,
            // like data packets going around the world; when it has finished unseen, the result's own mark from the
            // view's top line (a green check when it's good) sits on the globe until it's opened
            let away = network.running && !network.shown
            // the dashes show while it runs, open or not, since the animation is part of the look; when it's open, the
            // colors swap: the globe takes the accent color and the dashes the gray the icon has when closed
            ToolButton(symbol: "network", name: away ? "Testing" : "Network",
                       tip: away ? "A network test is running; its results will wait here"
                           : network.readyLevel != nil ? "Your network test results are ready" : "Test my network",
                       labels: labels, on: network.shown, ring: network.running,
                       badge: network.readyLevel.map { (NetworkView.mark($0), NetworkView.color($0)) }) {
                let open = !network.shown
                closeAll()
                if open { network.open() }
            }
            // leftovers to clear, last: the one tool that changes things on the Mac. A drawn broom was hard to make out
            // at this size, and macOS's bubbles and sparkles came next; now an open hard disk with sparkles, line drawn:
            // where it clears space, and that it cleans (macOS's own drive symbol is ambiguous)
            ToolButton(symbol: HardDisk.name, name: "Cleaner", tip: "Clear what deleted apps left behind", labels: labels, on: tools.cleaner) {
                let open = !tools.cleaner
                closeAll()
                tools.cleaner = open
            }
            // no Activity Monitor button: it's not Cool Head's tool, and anyone who wants it knows where it is; no Quit
            // either: it's on the Settings page and in the right-click menu, so the bar has room for the tools' names
            // without crowding
            Spacer(minLength: 4)
            // Report, Trusted, and Settings are about Cool Head itself, not the Mac, a separate kind of button: a line sets
            // them apart when the names show. No Update button: the version and Check Now are on the Settings page, and an
            // update that's ready shows at the top of the panel with Install
            if labels { Divider().frame(height: 34).padding(.horizontal, 4) }
            // Trusted is Cool Head's own list, not a tool for the Mac, so it's on the right, between Report and Settings
            ToolButton(symbol: "exclamationmark.bubble", name: "Report", tip: "Report a problem", labels: labels, on: watcher.showReport) {
                let open = !watcher.showReport
                closeAll()
                watcher.showReport = open
            }
            ToolButton(symbol: "checkmark.shield", name: "Trusted", tip: "Trusted apps and jobs", labels: labels, on: tools.trusted) {
                let open = !tools.trusted
                closeAll()
                tools.trusted = open
            }
            // Settings at the right end
            ToolButton(symbol: "gearshape", name: "Settings", tip: "Settings", labels: labels, on: tools.settings) {
                let open = !tools.settings
                closeAll()
                tools.settings = open
            }
        }
    }

    /// Before a tool opens: the others close, and Managed by Cool Head folds, so one thing is open at a time.
    func closeAll() { Tools.closeAll(watcher); PanelFocus.shared.foldSection() }
}

/// Which of the panel's own tools is open (Report a problem's flag lives in the watcher, as before), and the setting
/// for the tools' names.
@MainActor
final class Tools: ObservableObject {
    static let shared = Tools()
    /// For screenshots: COOLHEAD_SNAPSHOT_TRUSTED opens the Trusted tool, with made-up lists.
    @Published var trusted = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_TRUSTED"] != nil
    @Published var battery = false
    @Published var hardware = false
    @Published var settings = false
    @Published var cleaner = false
    /// Report a problem is open in the Managed by Cool Head section, under what Cool Head is holding back.
    @Published var reportAboutHeld = false

    /// Closes every tool, in one place, so they all behave alike: opening one closes the others, and the panel always
    /// opens with none open. A network test still running carries on, and its results wait in Network.
    static func closeAll(_ watcher: Watcher) {
        NetworkTester.shared.close()
        shared.trusted = false
        shared.battery = false
        shared.hardware = false
        shared.settings = false
        shared.cleaner = false
        shared.reportAboutHeld = false
        watcher.showReport = false
    }
    /// Show each tool's name under its icon (on by default; Show tool names on the Settings page).
    nonisolated static let labelsKey = "toolLabels"
}

/// A tool's icon at a size: a macOS symbol, or one of Cool Head's own drawings, named like symbols so a tool can use either.
struct ToolIcon: View {
    let symbol: String
    var size: CGFloat = 15
    var body: some View {
        switch symbol {
        case BatteryBolt.name: Image(nsImage: BatteryBolt.image(pointSize: size))
        case MacOutline.name: MacOutline(size: size)
        case HardDisk.name: Image(nsImage: HardDisk.image(size: size))
        default: Image(systemName: symbol)
        }
    }
}

/// The Hardware tool's icon: this Mac, line drawn like the icons beside it (macOS's own laptop and desktop have filled
/// screens): a laptop when it has a battery, a desktop when it doesn't. Matching the model isn't needed, and a Mac mini
/// or Studio drawn this small reads as a drive.
struct MacOutline: View {
    static let name = "coolhead.mac"
    /// A battery means a laptop: every MacBook has one, and no desktop Mac does. In a screenshot, a laptop.
    /// COOLHEAD_SNAPSHOT_DESKTOP draws a desktop in a screenshot.
    static let laptop = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_DESKTOP"] == nil && (PanelView.sampleSnapshot || {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        return service != 0
    }())
    var size: CGFloat = 15
    var body: some View {
        let k = size / 15
        Group {
            if MacOutline.laptop {
                VStack(spacing: 0.6 * k) {
                    RoundedRectangle(cornerRadius: 1.8 * k).strokeBorder(lineWidth: 1.4 * k).frame(width: 15 * k, height: 10.5 * k)
                    Capsule().frame(width: 20 * k, height: 1.6 * k)
                }
            } else {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.8 * k).strokeBorder(lineWidth: 1.4 * k).frame(width: 18 * k, height: 12.5 * k)
                    Rectangle().frame(width: 2.2 * k, height: 2 * k)
                    Capsule().frame(width: 8 * k, height: 1.5 * k)
                }
            }
        }
        .frame(width: 20 * k, height: 16 * k)
        .accessibilityHidden(true)
    }
}

/// The Cleaner tool's icon: an open hard disk, line drawn (its case, platter, and arm), with large sparkles at its corner
/// that cut a thin gap in the case, as the Battery icon's bolt does. Universal where macOS's own drive symbol is
/// ambiguous, and not dated the way a floppy disk is. Drawn as a template image, like the bolt, so the cut is clean in
/// light and dark and the image takes the tool's color.
enum HardDisk {
    static let name = "coolhead.harddisk"
    static func image(size: CGFloat) -> NSImage {
        let k = size / 15
        // the disk sits in the middle, with room to the right and above for the sparkles
        let canvas = NSSize(width: 26 * k, height: 22 * k)
        let sparkles = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10.5 * k, weight: .semibold))
        let image = NSImage(size: canvas, flipped: false) { _ in
            NSColor.black.set()
            let disk = NSRect(x: 13 * k - 7 * k, y: 11 * k - 8.5 * k, width: 14 * k, height: 17 * k)
            let body = NSBezierPath(roundedRect: disk.insetBy(dx: 0.7 * k, dy: 0.7 * k), xRadius: 1.8 * k, yRadius: 1.8 * k)
            body.lineWidth = 1.4 * k; body.stroke()
            let hub = NSPoint(x: disk.midX, y: disk.midY + 1.6 * k)
            let platter = NSBezierPath(ovalIn: NSRect(x: hub.x - 3.85 * k, y: hub.y - 3.85 * k, width: 7.7 * k, height: 7.7 * k))
            platter.lineWidth = 1.3 * k; platter.stroke()
            NSBezierPath(ovalIn: NSRect(x: hub.x - k, y: hub.y - k, width: 2 * k, height: 2 * k)).fill()
            // the arm, leaning in from the bottom right
            let arm = NSBezierPath(), mid = NSPoint(x: disk.midX + 2.9 * k, y: disk.midY - 3.4 * k)
            arm.move(to: NSPoint(x: mid.x - 1.72 * k, y: mid.y - 2.46 * k)); arm.line(to: NSPoint(x: mid.x + 1.72 * k, y: mid.y + 2.46 * k))
            arm.lineWidth = 1.3 * k; arm.lineCapStyle = .round; arm.stroke()
            if let sparkles {
                let at = NSPoint(x: 19.5 * k - sparkles.size.width / 2, y: 16 * k - sparkles.size.height / 2)
                let gap = max(1, 1.1 * k)
                for dx in [-gap, 0, gap] { for dy in [-gap, 0, gap] {
                    sparkles.draw(at: NSPoint(x: at.x + dx, y: at.y + dy), from: .zero, operation: .destinationOut, fraction: 1)
                } }
                sparkles.draw(at: at, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cleaner"
        return image
    }
}

/// The Power tool's icon: the battery with a bolt on a laptop, a plug on a Mac with no battery.
enum PowerIcon {
    static var name: String { MacOutline.laptop ? BatteryBolt.name : "powerplug" }
}

/// The Power tool's icon on a laptop: a battery a quarter full with a bolt through it, built from macOS's own symbols as it draws
/// (no image file), since macOS has a bolt only on a full battery, which was hard to read; the bolt reads better on a
/// less-full battery. The bolt cuts a thin gap in what's under it, as macOS's own charging icon does, and the image is a
/// template, so it takes the tool's color like the symbols beside it.
enum BatteryBolt {
    static let name = "coolhead.battery.bolt"
    static func image(pointSize: CGFloat) -> NSImage {
        guard let battery = NSImage(systemSymbolName: "battery.25percent", accessibilityDescription: "Battery")?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)),
              let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize * 0.62, weight: .heavy))
        else { return NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "Battery") ?? NSImage() }
        let image = NSImage(size: battery.size, flipped: false) { r in
            battery.draw(in: r)
            let at = NSPoint(x: r.width * 0.47 - bolt.size.width / 2, y: r.midY - bolt.size.height / 2)
            let gap = max(1, pointSize / 13)
            for dx in [-gap, 0, gap] { for dy in [-gap, 0, gap] {
                bolt.draw(at: NSPoint(x: at.x + dx, y: at.y + dy), from: .zero, operation: .destinationOut, fraction: 1)
            } }
            bolt.draw(at: at, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Battery"
        return image
    }
}

/// A tool: its icon, with its name under it (or, with names hidden, as a tooltip), tinted while it's open.
struct ToolButton: View {
    let symbol: String
    let name: String
    let tip: String
    let labels: Bool
    let on: Bool
    /// Something of the tool's is under way: rainbow dashes fly around the icon's equator, whether the tool is open or
    /// closed.
    var ring = false
    /// A small mark at the icon's corner, results ready to look at: their symbol, in their color.
    var badge: (symbol: String, color: Color)? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ToolIcon(symbol: symbol, size: 15)
                .font(.system(size: 15))
                .frame(height: 18)
                // the far half of the ring behind the globe, fainter; the near half in front of it
                .background { if ring { Orbit(near: false, still: still, on: on, hovering: hovering) } }
                .overlay { if ring { Orbit(near: true, still: still, on: on, hovering: hovering) } }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Image(systemName: badge.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(badge.color)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
                            .offset(x: 6, y: -4)
                    }
                }
                if labels { Text(name).font(.caption2) }
            }
            .frame(minWidth: labels ? 44 : 30)
            // room each side of the name, so an open tool's highlight doesn't sit tight on it; the names keep their size,
            // rather than shrinking to make the room
            .padding(.horizontal, labels ? 5 : 2)
            .padding(.vertical, labels ? 5 : 6)
            // the open tool in white on the deep blue, 7.4:1 (see Ink.fill), where blue on a pale blue measured 3:1 to 4.4:1
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Ink.fill : hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Ink.onFill : hovering ? Ink.text : Ink.muted)
        .onHover { hovering = $0 }
        .help(tip)
        .accessibilityLabel(tip)
    }
}

/// Half of a flat ring around an icon's equator, its dashes moving along it like data going around the world: the near
/// half passes in front, the far half behind and fainter. A small neon rainbow, so the data stands apart from the gray
/// icon, moving left to right across the front, and a quiet nod to pride. Not orange, which says "watch out": a test
/// running is Cool Head at work, not a warning. With Reduce motion on, the dashes stay still.
struct Orbit: View {
    let near: Bool
    let still: Bool
    /// The tool is open: the gaps the dashes cut take the open button's highlight.
    var on = false
    var hovering = false
    @Environment(\.barWash) private var wash
    /// Red, orange, yellow, green, blue, and violet, bright enough to read as neon on both the light and dark bar.
    static let rainbow = LinearGradient(colors: [Color(red: 1, green: 0.18, blue: 0.33), Color(red: 1, green: 0.58, blue: 0),
                                                 Color(red: 1, green: 0.84, blue: 0.04), Color(red: 0.19, green: 0.82, blue: 0.35),
                                                 Color(red: 0.04, green: 0.52, blue: 1), Color(red: 0.75, green: 0.35, blue: 0.95)],
                                        startPoint: .leading, endPoint: .trailing)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { t in
            // one dash length and its gap travel every 0.4 seconds, left to right across the near half
            let phase = still ? 0 : CGFloat(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.4) / 0.4 * 5.5)
            let half = Ellipse().trim(from: near ? 0 : 0.5, to: near ? 0.5 : 1)
            ZStack {
                // in front, each dash cuts a thin gap in the globe's lines, as the Battery icon's bolt does, so it reads
                // the gap is drawn in what's behind the button, layer by layer: the window, the bar's tint, and the
                // button's own highlight when it's open or under the mouse
                if near {
                    let gap = StrokeStyle(lineWidth: 3.9, lineCap: .round, dash: [2.5, 3], dashPhase: phase)
                    half.stroke(Color(nsColor: .windowBackgroundColor), style: gap)
                    half.stroke(wash, style: gap)
                    if on { half.stroke(Ink.fill, style: gap) }
                    else if hovering { half.stroke(Color.primary.opacity(0.07), style: gap) }
                }
                let dashes = StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [2.5, 3], dashPhase: phase)
                // a neon rainbow fixed across the ring, so each dash changes color as it travels through it, with a soft
                // glow of the same colors over it; the same whether the tool is open or closed, so a test always looks the same
                half.stroke(Orbit.rainbow, style: dashes)
                    .overlay { half.stroke(Orbit.rainbow, style: dashes).blur(radius: 1.6).opacity(0.9) }
            }
            .opacity(near ? 1 : 0.4)
        }
        .frame(width: 27, height: 8)
        .allowsHitTesting(false)
    }
}

/// The apps and jobs you trust, as a standard macOS list: select one and press − to stop trusting it, or + to choose an
/// app to trust. Jobs and scripts are trusted from the clock on their card, where Cool Head knows exactly which one.
struct TrustedView: View {
    let watcher: Watcher
    @ObservedObject var tools = Tools.shared
    @State private var list: [Item]
    @State private var selected: String?
    @State private var note: String?
    /// Always cooler: what runs cooler every time (CoolerRules), with its own selection and note.
    @State private var cooler: [Item]
    @State private var coolerSelected: String?
    @State private var coolerNote: String?

    struct Item: Identifiable, Equatable {
        let key: String
        let name: String
        var id: String { key }
        /// What it is, from how it was trusted: an app (by its identifier), a script, or a program.
        var kind: String { key.hasPrefix("app:") ? "App" : key.hasPrefix("script:") ? "Script" : "Program" }
    }

    /// `preset` is for renders; the panel reads the list.
    init(watcher: Watcher, preset: [Item]? = nil, presetCooler: [Item]? = nil) {
        self.watcher = watcher
        let render = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_TRUSTED"] != nil
        _list = State(initialValue: preset ?? (render ? [Item(key: "app:com.example.photobackup", name: "Photo Backup"),
                                                         Item(key: "script:/Users/you/tools/export.py", name: "export.py")] : TrustedView.load()))
        _cooler = State(initialValue: presetCooler ?? (render ? [Item(key: "app:com.example.huddle", name: "Huddle"),
                                                                 Item(key: "script:/Users/you/Sites/site/server.js", name: "server.js")] : TrustedView.loadCooler()))
    }

    static func load() -> [Item] { sorted(Trust.all) }
    static func loadCooler() -> [Item] { sorted(CoolerRules.all) }
    static func sorted(_ d: [String: String]) -> [Item] {
        d.map { Item(key: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Trusting and always slowing are opposites, so a change to one list can change the other.
    func reload() { list = TrustedView.load(); cooler = TrustedView.loadCooler() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Trusted", systemImage: "checkmark.shield").font(.body.weight(.semibold))
                Spacer()
                Button { tools.trusted = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            Text("Their cards stay calm. We still flag one if it looks stuck, your Mac gets hot, or it runs nonstop for \(Int(Trust.limitHours)) hours.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            box(list, empty: "No trusted apps or jobs", selected: $selected, addTip: "Trust an app", removeTip: "Stop trusting the selected one",
                add: { choose(cooler: false) }) { key in
                watcher.untrust(key: key)
                reload(); selected = nil; note = nil
            }
            Text(note ?? "To trust a job or script, use the clock on its card.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            Divider().padding(.vertical, 4)
            Label("Always cooler", systemImage: "tortoise").font(.body.weight(.semibold))
            Text("Slowed every time: an app while you aren't using it, back to full speed when you switch to it; a job whenever it runs.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            box(cooler, empty: "Nothing runs cooler every time", selected: $coolerSelected, addTip: "Always run an app cooler",
                removeTip: "Stop running the selected one cooler", add: { choose(cooler: true) }) { key in
                watcher.removeRule(key: key)
                reload(); coolerSelected = nil; coolerNote = nil
            }
            Text(coolerNote ?? "To add a job or script, press Every time after Run it cooler on its card. Trusting something takes it off this list.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    /// A list and its +/− bar, in one bordered box, as in System Settings.
    func box(_ items: [Item], empty: String, selected: Binding<String?>, addTip: String, removeTip: String,
             add: @escaping () -> Void, remove: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(empty)
                        .font(.callout).foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        row(item, stripe: i % 2 == 1, selected: selected)
                    }
                }
            }
            .frame(minHeight: 64, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            HStack(spacing: 0) {
                barButton("plus", addTip, action: add)
                Divider().frame(height: 16)
                barButton("minus", removeTip) { if let key = selected.wrappedValue { remove(key) } }
                    .disabled(selected.wrappedValue == nil)
                Divider().frame(height: 16)
                Spacer()
            }
            .frame(height: 22)
            .background(Color.primary.opacity(0.03))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.edge, lineWidth: 1))
    }

    func row(_ item: Item, stripe: Bool, selected: Binding<String?>) -> some View {
        let on = selected.wrappedValue == item.key
        return HStack(spacing: 8) {
            icon(item).frame(width: 18, height: 18)
            Text(item.name).font(.callout).lineLimit(1)
            Spacer()
            Text(item.kind).font(.caption).foregroundStyle(on ? Color.white.opacity(0.85) : Ink.muted)
        }
        .foregroundStyle(on ? Color.white : Ink.text)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(on ? Ink.accent : stripe ? Color.primary.opacity(0.035) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selected.wrappedValue = on ? nil : item.key }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// An app's own icon, found by its identifier; a script or program gets a plain one.
    @ViewBuilder func icon(_ item: Item) -> some View {
        if item.key.hasPrefix("app:"), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: String(item.key.dropFirst(4))) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: item.key.hasPrefix("app:") ? "app" : item.key.hasPrefix("script:") ? "doc.text" : "terminal").foregroundStyle(Ink.muted)
        }
    }

    func barButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 26, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
        .accessibilityLabel(tip)
    }

    /// + : choose an app in Applications to trust, or to always run cooler.
    func choose(cooler: Bool) {
        let open = NSOpenPanel()
        open.title = cooler ? "Always run an app cooler" : "Trust an app"
        open.prompt = cooler ? "Add" : "Trust"
        open.allowedContentTypes = [.application]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        if cooler {
            if watcher.addRule(appPath: url.path) {
                reload(); coolerSelected = self.cooler.first { $0.name == name }?.key; coolerNote = nil
            } else {
                coolerNote = "macOS's own apps can't be slowed: Cool Head explains them instead."
            }
        } else if watcher.trust(appPath: url.path) {
            reload(); selected = list.first { $0.name == name }?.key; note = nil
        } else {
            note = "macOS's own apps can't be trusted: Cool Head explains them instead."
        }
    }
}

/// The tools bar's tint (the level's color, as the top row has), so a gap cut in an icon matches what's behind it.
private struct BarWashKey: EnvironmentKey { static let defaultValue = Color.clear }
extension EnvironmentValues {
    var barWash: Color {
        get { self[BarWashKey.self] }
        set { self[BarWashKey.self] = newValue }
    }
}

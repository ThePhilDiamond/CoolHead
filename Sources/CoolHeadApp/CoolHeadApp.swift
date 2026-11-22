import AppKit
import CoolHeadChromeLink
import CoolHeadCore
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct CoolHeadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // The menu bar item is AppKit's NSStatusItem (in AppDelegate), not SwiftUI's MenuBarExtra,
    // because only the status item can tell a left-click (the panel) from a right-click (a small menu).
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var item: NSStatusItem!
    private let panel = MenuPanel()
    private var lastLevel: Watcher.Level?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)          // menu bar only, no Dock icon
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }  // crashes outside an app bundle
        let watcher = Watcher.shared
        watcher.onAlert = { card in Alerts.send(card) }
        watcher.onReminder = { text in Alerts.remind(text) }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuIcon.image(level: .good)
        item.button?.setAccessibilityLabel("Cool Head")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // a screenshot copy draws off screen and quits; it never appears in the menu bar, where it could be mistaken for
        // the real one (its panel hides every card but the demo, so it showed "Running warm" with nothing listed).
        // It hides under its own name: macOS saves a status item's visibility by name for every copy of the app, and
        // hiding the usual one hid the installed Cool Head too.
        if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] != nil { item.autosaveName = "snapshot"; item.isVisible = false }

        let host = NSHostingController(rootView: PanelView(watcher: watcher))
        host.sizingOptions = [.preferredContentSize]
        panel.setContent(host)

        // redraw the icon when the status level changes
        watcher.onPublish = { [weak self] in
            // every card on screen, the whole-Mac ones too (see CardSources.swift), by the same rule as the panel's snowflake
            let level = watcher.screenLevel
            guard let self, self.lastLevel != level else { return }
            self.lastLevel = level
            self.item.button?.image = MenuIcon.image(level: level)
        }
        // the icon picked on the Settings page or the welcome, drawn at once
        NotificationCenter.default.addObserver(forName: MenuIcon.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.item.button?.image = MenuIcon.image(level: Watcher.shared.screenLevel) }
        }
        watcher.start()
        // the link with Cool Head for Chrome, not while taking screenshots (see ChromeLinkServer)
        if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] == nil {
            ChromeLinkServer.shared.start()
            // a Cool Head that moved since Set up, or an update that allows a new extension ID: the file is written again
            if FileManager.default.fileExists(atPath: ChromeCompanion.hostsFolder + "/" + ChromeLink.hostName + ".json"), !ChromeCompanion.hostFileInstalled() {
                ChromeCompanion.installHostFile()
            }
        }
        HardwareWatch.shared.onAlert = { Alerts.remind($0) }
        for source in CardSources.all { source.start(watcher) }    // see CardSources.swift
        Updater.shared.schedule()
        // first launch: there's no window, so open the panel under the icon with a welcome, once; after an update
        // that brought something worth telling, open it once with what's new
        if (!UserDefaults.standard.bool(forKey: "welcomed") || WhatsNew.pending != nil) && ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showPanel() }
        }
        // for testing the whole update path: check and install at launch (COOLHEAD_UPDATE_TEST=1)
        if ProcessInfo.processInfo.environment["COOLHEAD_UPDATE_TEST"] != nil {
            Task { await Updater.shared.check(quiet: false); if case .available = Updater.shared.phase { await Updater.shared.install() } }
        }
        if let path = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] { Snapshot.take(to: path) }
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.close()
            // a shortcut menu, short: every setting, the version, and updates are on the Settings page in the panel,
            // behind the gear at the right of the toolbar
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "About Cool Head", action: #selector(about), keyEquivalent: "").target = self
            // Cool Head's own action, not NSApplication's terminate:, for which macOS 26 adds an icon that sets this one
            // item apart from the rest; without it, all the menu's items line up
            menu.addItem(withTitle: "Quit Cool Head", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            button.performClick(nil)          // shows the menu under the icon
            item.menu = nil                   // so the next left-click opens the panel again
        } else if panel.isVisible {
            panel.close()
        } else {
            panel.show(under: button)
        }
    }

    /// The panel, open on its Settings page.
    @objc func openSettings() {
        showPanel()
        Tools.closeAll(Watcher.shared)
        PanelFocus.shared.foldSection()
        Tools.shared.settings = true
    }

    @objc func about() { About.show() }

    @objc func quit() { NSApp.terminate(nil) }


    /// Nothing is left frozen: paused jobs carry on when Cool Head quits.
    func applicationWillTerminate(_ notification: Notification) {
        Watcher.shared.resumeAllPaused(why: "Cool Head quit")
        Watcher.shared.closePressureSpell()
        // a running network test stops with Cool Head (macOS doesn't stop a program's children when it quits)
        MainActor.assumeIsolated { NetworkTester.shared.halt() }
    }


    func showPanel() {
        guard let button = item.button, !panel.isVisible else { return }
        panel.show(under: button)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner])
    }
}

/// At most one quiet notification per card, only for cards that need a look, only when turned on.
enum Alerts {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifications") }
    }

    /// A short reminder (sync to resume, low battery). Never names a project or script.
    static func remind(_ text: String) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Cool Head"
            c.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    static func send(_ card: LiveCard) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Cool Head"
            // never the headline: it can hold a project or script name, and macOS keeps notification text
            c.body = card.card.state == .stalled ? "A job looks stuck. Open Cool Head to see which, and what to do."
                : "Something has been busy for a while. Open Cool Head to see what, and what to do."
            center.add(UNNotificationRequest(identifier: card.id, content: c, trigger: nil))
        }
    }
}

/// The standard About panel, with what Cool Head is and where its source lives.
@MainActor
enum About {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let body = NSFont.systemFont(ofSize: 11)
        let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        let center = NSMutableParagraphStyle(); center.alignment = .center
        let credits = NSMutableAttributedString(string: "Let cooler heads prevail.\n\n", attributes: [.font: italic])
        // the same sentence as the README's opening, the repository's description, and its social card
        credits.append(NSAttributedString(string: "Is your Mac running hot or slow? Cool Head says why in one sentence, with options to act in one click, plus tools to test your network, check your battery and hardware, and clear space.\n\n",
                                          attributes: [.font: body]))
        credits.append(NSAttributedString(string: "github.com/ThePhilDiamond/CoolHead",
                                          attributes: [.font: body, .link: URL(string: "https://github.com/ThePhilDiamond/CoolHead")!]))
        credits.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        credits.append(NSAttributedString(string: "Terms of use",
                                          attributes: [.font: body, .link: URL(string: "https://github.com/ThePhilDiamond/CoolHead/blob/main/TERMS.md")!]))
        credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
        // macOS shows the version and then the build number in brackets; they're the same here, so the build is left out
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Cool Head",
                                                     .applicationVersion: "Version \(CoolHead.version)", .version: ""])
        // in front of the panel, which floats at the menus' level, when it's open; otherwise About opens behind it
        // `NSApp.windows`, not `orderedWindows`, which is empty for an app without a Dock icon, so 0.11.0 found nothing
        // to raise and About still opened behind the panel (tested in a throwaway app)
        if MenuPanel.isOpen {
            for w in NSApp.windows where w is NSPanel && !(w is MenuPanel) && w.isVisible && w.level < .abovePanel { w.level = .abovePanel }
        }
    }
}

extension NSWindow.Level {
    /// Just above Cool Head's panel (`.popUpMenu`), for a window opened from it: About, or the folder chooser.
    static let abovePanel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
}

enum LoginItem {
    static var on: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
    }
}

/// The menu bar icon: a melting snowflake with a status badge at its top right. The badge's shape and color both carry
/// the meaning, for people who can't tell the colors apart: green circle, all well; yellow triangle, something needs a
/// look; red octagon, a problem. The flake is drawn in the menu bar's text color at draw time, so it follows light
/// and dark menu bars even though the image isn't a template (templates can't hold color).
enum MenuIcon {
    /// Posted when the icon's style changes, so the menu bar redraws it.
    static let changed = Notification.Name("CoolHeadMenuIconChanged")
    /// "badge": the melting snowflake with a status badge. "melting": the snowflake itself melts as things get worse.
    static var style: String {
        get { UserDefaults.standard.string(forKey: "iconStyle") ?? "badge" }
        set { UserDefaults.standard.set(newValue, forKey: "iconStyle") }
    }

    static func image(level: Watcher.Level, style: String = MenuIcon.style) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            if style == "melting" { melting(level) } else { badged(level) }
            return true
        }
        img.isTemplate = false
        return img
    }

    static let ice = NSColor(srgbRed: 0.35, green: 0.72, blue: 1.0, alpha: 1)

    /// The snowflake's spokes; `keep` chooses which spokes are drawn, and `length` how much of each.
    static func flake(center c: NSPoint, r: CGFloat, color: NSColor = .labelColor, width: CGFloat = 1.4, keep: (Int) -> CGFloat = { _ in 1 }) {
        color.setStroke()
        for i in 0..<6 {
            let len = keep(i)
            guard len > 0 else { continue }
            let a = CGFloat(i) * .pi / 3 + .pi / 2
            let spoke = NSBezierPath()
            spoke.move(to: c)
            spoke.line(to: NSPoint(x: c.x + cos(a) * r * len, y: c.y + sin(a) * r * len))
            if len >= 0.7 {
                let m = NSPoint(x: c.x + cos(a) * r * 0.58, y: c.y + sin(a) * r * 0.58)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let b = a + side * .pi / 4
                    spoke.move(to: m)
                    spoke.line(to: NSPoint(x: m.x + cos(b) * r * 0.36, y: m.y + sin(b) * r * 0.36))
                }
            }
            spoke.lineWidth = width
            spoke.lineCapStyle = .round
            spoke.stroke()
        }
    }

    /// The Status badge style: one melting snowflake, the Melting Snowflake's middle drawing with its ice-blue drops and
    /// puddle, the same at every level, so only the badge changes. It ties the style to the app icon's melting snowflake.
    /// The app icon's paler drops and quieter puddle were not used here: they're harder to see at the menu bar's size, so
    /// the ice-blue ones keep the contrast. See docs/BRAND.md.
    static func badged(_ level: Watcher.Level) {
        let tips = droopingFlake(center: NSPoint(x: 8.5, y: 10.2), r: 6.4)
        ice.setFill()
        for (k, t) in tips.enumerated() { drop(at: NSPoint(x: t.x, y: t.y - 2.2 - CGFloat(k % 2) * 0.7), size: 1.0) }
        NSBezierPath(ovalIn: NSRect(x: 3.5, y: 0.4, width: 10, height: 1.8)).fill()
        // clear a ring for the badge so it stands apart from the flake
        let box = NSRect(x: 12, y: 10.5, width: 7.5, height: 7.5)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: box.insetBy(dx: level == .warning ? -1.6 : -1, dy: level == .warning ? -1.6 : -1)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        Badge.path(level, in: box).fill(with: level)
    }

    /// Calm: a whole snowflake. Worth watching (something slowing the Mac or needing a look): its lower half has melted,
    /// dripping into a small puddle. A serious problem: it bursts into flames. The level is `Watcher.level(_:)`.
    /// Each drawing fills the whole icon. A yellow or red bar underneath was tried and dropped, because making room for
    /// it shrank the drawings too much; without it they can be bigger.
    static func melting(_ level: Watcher.Level) {
        switch level {
        case .good:
            flake(center: NSPoint(x: 10, y: 9), r: 7.5)
        case .warning:
            // every arm is still there, so it reads as a snowflake: the upper arms sag a little, the lower ones are
            // shorter and droop, and drops fall from their tips into a small puddle
            let tips = droopingFlake(center: NSPoint(x: 10, y: 10.5), r: 6.8)
            ice.setFill()
            for (k, t) in tips.enumerated() { drop(at: NSPoint(x: t.x, y: t.y - 2.4 - CGFloat(k % 2) * 0.8), size: 1.1) }
            NSBezierPath(ovalIn: NSRect(x: 4.5, y: 0.4, width: 11, height: 2.0)).fill()
        case .issue:
            onFire()
        }
    }

    /// Problem: it got so hot the snowflake burst into flames. A flame with a wide base, a curving main tip, and two
    /// smaller licks, and inside it the white snowflake it used to be, chosen over several other ideas.
    static func onFire() {
        let f = NSBezierPath()
        f.move(to: NSPoint(x: 10, y: 0.6))
        f.curve(to: NSPoint(x: 3.3, y: 6.6), controlPoint1: NSPoint(x: 5.4, y: 0.6), controlPoint2: NSPoint(x: 3.2, y: 3.2))
        f.curve(to: NSPoint(x: 5.0, y: 13.2), controlPoint1: NSPoint(x: 3.3, y: 9.4), controlPoint2: NSPoint(x: 4.3, y: 11.6))      // left lick
        f.curve(to: NSPoint(x: 7.4, y: 11.0), controlPoint1: NSPoint(x: 5.9, y: 12.0), controlPoint2: NSPoint(x: 6.7, y: 11.2))
        f.curve(to: NSPoint(x: 10.9, y: 17.8), controlPoint1: NSPoint(x: 7.8, y: 13.8), controlPoint2: NSPoint(x: 9.6, y: 15.8))     // main tip
        f.curve(to: NSPoint(x: 13.3, y: 12.4), controlPoint1: NSPoint(x: 12.4, y: 16.2), controlPoint2: NSPoint(x: 13.4, y: 14.4))
        f.curve(to: NSPoint(x: 15.2, y: 14.0), controlPoint1: NSPoint(x: 14.1, y: 12.7), controlPoint2: NSPoint(x: 14.8, y: 13.3))    // right lick
        f.curve(to: NSPoint(x: 16.7, y: 6.6), controlPoint1: NSPoint(x: 16.4, y: 11.6), controlPoint2: NSPoint(x: 16.9, y: 9.2))
        f.curve(to: NSPoint(x: 10, y: 0.6), controlPoint1: NSPoint(x: 16.8, y: 3.2), controlPoint2: NSPoint(x: 14.6, y: 0.6))
        f.close()
        NSGradient(colors: [NSColor.systemRed, NSColor.systemOrange, NSColor(srgbRed: 1, green: 0.78, blue: 0.2, alpha: 1)])!.draw(in: f, angle: 90)
        flake(center: NSPoint(x: 10, y: 6.6), r: 4.3, color: .white, width: 1.1)
    }

    /// A snowflake whose arms bend downward as if softening: upper arms sag slightly, lower arms are shorter and droop.
    /// Returns the tips of the three lower arms, where drops form.
    @discardableResult
    static func droopingFlake(center c: NSPoint, r: CGFloat, width: CGFloat = 1.4, color: NSColor = .labelColor, sagScale: CGFloat = 1) -> [NSPoint] {
        color.setStroke()
        var lowerTips: [NSPoint] = []
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 + .pi / 2
            let lower = sin(a) < -0.1
            let len = r * (lower ? 0.78 : 0.95)
            let sag: CGFloat = (lower ? 1.9 : 0.9) * sagScale
            let end = NSPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len - sag)
            let control = NSPoint(x: c.x + cos(a) * len * 0.55, y: c.y + sin(a) * len * 0.55)
            let arm = NSBezierPath()
            arm.move(to: c)
            arm.curve(to: end, controlPoint1: control, controlPoint2: control)
            // side branches, also sagging
            let mid = NSPoint(x: c.x + cos(a) * len * 0.58, y: c.y + sin(a) * len * 0.58 - sag * 0.45)
            for side in [-1.0, 1.0] as [CGFloat] {
                let b = a + side * .pi / 4
                arm.move(to: mid)
                arm.line(to: NSPoint(x: mid.x + cos(b) * len * 0.34, y: mid.y + sin(b) * len * 0.34 - sag * 0.5))
            }
            arm.lineWidth = width
            arm.lineCapStyle = .round
            arm.stroke()
            if lower { lowerTips.append(end) }
        }
        return lowerTips
    }

    /// Six plain arms, no side branches: clear even at a few points across.
    static func smallFlake(center c: NSPoint, r: CGFloat) {
        let arms = NSBezierPath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 + .pi / 2
            arms.move(to: c)
            arms.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        arms.lineWidth = 1.1
        arms.lineCapStyle = .round
        NSColor.white.setStroke()           // white on the flame, in light and dark menu bars alike
        arms.stroke()
    }

    /// A falling drop: round at the bottom, pointed at the top.
    static func drop(at p: NSPoint, size d: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x, y: p.y + d * 1.4))
        path.curve(to: NSPoint(x: p.x, y: p.y - d * 0.5), controlPoint1: NSPoint(x: p.x - d * 0.9, y: p.y), controlPoint2: NSPoint(x: p.x - d * 0.6, y: p.y - d * 0.5))
        path.curve(to: NSPoint(x: p.x, y: p.y + d * 1.4), controlPoint1: NSPoint(x: p.x + d * 0.6, y: p.y - d * 0.5), controlPoint2: NSPoint(x: p.x + d * 0.9, y: p.y))
        path.fill()
    }
}

/// The status badge's shape, shared by the menu bar icon and the panel's status line.
enum Badge {
    static func path(_ level: Watcher.Level, in r: NSRect) -> NSBezierPath {
        switch level {
        case .good:
            return NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        case .warning:
            // an equilateral caution triangle with rounded corners, centred in the box
            // a little larger than the box, so it carries the same weight as the circle and octagon
            let side = r.width * 1.22, h = side * sqrt(3) / 2, cy = r.midY + r.height * 0.04
            let top = NSPoint(x: r.midX, y: cy + h / 2)
            let right = NSPoint(x: r.midX + side / 2, y: cy - h / 2), left = NSPoint(x: r.midX - side / 2, y: cy - h / 2)
            let radius = side * 0.16
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: left.y))
            p.appendArc(from: right, to: top, radius: radius)
            p.appendArc(from: top, to: left, radius: radius)
            p.appendArc(from: left, to: right, radius: radius)
            p.close()
            return p
        case .issue:
            let p = NSBezierPath()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4 + .pi / 8
                let pt = NSPoint(x: r.midX + cos(a) * r.width / 2, y: r.midY + sin(a) * r.height / 2)
                i == 0 ? p.move(to: pt) : p.line(to: pt)
            }
            p.close()
            return p
        }
    }

    static func color(_ level: Watcher.Level) -> NSColor {
        // a deeper, more vivid yellow than macOS's systemYellow, which looks pale on a light menu bar
        switch level {
        case .good: return .systemGreen
        case .warning: return NSColor(srgbRed: 1.0, green: 0.74, blue: 0.0, alpha: 1)
        case .issue: return .systemRed
        }
    }

    /// The panel's version, as SF Symbols with the same shapes.
    static func symbol(_ level: Watcher.Level) -> String {
        switch level { case .good: return "circle.fill"; case .warning: return "exclamationmark.triangle.fill"; case .issue: return "xmark.octagon.fill" }
    }
}

extension NSBezierPath {
    func fill(with level: Watcher.Level) {
        Badge.color(level).setFill(); fill()
        // a fine dark edge keeps yellow and green visible on a light menu bar
        NSColor.black.withAlphaComponent(0.45).setStroke(); lineWidth = 0.6; stroke()
    }
}

/// For screenshots and checks: after 25 seconds of watching, draws the panel in light and dark to PNG files and quits.
/// COOLHEAD_SNAPSHOT=/path/prefix "Cool Head.app/Contents/MacOS/Cool Head"
enum Snapshot {
    static func take(to prefix: String) {
        if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CHECK"] != nil { Task { await Updater.shared.check(quiet: false) } }
        let after = Double(ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_AFTER"] ?? "") ?? 25
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            // the About panel, title bar included, light and dark, to <prefix>-about-light.png and -dark.png
            if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ABOUT"] != nil {
                let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                About.show()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                if let panel = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }),
                   let frame = panel.contentView?.superview {
                    for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                        panel.appearance = NSAppearance(named: look)
                        frame.layoutSubtreeIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
                        frame.cacheDisplay(in: frame.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-about-\(name).png"))
                    }
                    panel.close()
                }
            }
            // (COOLHEAD_SNAPSHOT_REPORT=held: opened from the button under what Cool Head is holding back)
            if let how = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_REPORT"] {
                if how == "held" { Tools.shared.reportAboutHeld = true } else { Watcher.shared.showReport = true }
            }
            // the Battery tool's page, with a made-up battery when the screenshot uses example cards
            if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_BATTERY"] != nil { Tools.shared.battery = true }
            // the Hardware tool's page, with made-up hardware (COOLHEAD_SNAPSHOT_HARDWARE=healthy or issue)
            if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HARDWARE"] != nil { Tools.shared.hardware = true }
            // the Cleaner tool's page, with made-up finds
            if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] != nil { Tools.shared.cleaner = true }
            // the Settings page
            if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SETTINGS"] != nil { Tools.shared.settings = true }
            // Test my network's result, with made-up figures (never this Mac's network)
            // (COOLHEAD_SNAPSHOT_NETWORK=reading, ready, testing or done: the page in that state)
            // (COOLHEAD_SNAPSHOT_NETWORK_VPN=all, some or off: a made-up VPN carrying everything, only a few addresses, or
            // none; "done" also shows where websites see you, made up too)
            if let state = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_NETWORK"] {
                let kind = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_NETWORK_VPN"] ?? "all"
                let vpn: NetworkCheck.VPN? = kind == "off" ? nil : .init(name: "WireGuard", carries: kind == "some" ? .someAddresses : .everything, lookups: kind != "some")
                let setup = NetworkCheck.Setup(link: .wifi(.init(rssi: -58, noise: -92, rate: 864, channel: 44, band: "5 GHz")), vpn: vpn,
                                               dns: vpn?.lookups == true ? .internet : .router, dnsName: vpn?.lookups == true ? "Quad9" : nil,
                                               dnsSetBy: vpn?.lookups == true ? .vpn : .network, router: "192.168.1.1", physical: "en0")
                let phase: NetworkTester.Phase = state == "reading" ? .reading : state == "ready" ? .ready
                    : state == "testing" ? .testing(started: Date().addingTimeInterval(-9))
                    : .done(.done(.init(download: 240_000_000, upload: 38_000_000, rpm: 1_100)))
                let here = NetworkCheck.Seen(address: "198.51.100.4", country: "US")
                let seen: NetworkCheck.Where? = state != "done" ? nil
                    : vpn?.carriesWebsites == true ? .seen(.init(address: "203.0.113.7", country: "NL"), around: .other(here))
                    : .seen(here, around: .notAsked)
                NetworkTester.shared.show(phase, setup: setup, seen: seen)
                // (COOLHEAD_SNAPSHOT_NETWORK_AWAY=1: the view closed, to show the Network tool's running or ready cue)
                if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_NETWORK_AWAY"] != nil { NetworkTester.shared.showAway() }
            }
            // screenshots: run the card whose headline contains this phrase cooler first, to show the pinned row
            if let phrase = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_COOL"],
               let c = Watcher.shared.cards.first(where: { $0.card.headline.contains(phrase) }) {
                _ = Watcher.shared.setCooler(c, on: true)
            }
            // and pause the card whose headline contains this phrase, to show the paused row
            if let phrase = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_PAUSE"],
               let c = Watcher.shared.cards.first(where: { $0.card.headline.contains(phrase) }) {
                _ = Watcher.shared.pauseJob(c)
            }
            for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let host = NSHostingView(rootView: PanelView(watcher: Watcher.shared).background(.background))
                host.appearance = NSAppearance(named: look)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: look)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                // the scrolling middle measures itself after the first layout; let that land, then size again
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
            }
            // the menu bar icon at each level, on a light and a dark menu bar, at 4x
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 360, pixelsHigh: 320, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let rows: [(NSColor, NSAppearance.Name, String)] = [(NSColor(white: 0.93, alpha: 1), .aqua, "badge"), (NSColor(white: 0.17, alpha: 1), .darkAqua, "badge"),
                                                                (NSColor(white: 0.93, alpha: 1), .aqua, "melting"), (NSColor(white: 0.17, alpha: 1), .darkAqua, "melting")]
            for (row, (bg, look, style)) in rows.enumerated() {
                bg.setFill(); NSRect(x: 0, y: CGFloat(row) * 80, width: 360, height: 80).fill()
                NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
                    for (i, level) in [Watcher.Level.good, .warning, .issue].enumerated() {
                        MenuIcon.image(level: level, style: style).draw(in: NSRect(x: 20 + CGFloat(i) * 120, y: CGFloat(row) * 80 + 4, width: 80, height: 72))
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-menu.png"))
            NSApp.terminate(nil)
        }
    }
}

/// The panel under the menu bar icon: a plain rounded rectangle with the system's translucent menu background, like
/// macOS's own menu bar items (the Battery menu, for one). It replaces NSPopover, which always draws an arrow.
/// It closes when you click elsewhere or press Escape, and follows its content's size up to a maximum height.
@MainActor
final class MenuPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private var host: NSHostingController<PanelView>?
    private var monitor: Any?
    private var sizeObservation: NSKeyValueObservation?
    private weak var anchor: NSStatusBarButton?

    /// Showing now, so a window opened from it goes in front (`.abovePanel`).
    static var isOpen: Bool { NSApp.windows.contains { $0 is MenuPanel && $0.isVisible } }
    /// While a window opened from the panel is up (the folder chooser), clicks in it don't close the panel: macOS draws
    /// the chooser in its own process, so they arrive as clicks elsewhere, and choosing a folder would close the panel.
    static var keepOpen = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 300), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView = effect
    }

    override var canBecomeKey: Bool { true }      // for typing in Report a problem

    func setContent(_ controller: NSHostingController<PanelView>) {
        host = controller
        controller.sizingOptions = [.preferredContentSize]
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: effect.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        // keep the top edge under the icon as the content grows or shrinks
        sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] c, _ in
            Task { @MainActor in self?.fit(c.preferredContentSize) }
        }
    }

    func show(under button: NSStatusBarButton) {
        anchor = button
        for source in CardSources.all { source.panelOpened() }     // each at most once a minute
        PanelFocus.shared.opened += 1
        if let size = host?.preferredContentSize, size.height > 0 { fit(size) } else { fit(NSSize(width: PanelView.width, height: 300)) }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        // close on a click anywhere else
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if !MenuPanel.keepOpen { self?.close() } }
        }
    }

    private func fit(_ size: NSSize) {
        guard let button = anchor, let bw = button.window, let screen = bw.screen ?? NSScreen.main else { return }
        let iconFrame = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let w = size.width, h = min(size.height, visible.height - 16)
        // centered under the icon when it opens; while open, its left edge stays put, so when it grows by the scroll
        // bar's room nothing in it moves sideways
        var x = isVisible ? frame.minX : iconFrame.midX - w / 2
        x = min(max(x, visible.minX + 8), visible.maxX - w - 8)
        let top = iconFrame.minY - 6
        setFrame(NSRect(x: x, y: top - h, width: w, height: h), display: true)
    }

    override func close() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if isVisible { Watcher.shared.panelClosed() }
        // every tool closes with the panel, so it always opens with none open; a network test started carries on
        MainActor.assumeIsolated { Tools.closeAll(Watcher.shared) }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) { close() }     // Escape
}

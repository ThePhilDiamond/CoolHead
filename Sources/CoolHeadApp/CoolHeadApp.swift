import AppKit
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var lastLevel: Watcher.Level?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)          // menu bar only, no Dock icon
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }  // crashes outside an app bundle
        let watcher = Watcher.shared
        watcher.onAlert = { card in Alerts.send(card) }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuIcon.image(level: .good)
        item.button?.setAccessibilityLabel("Cool Head")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let host = NSHostingController(rootView: PanelView(watcher: watcher))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient

        // redraw the icon when the status level changes
        watcher.onPublish = { [weak self] in
            guard let self, self.lastLevel != watcher.level else { return }
            self.lastLevel = watcher.level
            self.item.button?.image = MenuIcon.image(level: watcher.level)
        }
        watcher.start()
        if let path = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] { Snapshot.take(to: path) }
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            let menu = NSMenu()
            menu.addItem(withTitle: "About Cool Head", action: #selector(about), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Cool Head", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            button.performClick(nil)          // shows the menu under the icon
            item.menu = nil                   // so the next left-click opens the panel again
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func about() { About.show() }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
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

    static func send(_ card: LiveCard) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Cool Head"
            c.body = card.card.headline
            center.add(UNNotificationRequest(identifier: card.id, content: c, trigger: nil))
        }
    }
}

/// The standard About panel, with what Cool Head is and where its source lives.
enum About {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "Why is my Mac hot? One sentence, one action.\nFree and open source under the GNU AGPL v3.0.\n\n")
        credits.append(NSAttributedString(string: "github.com/ThePhilDiamond/CoolHead",
                                          attributes: [.link: URL(string: "https://github.com/ThePhilDiamond/CoolHead")!]))
        credits.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Cool Head"])
    }
}

enum LoginItem {
    static var on: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
    }
}

/// The menu bar icon: a snowflake with a status badge at its top right. The badge's shape and colour both carry the
/// meaning, for people who can't tell the colours apart: green circle, all well; yellow triangle, something needs a
/// look; red octagon, a problem. The flake is drawn in the menu bar's text colour at draw time, so it follows light
/// and dark menu bars even though the image isn't a template (templates can't hold colour).
enum MenuIcon {
    static func image(level: Watcher.Level) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let c = NSPoint(x: 8.5, y: 8.5), r: CGFloat = 7
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 2
                let spoke = NSBezierPath()
                spoke.move(to: c)
                spoke.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                let m = NSPoint(x: c.x + cos(a) * r * 0.58, y: c.y + sin(a) * r * 0.58)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let b = a + side * .pi / 4
                    spoke.move(to: m)
                    spoke.line(to: NSPoint(x: m.x + cos(b) * r * 0.36, y: m.y + sin(b) * r * 0.36))
                }
                spoke.lineWidth = 1.4
                spoke.lineCapStyle = .round
                spoke.stroke()
            }
            // clear a ring for the badge so it stands apart from the flake
            let box = NSRect(x: 12, y: 10.5, width: 7.5, height: 7.5)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: box.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            Badge.path(level, in: box).fill(with: level)
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// The status badge's shape, shared by the menu bar icon and the panel's status line.
enum Badge {
    static func path(_ level: Watcher.Level, in r: NSRect) -> NSBezierPath {
        switch level {
        case .good:
            return NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        case .warning:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: r.maxY)); p.line(to: NSPoint(x: r.maxX, y: r.minY)); p.line(to: NSPoint(x: r.minX, y: r.minY)); p.close()
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
        switch level { case .good: return .systemGreen; case .warning: return .systemYellow; case .issue: return .systemRed }
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
        NSColor.black.withAlphaComponent(0.35).setStroke(); lineWidth = 0.6; stroke()
    }
}

/// For screenshots and checks: after 25 seconds of watching, draws the panel in light and dark to PNG files and quits.
/// COOLHEAD_SNAPSHOT=/path/prefix "Cool Head.app/Contents/MacOS/Cool Head"
enum Snapshot {
    static func take(to prefix: String) {
        let after = Double(ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_AFTER"] ?? "") ?? 25
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let host = NSHostingView(rootView: PanelView(watcher: Watcher.shared).background(.background))
                host.appearance = NSAppearance(named: look)
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: look)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
            }
            // the menu bar icon at each level, on a light and a dark menu bar, at 4x
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 360, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            for (row, (bg, look)) in [(NSColor(white: 0.93, alpha: 1), NSAppearance.Name.aqua), (NSColor(white: 0.17, alpha: 1), .darkAqua)].enumerated() {
                bg.setFill(); NSRect(x: 0, y: CGFloat(row) * 80, width: 360, height: 80).fill()
                NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
                    for (i, level) in [Watcher.Level.good, .warning, .issue].enumerated() {
                        MenuIcon.image(level: level).draw(in: NSRect(x: 20 + CGFloat(i) * 120, y: CGFloat(row) * 80 + 4, width: 80, height: 72))
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-menu.png"))
            NSApp.terminate(nil)
        }
    }
}

import AppKit
import CoolHeadCore
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct CoolHeadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var watcher = Watcher.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(watcher: watcher)
        } label: {
            Image(nsImage: MenuIcon.image(alert: watcher.needsLook))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)          // menu bar only, no Dock icon
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }  // crashes outside an app bundle
        Watcher.shared.onAlert = { card in Alerts.send(card) }
        Watcher.shared.start()
        if let path = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT"] { Snapshot.take(to: path) }
    }

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

enum LoginItem {
    static var on: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
    }
}

/// The menu bar icon: a snowflake, drawn as a template so it follows the menu bar's colour; a small dot appears
/// at its top right when something needs a look. (A smiley was tried first; at 18 points its face didn't read.)
enum MenuIcon {
    static func image(alert: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let c = NSPoint(x: 9, y: 9), r: CGFloat = 7.2
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 2
                let spoke = NSBezierPath()
                spoke.move(to: c)
                spoke.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                // one pair of short branches on each spoke
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
            if alert {
                // clear a ring around the dot so it stands apart from the flake
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 11.5, y: 11, width: 7, height: 7)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 12, width: 5, height: 5)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
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
            // the menu bar icon, calm and with its dot, on a light and a dark menu bar, at 4x
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            for (row, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.17, alpha: 1), NSColor.white)].enumerated() {
                bg.setFill(); NSRect(x: 0, y: CGFloat(row) * 80, width: 320, height: 80).fill()
                for (i, alert) in [false, true].enumerated() {
                    let icon = MenuIcon.image(alert: alert)
                    let tinted = NSImage(size: icon.size, flipped: false) { r in icon.draw(in: r); fg.set(); r.fill(using: .sourceAtop); return true }
                    tinted.draw(in: NSRect(x: 40 + CGFloat(i) * 160, y: CGFloat(row) * 80 + 4, width: 72, height: 72))
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-menu.png"))
            NSApp.terminate(nil)
        }
    }
}

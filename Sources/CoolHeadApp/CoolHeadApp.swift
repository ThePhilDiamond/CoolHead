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

/// The menu bar icon: an ice cube with a bolt, drawn as a template so it follows the menu bar's colour;
/// a small dot appears when something needs a look.
enum MenuIcon {
    static func image(alert: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let cube = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 14), xRadius: 4, yRadius: 4)
            cube.lineWidth = 1.6
            NSColor.black.setStroke()
            cube.stroke()
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 10.2, y: 14))
            bolt.line(to: NSPoint(x: 5.6, y: 8.2))
            bolt.line(to: NSPoint(x: 8.8, y: 8.2))
            bolt.line(to: NSPoint(x: 7.8, y: 4))
            bolt.line(to: NSPoint(x: 12.4, y: 9.8))
            bolt.line(to: NSPoint(x: 9.2, y: 9.8))
            bolt.close()
            NSColor.black.setFill()
            bolt.fill()
            if alert {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 13, y: 13, width: 5, height: 5)).fill()
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
            NSApp.terminate(nil)
        }
    }
}

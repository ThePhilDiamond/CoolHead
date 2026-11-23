import AppKit
import CoolHeadCore

extension ChromeCompanion {
    /// Opens the extension's Chrome Web Store page in Chrome itself, since only Chrome can add it (another default
    /// browser would show the page without Add to Chrome); in the default browser if Chrome isn't where it usually is.
    static func openStorePage() {
        guard let url = URL(string: getPage) else { return }
        let chrome = URL(fileURLWithPath: chromeApp)
        if FileManager.default.fileExists(atPath: chrome.path) {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

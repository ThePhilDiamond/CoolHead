import Foundation
import CoolHeadChromeLink

/// Cool Head for Chrome, the extension that works with Cool Head (Extension/chrome), offered on the Settings page and
/// among the memory card's fixes, with a sign in Settings showing when the two are working together. Linked through
/// Chrome's native messaging: Chrome starts Cool Head's helper only for this extension, named in a small file Cool Head
/// places in Chrome's NativeMessagingHosts folder when the person presses Set up (see ChromeLinkServer).
public enum ChromeCompanion {
    public enum Status: Equatable { case noChrome, notInstalled, connected }

    public static let name = "Cool Head for Chrome"
    /// What it does, in one sentence, for the welcome card, Settings, and the option that offers it.
    public static let pitch = "Puts Chrome tabs you aren't using to sleep when memory is tight, keeps the ones you choose awake, and makes Cool Head's Chrome options one click."
    /// How to get it: until it's in the Chrome Web Store, its page in Cool Head's repository says how to add it by hand.
    public static let getPage = "https://github.com/ThePhilDiamond/CoolHead/tree/main/Extension/chrome#readme"
    public static let chromeApp = "/Applications/Google Chrome.app"
    /// The extension's ID in the Chrome Web Store, and its ID while it's added by hand, fixed by the key in its manifest
    /// (Extension/chrome/README.md). Cool Head's helper answers either.
    public static let storeID = "pobnaljpjmpbpokcdbjpmlkdaljhhcfm"
    public static let handID = "idncmcjhcnoknfiomdkjidgmjkglmghl"
    public static let extensionIDs = [storeID, handID]
    /// Chrome's own folder for the files that name native messaging helpers.
    public static let hostsFolder = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/NativeMessagingHosts"

    /// For screenshots, COOLHEAD_SNAPSHOT_COMPANION=connected or none; otherwise whether an extension is linked now.
    public static var status: Status {
        switch ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_COMPANION"] {
        case "connected": return .connected
        case "none": return .notInstalled
        default:
            if ChromeLinkServer.shared.summary.connected { return .connected }
            return FileManager.default.fileExists(atPath: chromeApp) ? .notInstalled : .noChrome
        }
    }

    /// Writes the file that lets Chrome start Cool Head's helper for this extension, naming the helper inside this copy
    /// of Cool Head (so it must be written again if Cool Head moves). Only that one file, in Chrome's own folder for it.
    @discardableResult
    public static func installHostFile(folder: String = hostsFolder, helper: String = Bundle.main.bundlePath + "/Contents/Helpers/coolhead-chrome-host") -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helper), let json = ChromeLink.manifest(hostPath: helper, extensionIDs: extensionIDs) else { return false }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = folder + "/" + ChromeLink.hostName + ".json"
        return FileManager.default.createFile(atPath: path, contents: Data(json), attributes: [.posixPermissions: 0o644])
    }

    /// Whether that file is there, names this copy's helper, and allows every ID this version knows, so a Cool Head that
    /// moved, or an update that knows a new ID, writes it again.
    public static func hostFileInstalled(folder: String = hostsFolder, helper: String = Bundle.main.bundlePath + "/Contents/Helpers/coolhead-chrome-host") -> Bool {
        guard let d = FileManager.default.contents(atPath: folder + "/" + ChromeLink.hostName + ".json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return j["path"] as? String == helper && j["allowed_origins"] as? [String] == ChromeLink.origins(extensionIDs)
    }
}

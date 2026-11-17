import Foundation

/// Whether an update can run on this Mac, checked before it replaces the copy that works: the update's own minimum
/// macOS (its Info.plist's LSMinimumSystemVersion) against this Mac's. Without it, a Mac below an update's minimum would
/// swap a working copy for one macOS refuses to open (found 17 November 2026, before the minimum moves past macOS 14).
public enum UpdateCheck {
    /// "15.0" or "15" against this Mac's version: true when this Mac is at or above it. An unreadable minimum counts as
    /// fitting, as macOS itself treats a missing one.
    public static func runs(minimum: String?, on os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard let minimum else { return true }
        let need = minimum.split(separator: ".").map { Int($0) ?? 0 }
        let have = [os.majorVersion, os.minorVersion, os.patchVersion]
        for i in 0..<3 {
            let n = i < need.count ? need[i] : 0
            if have[i] != n { return have[i] > n }
        }
        return true
    }

    /// What to tell the person when it can't run here.
    public static func tooOld(version: String, minimum: String) -> String {
        "Cool Head \(version) needs macOS \(minimum) or later. This copy stays as it is."
    }
}

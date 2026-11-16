import Foundation

/// A sync app kept busy by a build or other job writing lots of files into a folder it syncs (found on Phil's Mac,
/// 15 November 2026: Google Drive logged about 22,700 failed uploads in under two hours, all Java and Android build
/// output from a project inside Documents, which Drive backed up; they stopped when the project moved out). The sync
/// app uploads every file a build writes, including short-lived ones it then can't find.
///
/// Which folders a sync app syncs is known for certain only for its own folder (in ~/Library/CloudStorage, or
/// ~/Dropbox). Documents and Desktop are often backed up too (Google Drive, OneDrive, iCloud), but only the sync app's
/// own settings say so, and Cool Head doesn't read another app's settings, so for those it says "may".
/// Paths are compared as text: nothing in a synced folder is opened or listed.
public struct SyncFeed: Equatable {
    /// The job writing: its project folder's name, or its program's name.
    public let who: String
    /// The folder it is writing in, by name only (the provider's folder name can hold an email address).
    public let folder: String
    /// nil when the folder is in the sync app's own folder; "Documents" or "Desktop" when it is in one of those,
    /// which the sync app may be backing up.
    public let area: String?
    public var certain: Bool { area == nil }
    /// The folder's full path, to show it in Finder.
    public var path: String = ""

    /// Which sync app owns a folder in ~/Library/CloudStorage, by the folder's prefix.
    static let cloudStoragePrefixes: [(prefix: String, app: String)] = [
        ("GoogleDrive-", "Google Drive"), ("Dropbox", "Dropbox"), ("OneDrive", "OneDrive"), ("Box-", "Box"),
    ]

    /// Where `path` sits, for the sync app named `sync`: in its own folder (certain), in Documents or Desktop
    /// (it may be backing those up), or neither (nil). `home` is the home folder.
    /// `.some(nil)` for its own folder, `.some("Documents")` or `.some("Desktop")`, or nil for neither.
    public static func place(_ path: String, sync: String, home: String = NSHomeDirectory()) -> String?? {
        let cloud = home + "/Library/CloudStorage/"
        if path.hasPrefix(cloud) {
            let top = path.dropFirst(cloud.count).split(separator: "/").first.map(String.init) ?? ""
            return cloudStoragePrefixes.contains { top.hasPrefix($0.prefix) && $0.app == sync } ? .some(nil) : nil
        }
        if sync == "Dropbox", path == home + "/Dropbox" || path.hasPrefix(home + "/Dropbox/") { return .some(nil) }
        for f in ["Documents", "Desktop"] where path == home + "/" + f || path.hasPrefix(home + "/" + f + "/") { return .some(f) }
        return nil
    }

    /// The job most likely keeping `sync` busy, from processes writing lots to disk right now: each with its working
    /// folder, a name for it, and how much it wrote in the last sample. A job in the sync app's own folder wins over
    /// one in Documents or Desktop; then the one writing most.
    public static func find(sync: String, writers: [(cwd: String, who: String, bytes: UInt64)], home: String = NSHomeDirectory()) -> SyncFeed? {
        let placed = writers.compactMap { w in place(w.cwd, sync: sync, home: home).map { (w, $0) } }
        guard let best = placed.max(by: { ($0.1 == nil ? 1 : 0, $0.0.bytes) < ($1.1 == nil ? 1 : 0, $1.0.bytes) }) else { return nil }
        return SyncFeed(who: best.0.who, folder: (best.0.cwd as NSString).lastPathComponent, area: best.1, path: best.0.cwd)
    }

    /// A sentence for the sync app's card.
    public func sentence(_ sync: String) -> String {
        if let area {
            return "It may be uploading the files \(who) is writing in \(folder), inside \(area): if \(sync) backs up \(area), it uploads every file written there."
        }
        return "It's probably uploading the files \(who) is writing in \(folder), a folder \(sync) syncs: it uploads every file written there."
    }

    /// The fix: keep the project out of synced folders.
    public func fix(_ sync: String, recommended: Bool) -> Fix {
        let steps = "Move it to a folder \(sync) doesn't sync, such as one in your home folder, or exclude it in \(sync)'s settings."
        return Fix(id: "movebuild", title: "Keep \(folder) out of synced folders", consequence: "Shows it in Finder. " + steps,
                   kind: .reveal(path, steps), recommended: recommended)
    }
}

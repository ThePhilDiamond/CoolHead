import Foundation
import CoreServices

/// Build output kept out of Time Machine. A build rewrites thousands of files, and Time Machine copies every changed file
/// at its next backup, so a busy backup can be mostly a build's own output, which the build makes again anyway.
///
/// A "sticky" exclusion, the kind `tmutil addexclusion` sets without -p or -v, follows the folder and needs no
/// administrator password; only the -p and -v forms need one (from tmutil(8) on macOS
/// 26.6.2). Cool Head sets it through Core Services (CSBackupSetItemExcluded), and its selftest checks that `tmutil
/// isexcluded` then agrees. Undone by removing it.
///
/// Only folders that are build output by their name (see `buildFolders`), inside your home folder: never a project
/// itself, and never anything a build can't make again.
public struct BackupFeed: Equatable {
    /// The job writing there: its program's name.
    public let who: String
    /// The build-output folder's full path.
    public let path: String
    public var name: String { (path as NSString).lastPathComponent }
    /// The folder it's in, by name (the project), for the card.
    public var project: String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }

    public func sentence() -> String {
        "It probably backs up \(name) in \(project), which \(who) keeps rewriting. Time Machine copies every changed file."
    }

    public func fix(recommended: Bool) -> Fix {
        Fix(id: "backup", title: "Keep \(name) out of Time Machine",
            consequence: CardTemplate.says("This makes later backups skip it. A build makes this folder again, so you do not need a backup of it.", undo: true),
            kind: .keepOutOfBackup(path), recommended: recommended)
    }
}

public enum BackupExclusions {
    /// Folder names that hold only what a build or package manager makes again: Xcode, Swift, Gradle, Maven and Rust,
    /// JavaScript, Python and CocoaPods.
    public static let buildFolders: Set<String> = ["DerivedData", "build", ".build", ".gradle", "target", "dist", "node_modules", ".next", "__pycache__", "Pods"]
    /// What Cool Head excluded, so it can be undone from the top of the panel.
    public static let marker = "backupExcluded"

    /// The build-output folder a written file is in, inside `home`: the path up to the first folder named as build output.
    public static func buildFolder(of file: String, home: String = NSHomeDirectory()) -> String? {
        guard file.hasPrefix(home + "/") else { return nil }
        var path = home
        for part in file.dropFirst(home.count + 1).split(separator: "/").dropLast() {
            path += "/" + part
            if buildFolders.contains(String(part)) { return path }
        }
        return nil
    }

    /// The job most likely keeping Time Machine busy: of the jobs writing lots right now, the one writing most into a
    /// build-output folder that isn't already left out of backups.
    public static func find(writers: [(who: String, files: [String], bytes: UInt64)], home: String = NSHomeDirectory(),
                            excluded: (String) -> Bool = BackupExclusions.isExcluded) -> BackupFeed? {
        for w in writers.sorted(by: { $0.bytes > $1.bytes }) {
            let folders = Set(w.files.compactMap { buildFolder(of: $0, home: home) })
            if let f = folders.sorted().first(where: { !excluded($0) }) { return BackupFeed(who: w.who, path: f) }
        }
        return nil
    }

    /// Left out of backups: the folder itself, or a folder it's in.
    public static func isExcluded(_ path: String) -> Bool {
        var p = path
        while p.count > 1 {
            var byPath: DarwinBoolean = false
            if CSBackupIsItemExcluded(URL(fileURLWithPath: p) as CFURL, &byPath) { return true }
            p = (p as NSString).deletingLastPathComponent
        }
        return false
    }

    /// Leaves it out of later backups. True when it took.
    @discardableResult
    public static func exclude(_ path: String, marker m: String = marker) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              CSBackupSetItemExcluded(URL(fileURLWithPath: path) as CFURL, true, false) == noErr else { return false }
        var byPath: DarwinBoolean = false
        let ok = CSBackupIsItemExcluded(URL(fileURLWithPath: path) as CFURL, &byPath)
        if ok { record(path, on: true, marker: m) }
        return ok
    }

    /// Backs it up again. True when it took.
    @discardableResult
    public static func include(_ path: String, marker m: String = marker) -> Bool {
        if FileManager.default.fileExists(atPath: path) {
            guard CSBackupSetItemExcluded(URL(fileURLWithPath: path) as CFURL, false, false) == noErr else { return false }
        }
        var byPath: DarwinBoolean = false
        let ok = !CSBackupIsItemExcluded(URL(fileURLWithPath: path) as CFURL, &byPath)
        if ok { record(path, on: false, marker: m) }
        return ok
    }

    /// What Cool Head left out and is still left out (a folder since deleted, or included again some other way, drops off).
    public static func excludedByCoolHead(marker m: String = marker) -> [String] {
        (UserDefaults.standard.stringArray(forKey: m) ?? []).filter { FileManager.default.fileExists(atPath: $0) && isExcluded($0) }
    }

    static func record(_ path: String, on: Bool, marker m: String) {
        var list = (UserDefaults.standard.stringArray(forKey: m) ?? []).filter { $0 != path }
        if on { list.append(path) }
        if list.isEmpty { UserDefaults.standard.removeObject(forKey: m) } else { UserDefaults.standard.set(list, forKey: m) }
    }
}

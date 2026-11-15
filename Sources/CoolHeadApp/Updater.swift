import AppKit
import CoolHeadCore
import CryptoKit
import Foundation
import Observation

/// Checks GitHub for a newer release and installs it, after proving it was signed by the project.
///
/// What it sends: one request to GitHub's public API for the latest release, and, if you install, the download of
/// that release's zip and signature. No information about you, your Mac or your processes.
/// How it knows the update is genuine: each release zip is signed with the project's private key in the release
/// workflow; the matching public key is built into this app, and an update whose signature doesn't verify is refused.
@MainActor @Observable
final class Updater {
    static let shared = Updater()
    /// The public half of the update-signing key (see docs/UPDATES.md). Changing it means older versions can't
    /// verify newer updates, so it changes only if the private key is lost or exposed.
    static let publicKey = "SGry6+624YcbH/CXiGNnZZv/iGwlkWfqjqCxg3JbNI8="
    static let latestURL = URL(string: "https://api.github.com/repos/ThePhilDiamond/CoolHead/releases/latest")!

    enum Phase: Equatable { case idle, checking, upToDate, available(String), installing, failed(String) }
    var phase: Phase = .idle
    var releasePage: URL?
    private var zip: URL?
    private var sig: URL?
    private var timer: Timer?

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "checkForUpdates"); schedule() }
    }

    /// Checks a minute after launch and then once a day, when automatic checks are on.
    func schedule() {
        timer?.invalidate()
        guard automatic else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in Task { @MainActor in await Updater.shared.check(quiet: true) } }
        Task { try? await Task.sleep(for: .seconds(60)); await check(quiet: true) }
    }

    /// `quiet`: an automatic check says nothing unless there is an update.
    func check(quiet: Bool) async {
        if case .installing = phase { return }
        if !quiet { phase = .checking }
        do {
            var req = URLRequest(url: Updater.latestURL)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, let assets = json["assets"] as? [[String: Any]] else {
                throw Problem("GitHub's answer wasn't readable")
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            releasePage = (json["html_url"] as? String).flatMap(URL.init(string:))
            func asset(_ suffix: String) -> URL? {
                assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                    .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
            }
            zip = asset(".zip"); sig = asset(".zip.sig")
            if Updater.newer(version, than: CoolHead.version) {
                phase = .available(version)
                Watcher.shared.log("Update available: \(version)")
            } else if !quiet { phase = .upToDate }
        } catch {
            if !quiet { phase = .failed("Couldn't check for updates: \(error.localizedDescription)") }
        }
    }

    /// Downloads, verifies and installs the update, then reopens Cool Head.
    func install() async {
        guard case .available(let version) = phase else { return }
        guard let zip, let sig else {
            phase = .failed("This release isn't signed for updating from inside the app. Download it from its release page instead.")
            return
        }
        phase = .installing
        do {
            let (zipFile, _) = try await URLSession.shared.download(from: zip)
            let (sigData, _) = try await URLSession.shared.data(from: sig)
            let zipData = try Data(contentsOf: zipFile)
            // 1. the signature: made with the project's private key, or refused
            guard let keyData = Data(base64Encoded: Updater.publicKey),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
                  let signature = Data(base64Encoded: String(decoding: sigData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
                  key.isValidSignature(signature, for: zipData) else {
                throw Problem("the update's signature didn't match, so it wasn't installed")
            }
            // 2. unpack it beside nothing else, and check it is Cool Head at the version expected
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("CoolHeadUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Updater.run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
            let app = work.appendingPathComponent("Cool Head.app")
            guard let info = Bundle(url: app)?.infoDictionary,
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info["CFBundleShortVersionString"] as? String == version else {
                throw Problem("the download wasn't the expected version of Cool Head")
            }
            try Updater.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            // 3. replace this copy (the old one goes to the Trash, so it can be put back) and reopen
            let here = Bundle.main.bundleURL
            try FileManager.default.trashItem(at: here, resultingItemURL: nil)
            try FileManager.default.moveItem(at: app, to: here)
            Watcher.shared.log("Updated to \(version)")
            let reopen = Process()
            reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
            reopen.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", here.path]
            try reopen.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed((error as? Problem)?.message ?? "The update couldn't be installed: \(error.localizedDescription)")
            Watcher.shared.log("Update to \(version) failed")
        }
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Problem("a check on the download failed (\((tool as NSString).lastPathComponent))") }
    }

    struct Problem: Error { let message: String; init(_ m: String) { message = m } }
}

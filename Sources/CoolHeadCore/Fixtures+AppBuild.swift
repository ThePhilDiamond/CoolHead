import Foundation

/// Checks for what a busy app is built on (see AppBuild, research rules 19 and 20), and the example cards
/// `coolhead wording` shows for it.
extension Fixture {
    static let intelAppPath = "/Applications/Old Tool.app/Contents/MacOS/Old Tool"
    static let windowServerPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
    static let spotlightPathForApps = "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores"

    /// The example cards (see Wording).
    static func appBuildSamples(_ now: Date) -> [(String, Card)] {
        let app = Evidence.sample(name: "Old Tool", path: intelAppPath, start: now.addingTimeInterval(-3 * 3600), cores: 1.5)
        let ws = catalogueProcess("WindowServer", windowServerPath, mine: false, start: now.addingTimeInterval(-9 * 3600), cores: 1.2, gpu: 0.6)
        func make(_ e: Evidence, _ f: AppBuild.Facts) -> Card { Card.make(e, now: now, busySince: now.addingTimeInterval(-40 * 60), apps: f) }
        return [("intel-app-26", make(app, .init(rosetta: .intelOnly, macOS: (26, 6)))),
                ("intel-app-27", make(app, .init(rosetta: .intelOnly, macOS: (27, 2)))),
                ("app-set-to-rosetta", make(app, .init(rosetta: .setToRosetta, macOS: (26, 6)))),
                ("windowserver-old-electron", make(ws, .init(oldElectron: ["Figma", "Loom"], macOS: (26, 1))))]
    }

    static func appBuildChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []

        // Rosetta: an Intel-only program, from its header; a universal one running translated; nothing for a native one
        func be(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
        func fat(_ cpus: [UInt32]) -> Data {
            var d = Data([0xCA, 0xFE, 0xBA, 0xBE]) + be(UInt32(cpus.count))
            for c in cpus { d += be(c) + Data(count: 16) }
            return d
        }
        let thin = Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01])            // 64-bit, x86_64, little-endian
        let a = AppBuild.architectures(header:)
        let r1 = a(fat([0x0100_0007])) == ["x86_64"] && a(fat([0x0100_0007, 0x0100_000C])) == ["x86_64", "arm64"]
            && a(thin) == ["x86_64"] && a(fat(Array(repeating: 0x0100_0007, count: 40))) == [] && a(Data("#!/bin/sh".utf8)) == []
            && AppBuild.rosetta(translated: false, architectures: ["x86_64"]) == .intelOnly
            && AppBuild.rosetta(translated: true, architectures: ["x86_64", "arm64"]) == .setToRosetta
            && AppBuild.rosetta(translated: false, architectures: ["x86_64", "arm64"]) == nil && AppBuild.rosetta(translated: nil, architectures: []) == nil
        review.append(("app-build-rosetta-read", r1, "headers: Intel-only, universal, thin Intel, a Java class file and a script told apart"))

        // the card, by macOS version: on 26 Rosetta and macOS 28; on 27 Apple's own list; "Open using Rosetta" only before 27
        let app = Evidence.sample(name: "Old Tool", path: intelAppPath, start: now.addingTimeInterval(-3 * 3600), cores: 1.5)
        func card(_ f: AppBuild.Facts) -> Card { Card.make(app, now: now, busySince: now.addingTimeInterval(-40 * 60), apps: f) }
        let on26 = card(.init(rosetta: .intelOnly, macOS: (26, 6))), on27 = card(.init(rosetta: .intelOnly, macOS: (27, 2)))
        let set26 = card(.init(rosetta: .setToRosetta, macOS: (26, 6))), set27 = card(.init(rosetta: .setToRosetta, macOS: (27, 2)))
        let mds = catalogueProcess("mds_stores", spotlightPathForApps, mine: false, start: now, cores: 1)
        let macOSCard = Card.make(mds, now: now, busySince: now.addingTimeInterval(-600), apps: .init(rosetta: .intelOnly, macOS: (26, 6)))
        let r2 = on26.explanation.hasSuffix("It's an Intel app, running through Rosetta, and it won't open in macOS 28.")
            && on26.fixes.contains { $0.kind == .lookUp("Old Tool Apple silicon") }
            && on27.explanation.contains("Settings lists the Intel apps affected") && on27.fixes.contains { $0.id == "intel" && $0.doer == .you }
            && set26.fixes.contains { $0.id == "native" } && !set27.fixes.contains { $0.id == "native" }
            && !macOSCard.explanation.contains("Intel app")
        review.append(("app-build-rosetta-card", r2, on26.explanation + " | 27: " + on27.explanation))

        // old Electron: below 36.9.2, 37.6.0, 38.2.0 or 39 lags 26.0 and 26.1 only; said on a busy WindowServer, with updating
        // recommended
        let lags = AppBuild.electronLags
        let ws = catalogueProcess("WindowServer", windowServerPath, mine: false, start: now.addingTimeInterval(-9 * 3600), cores: 1.2, gpu: 0.6)
        let wsCard = Card.make(ws, now: now, busySince: now.addingTimeInterval(-40 * 60), apps: .init(oldElectron: ["Figma", "Loom"], macOS: (26, 1)))
        let wsLater = Card.make(ws, now: now, busySince: now.addingTimeInterval(-40 * 60), apps: .init(oldElectron: ["Figma"], macOS: (26, 2)))
        let r3 = lags("36.6.0") && lags("19.1.8") && lags("37.5.9") && lags("38.1.2") && !lags("36.9.2") && !lags("37.6.0")
            && !lags("38.2.0") && !lags("39.0.0") && !lags("45.2.1") && !lags("36.10.0")
            && AppBuild.electronWindow((26, 0)) && AppBuild.electronWindow((26, 1)) && !AppBuild.electronWindow((26, 2)) && !AppBuild.electronWindow((27, 0))
            && wsCard.explanation.contains("Figma and Loom are built on an older Electron that makes macOS 26.1 draw slowly: update them.")
            && wsCard.recommended?.id == "electron" && !wsLater.explanation.contains("Electron")
        review.append(("app-build-old-electron", r3, wsCard.explanation + " Options: \(wsCard.fixes.map(\.id))"))

        // on this Mac, for real: this program's own header and translation flag, and the Electron version of every app in
        // /Applications (read only)
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let me = AppBuild.architectures(exe)
        let selfTranslated = AppBuild.translated(getpid())
        let apps = ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []).filter { $0.hasSuffix(".app") }.map { "/Applications/" + $0 }
        let electron = apps.compactMap { b in AppBuild.electronVersion(app: b).map { ((b as NSString).lastPathComponent, $0, AppBuild.electronLags($0)) } }
        let r4 = me.contains("arm64") && selfTranslated == false
        review.append(("app-build-this-mac", r4, "coolhead built for \(me.sorted()), translated \(String(describing: selfTranslated)); Electron apps here: "
                       + electron.map { "\($0.0) \($0.1)\($0.2 ? " (lags 26.0 to 26.1)" : "")" }.joined(separator: ", ")))
        return review
    }
}

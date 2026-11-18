import Foundation

/// Checks for crediting macOS's helpers to the app they work for (see Served, research rule 4), and the example cards
/// `coolhead wording` shows.
extension Fixture {
    static let webContentPath = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
    static let webGPUPath = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
    static let decoderPath = "/System/Library/Frameworks/VideoToolbox.framework/Versions/A/XPCServices/VTDecoderXPCService.xpc/Contents/MacOS/VTDecoderXPCService"
    static let safariCryptex = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"

    static func served(_ name: String, _ path: String, by bundle: String?, cores: Double = 1.5, now: Date) -> Evidence {
        var e = Evidence.sample(name: name, path: path, start: now.addingTimeInterval(-3600), cores: cores)
        e.servedBy = bundle
        return e
    }

    /// The example cards (see Wording).
    static func servedSamples(_ now: Date) -> [(String, Card)] {
        func card(_ e: Evidence) -> Card { Card.make(e, now: now, busySince: now.addingTimeInterval(-25 * 60)) }
        return [("web-page-in-app", card(served("com.apple.WebKit.WebContent", webContentPath, by: "/System/Applications/Mail.app", now: now))),
                ("macos-service-for-app", card(served("VTDecoderXPCService", decoderPath, by: "/Applications/IINA.app", now: now)))]
    }

    static func servedChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func card(_ e: Evidence) -> Card { Card.make(e, now: now, busySince: now.addingTimeInterval(-25 * 60)) }
        func words(_ c: Card) -> Int { (c.headline + " " + c.explanation).split(separator: " ").count }

        // only macOS's XPC services are credited, and only to an app the person opens
        let r1 = Served.isService(webContentPath) && Served.isService(decoderPath) && !Served.isService("/usr/bin/python3")
            && !Served.isService("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")
            && Served.opened("/Applications/Google Drive.app") && Served.opened("/System/Applications/Mail.app") && Served.opened(safariCryptex)
            && !Served.opened("/System/Library/CoreServices/Dock.app") && !Served.opened("/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex")
        review.append(("served-only-services-and-opened-apps", r1, "WebKit and the video decoder are services, python3 and Chrome's helper aren't; Google Drive, Mail, and Safari are opened apps, the Dock and the wallpaper aren't"))

        // web pages in another app: that app named and quitting it advised (a sync app stops syncing; the text doesn't
        // repeat the option); in Safari, or unknown, the Safari tab card as before
        let drive = card(served("com.apple.WebKit.WebContent", webContentPath, by: "/Applications/Google Drive.app", now: now))
        let safari = card(served("com.apple.WebKit.WebContent", webContentPath, by: safariCryptex, now: now))
        let unknown = card(served("com.apple.WebKit.WebContent", webContentPath, by: nil, now: now))
        var gpuE = served("com.apple.WebKit.GPU", webGPUPath, by: safariCryptex, cores: 0.2, now: now); gpuE.gpuShare = 0.4
        let gpu = card(gpuE)
        let q = drive.recommended
        let r2 = drive.headline == "A web page in Google Drive is working hard."
            && q?.id == "quit" && q?.kind == .quitApp("/Applications/Google Drive.app") && q?.consequence == "Stops syncing until you open it again." && q?.caution == false
            && !drive.explanation.contains("Quit") && words(drive) <= 40
            && safari.headline == "A Safari tab is working hard." && unknown.headline == "A Safari tab is working hard."
            && gpu.explanation.hasPrefix("The process that draws Safari's pages") && !gpu.explanation.contains("usually a Safari tab")
        review.append(("served-web-pages-credited", r2, "\(drive.headline) \(drive.explanation) Options: \(drive.fixes.map(\.id)); \(q?.consequence ?? "-") | Safari: \(safari.headline) | unknown: \(unknown.headline) | graphics: \(gpu.explanation)"))

        // another macOS service: what it's doing and for which app; quitting the app advised, except where that loses work
        let iina = card(served("VTDecoderXPCService", decoderPath, by: "/Applications/IINA.app", now: now))
        let utm = card(served("VTDecoderXPCService", decoderPath, by: "/Applications/UTM.app", now: now))
        let other = card(served("SomeService", "/System/Library/PrivateFrameworks/Some.framework/XPCServices/SomeService.xpc/Contents/MacOS/SomeService", by: "/Applications/IINA.app", now: now))
        let u = utm.fixes.first { $0.id == "quit" }
        let r3 = iina.headline == "macOS is decoding video for IINA." && iina.recommended?.kind == .quitApp("/Applications/IINA.app")
            && iina.recommended?.consequence == "It asks about anything unsaved." && words(iina) <= 40 && !iina.explanation.contains("Quit")
            && u?.caution == true && u?.recommended == false
            && other.headline == "A part of macOS is busy working for IINA."
        review.append(("served-service-credited", r3, "\(iina.headline) \(iina.explanation) | UTM quit caution \(u?.caution == true), recommended \(u?.recommended == true) | \(other.headline)"))

        // on this Mac: macOS's record of the responsible process can be read; a command Cool Head starts is credited to
        // whatever started Cool Head, which is why only services are read this way
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["5"]
        var live = "couldn't start a command"
        var ok = false
        if (try? p.run()) != nil {
            let r = Served.responsible(p.processIdentifier)
            ok = Served.lookup != nil && r != nil && Served.app(pid: p.processIdentifier, path: "/bin/sleep") == nil
            live = "lookup found \(Served.lookup != nil); /bin/sleep's responsible process \(r.map { "\($0)" } ?? "none"); credited to an app \(Served.app(pid: p.processIdentifier, path: "/bin/sleep") ?? "no")"
            p.terminate(); p.waitUntilExit()
        }
        review.append(("served-this-mac", ok, live))
        return review
    }
}

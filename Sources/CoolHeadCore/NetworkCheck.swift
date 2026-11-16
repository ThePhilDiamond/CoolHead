import CoreWLAN
import Darwin
import Foundation
import Network
import SystemConfiguration

/// "Test my network": tells a Mac that feels slow because of the network apart from one that's slow for other reasons.
///
/// Two halves. What the Mac can say about its connection with no permission prompt (`Setup`): the Wi-Fi signal, noise,
/// transmit rate and channel (from CoreWLAN, which leaves out the network's name unless Location Services is allowed,
/// and Cool Head never asks), whether AirDrop's radio link (AWDL) is up, which DNS server looks names up, whether a VPN
/// or proxy is in use, and which processes are moving data (from Apple's `nettop`). And, only when the person presses
/// the button, Apple's own test, `/usr/bin/networkQuality`, which measures speed and responsiveness (round trips a
/// minute under load, "RPM"). That test fills the connection for up to `testSeconds` and uses data, so it never runs
/// by itself.
///
/// Sources (research node N-020, 16 November 2026): the RPM bands are from the IETF responsiveness draft by Apple's
/// authors (draft-ietf-ippm-responsiveness-08: 300 or fewer is poor, 1,000 or more is good); the weak-signal line is
/// Apple's own: a Mac looks for a better access point once the signal drops to -75 dBm (Apple Platform Deployment,
/// "Wi-Fi roaming support in Apple devices"). Two causes are weaker and are worded as such: AWDL stutter (reported by
/// three independent sources, with no statement from Apple) and iCloud Private Relay lowering responsiveness (one
/// tester, Howard Oakley).
public enum NetworkCheck {
    /// Round trips a minute under load at or below which responsiveness is poor, and at or above which it is good.
    public static let poorRPM = 300
    public static let goodRPM = 1000
    /// The signal, in dBm, at which a Mac starts looking for a better access point.
    public static let weakSignal = -75
    /// The channels AWDL prefers ("social" channels); a router on another channel makes the radio hop away to listen.
    public static let awdlChannels: Set<Int> = [6, 44, 149]
    /// The longest the test may take. The draft aims for about ten seconds and gives 40 as an example budget.
    public static let testSeconds = 30
    /// Processes moving less than this, in bytes a second, aren't worth naming.
    public static let talkerFloor = 100_000.0

    /// What the button says it will do, before it is pressed.
    public static let explainer = "Runs Apple's network test. It uses your whole connection for up to \(testSeconds) seconds, so it runs only when you press it."
    /// How much data the test can use: about the connection's speed times the run time, so a few gigabytes on a fast
    /// line (an estimate, as in research node N-020; Apple doesn't say).
    public static let dataNote = "Uses your whole connection for up to \(testSeconds) seconds: on a fast line, a few gigabytes of data."
    /// Said before the test on a connection macOS marks as metered, or one that isn't Wi-Fi or cable (a phone, say).
    public static let meteredNote = "This looks like a phone or metered connection, where the test could use a gigabyte or more of your data allowance."

    // MARK: what the Mac can say without a prompt

    public struct WiFi: Equatable {
        public var rssi: Int            // dBm
        public var noise: Int           // dBm
        public var rate: Double         // Mbps the Mac is sending at
        public var channel: Int
        public var band: String         // "2.4 GHz", "5 GHz", "6 GHz", or "" when unknown
        public init(rssi: Int, noise: Int, rate: Double, channel: Int, band: String) {
            self.rssi = rssi; self.noise = noise; self.rate = rate; self.channel = channel; self.band = band
        }
    }

    public enum Link: Equatable { case wifi(WiFi), cable, other, none }

    /// Who looks website names up: the router, another machine on the local network, or a server on the internet
    /// (set on this Mac, or by a VPN or app).
    public enum DNS: Equatable { case router, local, internet, none }

    public struct Talker: Equatable {
        public var name: String
        public var bytesPerSecond: Double
        public var bundle: String?      // the app it belongs to, if any, for a fix that opens or pauses it
        public init(name: String, bytesPerSecond: Double, bundle: String? = nil) {
            self.name = name; self.bytesPerSecond = bytesPerSecond; self.bundle = bundle
        }
    }

    public struct Setup: Equatable {
        public var link: Link
        public var awdlOn: Bool
        public var vpn: Bool
        public var proxy: Bool
        public var autoProxy: Bool
        public var dns: DNS
        public var talkers: [Talker]
        /// macOS marks the connection as metered (a phone hotspot, Low Data Mode).
        public var metered: Bool
        public init(link: Link, awdlOn: Bool = false, vpn: Bool = false, proxy: Bool = false, autoProxy: Bool = false,
                    dns: DNS = .router, talkers: [Talker] = [], metered: Bool = false) {
            self.link = link; self.awdlOn = awdlOn; self.vpn = vpn; self.proxy = proxy; self.autoProxy = autoProxy
            self.dns = dns; self.talkers = talkers; self.metered = metered
        }
        /// Whether to warn about data before the test.
        public var mayBeMetered: Bool { metered || link == .other }
    }

    /// Reads the connection, then watches network use for about a second (so call it off the main thread).
    public static func readSetup() -> Setup {
        let store = SCDynamicStoreCreate(nil, "Cool Head" as CFString, nil, nil)
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let primary = global?["PrimaryInterface"] as? String
        let router = global?["Router"] as? String
        // CoreWLAN: signal, noise, rate and channel need no permission; ssid() and bssid() stay nil without Location
        // Services, and Cool Head never calls them
        let wifi = CWWiFiClient.shared().interface()
        var link = Link.none
        if let p = primary {
            if let w = wifi, w.interfaceName == p { link = reading(w).map(Link.wifi) ?? .other }
            // a VPN's tunnel is primary; the link under it is the Wi-Fi, if it's connected
            else if isVPN(p) { link = wifi.flatMap(reading).map(Link.wifi) ?? .other }
            else { link = p.hasPrefix("en") ? .cable : .other }
        }
        let dnsInfo = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/DNS" as CFString) as? [String: Any] }
        let proxies = store.flatMap { SCDynamicStoreCopyProxies($0) as? [String: Any] } ?? [:]
        func on(_ k: String) -> Bool { (proxies[k] as? NSNumber)?.boolValue ?? false }
        return Setup(link: link,
                     awdlOn: interfaceUp("awdl0"),
                     vpn: primary.map(isVPN) ?? false,
                     proxy: on("HTTPEnable") || on("HTTPSEnable") || on("SOCKSEnable"),
                     autoProxy: on("ProxyAutoConfigEnable") || on("ProxyAutoDiscoveryEnable"),
                     dns: dnsKind(dnsInfo?["ServerAddresses"] as? [String] ?? [], router: router),
                     talkers: talkers(),
                     metered: metered())
    }

    /// Whether macOS marks the current connection as expensive (a phone hotspot) or constrained (Low Data Mode).
    static func metered() -> Bool {
        let monitor = NWPathMonitor()
        let answer = Locked(false)
        let got = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in answer.value = path.isExpensive || path.isConstrained; got.signal() }
        monitor.start(queue: DispatchQueue(label: "coolhead.network-path"))
        _ = got.wait(timeout: .now() + 1)
        monitor.cancel()
        return answer.value
    }

    /// The Wi-Fi link's signal, noise, rate and channel, or nil when it isn't connected.
    static func reading(_ w: CWInterface) -> WiFi? {
        guard w.powerOn(), w.rssiValue() != 0, let ch = w.wlanChannel() else { return nil }
        let band = [CWChannelBand.band2GHz: "2.4 GHz", .band5GHz: "5 GHz", .band6GHz: "6 GHz"][ch.channelBand] ?? ""
        return WiFi(rssi: w.rssiValue(), noise: w.noiseMeasurement(), rate: w.transmitRate(), channel: ch.channelNumber, band: band)
    }

    /// A VPN's tunnel interface (utun for most, ipsec and ppp for older kinds).
    static func isVPN(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp"].contains { interface.hasPrefix($0) }
    }

    /// Whether a network interface is up and running, from getifaddrs (no permission needed).
    static func interfaceUp(_ name: String) -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return false }
        defer { freeifaddrs(list) }
        var p = list
        while let a = p {
            if String(cString: a.pointee.ifa_name) == name {
                let flags = Int32(a.pointee.ifa_flags)
                return flags & IFF_UP != 0 && flags & IFF_RUNNING != 0
            }
            p = a.pointee.ifa_next
        }
        return false
    }

    static func dnsKind(_ servers: [String], router: String?) -> DNS {
        guard let first = servers.first else { return .none }
        if first == router || first.hasPrefix("fe80:") { return .router }
        return isPrivate(first) ? .local : .internet
    }

    /// Private and link-local addresses: 10/8, 172.16/12, 192.168/16, 169.254/16, IPv6 fc00::/7 and fe80::/10.
    static func isPrivate(_ address: String) -> Bool {
        let a = address.lowercased()
        if a.hasPrefix("fe80:") || a.hasPrefix("fc") || a.hasPrefix("fd") { return a.contains(":") }
        let o = a.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        return o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168) || (o[0] == 169 && o[1] == 254)
    }

    /// Processes moving data over the last second, busiest first, from Apple's nettop (which any user can run). Two
    /// samples a second apart in delta mode: the second is what moved in that second.
    public static func talkers() -> [Talker] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-L", "2", "-s", "1", "-d", "-n", "-x", "-J", "bytes_in,bytes_out"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        // it takes about a second; one that hangs is stopped, so the view never waits on it
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return talkers(nettop: String(decoding: data, as: UTF8.self), mine: getpid())
    }

    /// The second sample of nettop's CSV ("name.pid,bytes_in,bytes_out,"), named the way a person knows them: the app
    /// a process belongs to, or its own name, with "macOS's" before macOS's own. Cool Head and the test itself
    /// are left out, and one app's processes are added together. A process's name can hold commas, so each row is read
    /// from the right (the byte counts are last), and a row counts only if its name matches the process with that
    /// number: a program can't pass itself off as another app.
    static func talkers(nettop: String, mine: pid_t, path: (pid_t) -> String? = Proc.path,
                        name processName: (pid_t) -> String? = { Proc.bsd($0)?.name }) -> [Talker] {
        var blocks: [[Substring]] = []
        for line in nettop.split(separator: "\n") {
            if line.hasPrefix(",") { blocks.append([]) } else if !blocks.isEmpty { blocks[blocks.count - 1].append(line) }
        }
        var totals: [String: Double] = [:]
        var bundles: [String: String] = [:]
        for row in blocks.last ?? [] {
            // "name.pid,bytes_in,bytes_out," : the last field is empty, the two before it are the bytes
            let f = row.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 4, f[f.count - 1].isEmpty else { continue }
            let label = f[..<(f.count - 3)].joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = pid_t(label[label.index(after: dot)...]) else { continue }
            let bytes = (Double(f[f.count - 3]) ?? 0) + (Double(f[f.count - 2]) ?? 0)
            let raw = String(label[..<dot])
            guard bytes > 0, bytes.isFinite, pid != mine, raw != "networkQuality",
                  let real = processName(pid), real.hasPrefix(raw) || raw.hasPrefix(real) else { continue }
            let exe = path(pid)
            let name = Evidence.appName(exe) ?? (exe.map { CaseReport.isMacOS($0) } == true ? "macOS's \(raw)" : raw)
            totals[name, default: 0] += bytes
            if let b = Evidence.bundle(exe) { bundles[name] = b }
        }
        return totals.map { Talker(name: $0.key, bytesPerSecond: $0.value, bundle: bundles[$0.key]) }.sorted { $0.bytesPerSecond > $1.bytesPerSecond }
    }

    // MARK: Apple's test, run only when pressed

    public struct Result: Equatable {
        public var download: Double      // bits a second
        public var upload: Double
        public var rpm: Int
        public init(download: Double, upload: Double, rpm: Int) { self.download = download; self.upload = upload; self.rpm = rpm }
    }

    public enum Outcome: Equatable { case done(Result), failed(String) }

    /// Runs `networkQuality` and waits for it (up to `testSeconds`, plus a little to start and finish). Cancelling the
    /// task stops the test, even if it comes just as the test starts: starting and stopping share one lock, so a
    /// cancelled test never starts and a started one is always stopped.
    public static func run() async -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-M", "\(testSeconds)", "-c"]          // -c last: it takes an optional file name
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let state = Locked((cancelled: false, started: false))
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Outcome, Never>) in
                DispatchQueue.global().async {
                    let ok: Bool? = state.with { s in
                        if s.cancelled { return nil }
                        guard (try? p.run()) != nil else { return false }
                        s.started = true
                        return true
                    }
                    guard let ok else { done.resume(returning: .failed("The test was stopped.")); return }
                    guard ok else { done.resume(returning: .failed("Apple's network test isn't on this Mac (it comes with macOS 12 and later).")); return }
                    // a test that hangs past its own limit is stopped, and reads as one that couldn't finish
                    DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(testSeconds + 15)) { if p.isRunning { p.terminate() } }
                    // read while it runs, so a full pipe can never hold it up
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    done.resume(returning: parse(data))
                }
            }
        } onCancel: {
            state.with { s in
                s.cancelled = true
                if s.started && p.isRunning { p.terminate() }
            }
        }
    }

    /// networkQuality's JSON: dl_throughput and ul_throughput in bits a second, responsiveness in RPM, and error_code
    /// when it couldn't finish.
    public static func parse(_ data: Data) -> Outcome {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed("The test stopped before it had a result.")
        }
        if j["error_code"] != nil {
            return .failed("The test couldn't reach Apple's test servers, so the connection may be down.")
        }
        guard let rpm = (j["responsiveness"] as? NSNumber)?.doubleValue, rpm.isFinite,
              let down = (j["dl_throughput"] as? NSNumber)?.doubleValue, down.isFinite else {
            return .failed("The test stopped before it had a result.")
        }
        let up = (j["ul_throughput"] as? NSNumber)?.doubleValue ?? 0
        return .done(Result(download: max(0, down), upload: up.isFinite ? max(0, up) : 0, rpm: Int(min(max(rpm, 0), 1_000_000).rounded())))
    }

    // MARK: what it says

    /// The answer at the top: how it went (0 fine, 1 worth a look, 2 the network is the problem), a few words, and what
    /// it means for someone who doesn't know what RPM is.
    public struct Verdict: Equatable {
        public var level: Int
        public var title: String
        public var meaning: String
    }

    public static func verdict(_ o: Outcome) -> Verdict {
        guard case .done(let r) = o else {
            if case .failed(let why) = o { return Verdict(level: 2, title: "The test couldn't finish", meaning: why) }
            return Verdict(level: 2, title: "", meaning: "")
        }
        if r.rpm <= poorRPM {
            return Verdict(level: 2, title: "The network is slow to respond",
                           meaning: "The Mac is fine. Things online lag while the connection is busy.")
        }
        if r.download < hdVideoMbps * 1_000_000 {
            return Verdict(level: 2, title: "The network is slow",
                           meaning: "The Mac is fine. The connection is too slow for HD video, so pages and downloads crawl.")
        }
        if r.rpm < goodRPM {
            return Verdict(level: 1, title: "The network is a little slow to respond",
                           meaning: "Fine for most things; calls and games may lag while something else uses the connection.")
        }
        return Verdict(level: 0, title: "The network is fine",
                       meaning: "If the Mac feels slow, the cause is on the Mac, not the network.")
    }

    /// The download speed HD video needs (Netflix, 1080p: 5 Mbps).
    static let hdVideoMbps = 5.0

    /// Everyday tasks and the speed each needs, from the people who run them: the FCC's Broadband Speed Guide (web and
    /// email 1 Mbps; online multiplayer games 4 Mbps), Netflix (HD 1080p 5 Mbps, 4K 15 Mbps) and Zoom (1080p video calls
    /// 3.0 Mbps down and 3.8 up). Calls and games also need a responsive connection: speed alone doesn't stop the lag.
    public struct Task: Equatable {
        public let name: String
        public let symbol: String
        public let down: Double     // Mbps
        public let up: Double
        public let needsResponsive: Bool
    }
    public static let tasks: [Task] = [
        Task(name: "Web", symbol: "globe", down: 1, up: 0, needsResponsive: false),
        Task(name: "HD video", symbol: "play.rectangle", down: hdVideoMbps, up: 0, needsResponsive: false),
        Task(name: "4K video", symbol: "4k.tv", down: 15, up: 0, needsResponsive: false),
        Task(name: "Video calls", symbol: "video", down: 3.0, up: 3.8, needsResponsive: true),
        Task(name: "Games", symbol: "gamecontroller", down: 4, up: 0, needsResponsive: true),
    ]

    /// How well a task will go: fine; laggy (fast enough, but slow to respond while busy); or too slow.
    public enum Fit: Equatable { case fine, laggy, tooSlow }

    public static func fit(_ t: Task, _ r: Result) -> Fit {
        if r.download < t.down * 1_000_000 || r.upload < t.up * 1_000_000 { return .tooSlow }
        if t.needsResponsive && r.rpm <= poorRPM { return .laggy }
        return .fine
    }

    /// The wait for a reply while the connection is busy, in milliseconds: RPM is round trips a minute, so 60,000 / RPM.
    public static func delay(_ r: Result) -> Int { Int((60_000 / Double(max(r.rpm, 1))).rounded()) }

    /// What to do about it, only when the test found a problem and only for causes that apply, most useful first; each
    /// is an option the person carries out, with Cool Head taking them to the place. Nothing here ever turns off a VPN
    /// or security software itself. With nothing wrong, there is nothing to offer (an option to fix a fine network would
    /// do harm).
    public static func fixes(_ r: Result, _ s: Setup) -> [Fix] {
        guard verdict(.done(r)).level > 0 else { return [] }
        var out: [Fix] = []
        // 1. something on this Mac filling the connection
        if let t = s.talkers.first(where: { $0.bytesPerSecond >= 1_000_000 }), let b = t.bundle {
            if let sync = SyncApps.app(bundle: b) {
                out.append(Fix(id: "net-pause-sync", title: "Pause \(sync) for a while",
                               consequence: "It was using \(rate(t.bytesPerSecond)). Syncing waits until you resume; nothing is lost.",
                               kind: .pauseSync(b, sync)))
            } else {
                out.append(.openApp("net-busy-app", "Pause what \(t.name) is downloading", bundle: b,
                                    steps: "It was using \(rate(t.bytesPerSecond)). Pause or finish its download, then test again."))
            }
        }
        // 2. a weak Wi-Fi signal
        if case .wifi(let w) = s.link, w.rssi <= weakSignal {
            out.append(.guide("net-signal", "Get a stronger Wi-Fi signal", "The signal is weak (\(w.rssi) dBm).",
                              steps: ["Move closer to the router, or away from walls, metal and microwaves.",
                                      "Use a cable if you can: it's steadier than Wi-Fi.",
                                      "Test again."]))
            out.append(.openApp("net-diagnostics", "Ask Apple's Wireless Diagnostics", bundle: wirelessDiagnostics,
                                steps: "It checks your Wi-Fi and suggests fixes, and doesn't change any settings."))
        }
        // 3. slow to respond under load: the router's queue (bufferbloat); the fix is its Smart Queue setting
        if r.rpm < goodRPM {
            out.append(.guide("net-smart-queue", "Turn on your router's Smart Queue",
                              "Keeps the connection quick to respond while it's busy; top speed may drop a little.",
                              steps: ["Open your router's settings (its app, or the address on its label).",
                                      "Look for Smart Queue, SQM, QoS or Bufferbloat, and turn it on.",
                                      "Test again."]))
        }
        // 4. AirDrop's radio link hopping channels (several reports, no Apple statement)
        if r.rpm < goodRPM, case .wifi(let w) = s.link, s.awdlOn, !awdlChannels.contains(w.channel) {
            out.append(Fix(id: "net-airdrop", title: "Set AirDrop to No One for a while",
                           consequence: "Stopped regular stutters for some people; Apple hasn't said why. Others can't AirDrop to you until you set it back.",
                           kind: .openPage(systemSettings, "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")))
        }
        // 5. iCloud Private Relay (one tester), a VPN, a proxy: test without them; Cool Head never turns them off
        if r.rpm < goodRPM {
            out.append(Fix(id: "net-private-relay", title: "Test with Private Relay off",
                           consequence: "If it's on (Apple Account ▸ iCloud ▸ Private Relay), turn it off and test again. One tester found it cut responsiveness on two of three Macs.",
                           kind: .openPage(systemSettings, "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")))
        }
        if s.vpn {
            out.append(.guide("net-vpn", "Test without the VPN", "Only if your work allows it.",
                              steps: ["Disconnect the VPN from its menu bar icon.", "Test again.", "Reconnect it."]))
        }
        if s.proxy || s.autoProxy {
            out.append(Fix(id: "net-proxy", title: "Check the proxy setting",
                           consequence: "In Network ▸ Details ▸ Proxies. Turn it off only if you know you don't need it.",
                           kind: .openPage(systemSettings, "x-apple.systempreferences:com.apple.Network-Settings.extension")))
        }
        // 6. slow, with a good signal or a cable: the line itself
        if r.download < hdVideoMbps * 1_000_000 {
            out.append(.guide("net-provider", "Compare with what you pay for", "Your plan's speed is on your bill or your provider's site.",
                              steps: ["Restart the router (everyone's connection drops for a minute or two).", "Test again.",
                                      "Still far below your plan? Call your provider."]))
        }
        if !out.isEmpty { out[0].recommended = true }
        return out
    }

    /// What the activity log says when a fix is pressed: its fixed id only. A fix's title can name an app, and the log
    /// can end up in a public Report a problem issue, so names never go into it.
    public static func logLine(_ f: Fix) -> String { "Test my network: \(f.id) pressed" }

    static let systemSettings = "/System/Applications/System Settings.app"
    public static let wirelessDiagnostics = "/System/Library/CoreServices/Applications/Wireless Diagnostics.app"

    /// The facts behind the verdict, one plain line each; `result` is nil before the test has been run.
    public static func lines(_ result: Result?, _ s: Setup) -> [String] {
        var out: [String] = []
        if let r = result {
            out.append("Speed: \(mbps(r.download)) down, \(mbps(r.upload)) up.")
            out.append("Responsiveness: \(grouped(r.rpm)) round trips a minute while busy, a wait of about \(grouped(delay(r))) ms each (\(poorRPM) or fewer is poor, \(grouped(goodRPM)) or more is good).")
        }
        switch s.link {
        case .wifi(let w):
            if w.rssi <= weakSignal {
                out.append("Wi-Fi signal is weak: \(w.rssi) dBm, against \(w.noise) dBm of background noise. A Mac looks for a better access point once it drops to \(weakSignal), so moving closer to the router may help.")
            } else {
                out.append("Wi-Fi signal is fine: \(w.rssi) dBm, against \(w.noise) dBm of background noise (weak is \(weakSignal) or lower).")
            }
            out.append("Wi-Fi is sending at up to \(grouped(Int(w.rate.rounded()))) Mbps on channel \(w.channel)" + (w.band.isEmpty ? "." : " (\(w.band))."))
            if s.awdlOn && !awdlChannels.contains(w.channel) {
                out.append("The radio link AirDrop and Continuity use is on, and it listens on channel 6, 44 or 149 rather than your router's \(w.channel). Several people report this causes short, regular stutters, though Apple hasn't said so; setting AirDrop to No One stopped it for some.")
            }
        case .cable: out.append("Connected by cable.")
        case .other: out.append("Connected, but not by Wi-Fi or cable (perhaps through a phone).")
        case .none: out.append("Not connected to a network.")
        }
        if s.vpn { out.append("A VPN is carrying your traffic, which adds a stop on the way to every site.") }
        if s.proxy { out.append("A proxy is set in Network settings, so web traffic goes through it first.") }
        if s.autoProxy { out.append("Automatic proxy setup is on in Network settings, so web traffic may go through a proxy first.") }
        switch s.dns {
        case .router: out.append("Website names are looked up by your router.")
        case .local: out.append("Website names are looked up by another machine on your network, not your router.")
        case .internet: out.append("Website names are looked up by a server on the internet, set on this Mac or by a VPN or app.")
        case .none: out.append("No server is set to look up website names, so sites by name won't load.")
        }
        let busy = s.talkers.filter { $0.bytesPerSecond >= talkerFloor }.prefix(3)
        out.append(busy.isEmpty ? "Nothing else was using much of the network\(result == nil ? "" : " before the test")."
                   : "Using the network\(result == nil ? "" : " before the test"): " + busy.map { "\($0.name) (\(rate($0.bytesPerSecond)))" }.joined(separator: ", ") + ".")
        return out
    }

    /// Bits a second as Mbps: "240 Mbps", "4.5 Mbps", "under 1 Mbps".
    public static func mbps(_ bits: Double) -> String {
        let m = bits / 1_000_000
        if m < 1 { return "under 1 Mbps" }
        return m < 10 ? String(format: "%.1f Mbps", m) : "\(grouped(Int(m.rounded()))) Mbps"
    }

    /// 1240 as "1,240", whatever the Mac's region, so the wording is the same everywhere (US English, like every card).
    public static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Bytes a second, in words: "2.1 MB a second", "300 KB a second".
    public static func rate(_ bytes: Double) -> String {
        bytes >= 1_000_000 ? String(format: "%.1f MB a second", bytes / 1_000_000) : "\(Int((bytes / 1000).rounded())) KB a second"
    }
}

/// A value shared between threads, behind a lock.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    @discardableResult func with<R>(_ body: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&stored) }
}

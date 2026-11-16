import CoreWLAN
import Darwin
import Foundation
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
    public static let explainer = "Runs Apple's network test. It uses your whole connection for up to \(testSeconds) seconds, and some data, so it runs only when you press it."

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
        public init(name: String, bytesPerSecond: Double) { self.name = name; self.bytesPerSecond = bytesPerSecond }
    }

    public struct Setup: Equatable {
        public var link: Link
        public var awdlOn: Bool
        public var vpn: Bool
        public var proxy: Bool
        public var autoProxy: Bool
        public var dns: DNS
        public var talkers: [Talker]
        public init(link: Link, awdlOn: Bool = false, vpn: Bool = false, proxy: Bool = false, autoProxy: Bool = false,
                    dns: DNS = .router, talkers: [Talker] = []) {
            self.link = link; self.awdlOn = awdlOn; self.vpn = vpn; self.proxy = proxy; self.autoProxy = autoProxy
            self.dns = dns; self.talkers = talkers
        }
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
                     talkers: talkers())
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
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return talkers(nettop: String(decoding: data, as: UTF8.self), mine: getpid())
    }

    /// The second sample of nettop's CSV ("name.pid,bytes_in,bytes_out,"), named the way a person knows them: the app
    /// a process belongs to, or its own name, with "macOS's" before macOS's own. Cool Head and the test itself
    /// are left out, and one app's processes are added together.
    static func talkers(nettop: String, mine: pid_t, path: (pid_t) -> String? = Proc.path) -> [Talker] {
        var blocks: [[Substring]] = []
        for line in nettop.split(separator: "\n") {
            if line.hasPrefix(",") { blocks.append([]) } else if !blocks.isEmpty { blocks[blocks.count - 1].append(line) }
        }
        var totals: [String: Double] = [:]
        for row in blocks.last ?? [] {
            let f = row.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, let dot = f[0].lastIndex(of: "."), let pid = pid_t(f[0][f[0].index(after: dot)...]) else { continue }
            let bytes = (Double(f[1]) ?? 0) + (Double(f[2]) ?? 0)
            let raw = String(f[0][..<dot])
            guard bytes > 0, pid != mine, raw != "networkQuality" else { continue }
            let exe = path(pid)
            let name = Evidence.appName(exe) ?? (exe.map { CaseReport.isMacOS($0) } == true ? "macOS's \(raw)" : raw)
            totals[name, default: 0] += bytes
        }
        return totals.map { Talker(name: $0.key, bytesPerSecond: $0.value) }.sorted { $0.bytesPerSecond > $1.bytesPerSecond }
    }

    // MARK: Apple's test, run only when pressed

    public struct Result: Equatable {
        public var download: Double      // bits a second
        public var upload: Double
        public var rpm: Int
        public init(download: Double, upload: Double, rpm: Int) { self.download = download; self.upload = upload; self.rpm = rpm }
    }

    public enum Outcome: Equatable { case done(Result), failed(String) }

    /// Runs `networkQuality -c` and waits for it (up to `testSeconds`, plus a little to start and finish). Cancelling
    /// the task stops the test.
    public static func run() async -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-c", "-M", "\(testSeconds)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Outcome, Never>) in
                p.terminationHandler = { _ in
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    done.resume(returning: parse(data))
                }
                do { try p.run() } catch {
                    p.terminationHandler = nil
                    done.resume(returning: .failed("Apple's network test isn't on this Mac (it comes with macOS 12 and later)."))
                    return
                }
                // a test that hangs past its own limit is stopped, and reads as one that couldn't finish
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(testSeconds + 15)) { if p.isRunning { p.terminate() } }
            }
        } onCancel: {
            if p.isRunning { p.terminate() }
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
        guard let rpm = (j["responsiveness"] as? NSNumber)?.doubleValue,
              let down = (j["dl_throughput"] as? NSNumber)?.doubleValue else {
            return .failed("The test stopped before it had a result.")
        }
        return .done(Result(download: down, upload: (j["ul_throughput"] as? NSNumber)?.doubleValue ?? 0, rpm: Int(rpm.rounded())))
    }

    // MARK: what it says

    /// One sentence: is the network what's slow?
    public static func verdict(_ o: Outcome) -> String {
        switch o {
        case .failed(let why): return why
        case .done(let r) where r.rpm <= poorRPM:
            return "Your connection is slow to respond when it's busy, so things online will feel slow even though the Mac is fine."
        case .done(let r) where r.rpm < goodRPM:
            return "Your connection responds fairly well; calls and busy pages may lag a little while it's in use."
        case .done:
            return "Your connection is fine, so if the Mac feels slow, the network is unlikely to be the cause."
        }
    }

    /// The facts behind the verdict, one plain line each; `result` is nil before the test has been run.
    public static func lines(_ result: Result?, _ s: Setup) -> [String] {
        var out: [String] = []
        if let r = result {
            out.append("Speed: \(mbps(r.download)) down, \(mbps(r.upload)) up.")
            out.append("Responsiveness: \(grouped(r.rpm)) round trips a minute while busy (\(poorRPM) or fewer is poor, \(grouped(goodRPM)) or more is good).")
        }
        switch s.link {
        case .wifi(let w):
            if w.rssi <= weakSignal {
                out.append("Wi-Fi signal is weak: \(w.rssi) dBm, against \(w.noise) dBm of background noise. A Mac looks for a better access point once it drops to \(weakSignal), so moving closer to the router may help.")
            } else {
                out.append("Wi-Fi signal is fine: \(w.rssi) dBm, against \(w.noise) dBm of background noise (weak is \(weakSignal) or lower).")
            }
            out.append("Wi-Fi is sending at up to \(Int(w.rate.rounded())) Mbps on channel \(w.channel)" + (w.band.isEmpty ? "." : " (\(w.band))."))
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
        if let r = result, r.rpm < goodRPM {
            out.append("If iCloud Private Relay is on, try the test again with it off: one tester found it cut responsiveness sharply on two of three Macs.")
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
    static func grouped(_ n: Int) -> String {
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

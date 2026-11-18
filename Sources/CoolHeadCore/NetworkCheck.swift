import CoreServices
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

    /// Who set the server that looks website names up: the network the Mac joined (the router hands it out), someone
    /// on this Mac (Network settings ▸ Details ▸ DNS), or the VPN.
    public enum DNSSource: Equatable { case network, thisMac, vpn }

    /// A connected VPN, and what it carries. Read on the Mac only: macOS's own list of VPNs (as `scutil --nc list`
    /// shows it) and which way the Mac would send traffic to a public address (a routing lookup that sends nothing).
    public struct VPN: Equatable {
        /// What goes through it: everything; everything but IPv6 (so some sites still see the person's own address);
        /// or only traffic for particular addresses, such as a work or home network, with websites going directly.
        public enum Carries: Equatable { case everything, notIPv6, someAddresses }
        public var name: String?        // the VPN app's name, when macOS knows it
        public var carries: Carries
        /// Website names are looked up through it too (when they aren't, the internet provider still sees which sites).
        public var lookups: Bool
        public init(name: String? = nil, carries: Carries = .everything, lookups: Bool = true) {
            self.name = name; self.carries = carries; self.lookups = lookups
        }
        /// Websites' traffic goes through it (IPv4 at least).
        public var carriesWebsites: Bool { carries != .someAddresses }
        /// "WireGuard", or "The VPN" when the app isn't known.
        public var called: String { name ?? "The VPN" }
    }

    public struct Setup: Equatable {
        public var link: Link
        public var awdlOn: Bool
        public var vpn: VPN?
        public var proxy: Bool
        public var autoProxy: Bool
        public var dns: DNS
        /// The name of a well-known public lookup service ("Cloudflare"), when that's the one in use.
        public var dnsName: String?
        public var dnsSetBy: DNSSource
        /// The router's address on the local network, to say where its settings page is.
        public var router: String?
        /// The Mac gave itself an address (169.254.x.x) because the router didn't hand one out, so it can't go online.
        public var selfAssigned: Bool
        /// The Wi-Fi or cable interface under any VPN ("en0"), for the check that goes around the VPN.
        public var physical: String?
        public var talkers: [Talker]
        /// macOS marks the connection as metered (a phone hotspot, Low Data Mode).
        public var metered: Bool
        public init(link: Link, awdlOn: Bool = false, vpn: VPN? = nil, proxy: Bool = false, autoProxy: Bool = false,
                    dns: DNS = .router, dnsName: String? = nil, dnsSetBy: DNSSource = .network, router: String? = nil,
                    selfAssigned: Bool = false, physical: String? = nil, talkers: [Talker] = [], metered: Bool = false) {
            self.link = link; self.awdlOn = awdlOn; self.vpn = vpn; self.proxy = proxy; self.autoProxy = autoProxy
            self.dns = dns; self.dnsName = dnsName; self.dnsSetBy = dnsSetBy; self.router = router
            self.selfAssigned = selfAssigned; self.physical = physical; self.talkers = talkers; self.metered = metered
        }
        /// Whether to warn about data before the test.
        public var mayBeMetered: Bool { metered || link == .other }
    }

    /// Reads the connection, then watches network use for about a second (so call it off the main thread).
    public static func readSetup() -> Setup {
        let store = SCDynamicStoreCreate(nil, "Cool Head" as CFString, nil, nil)
        func value(_ key: String) -> [String: Any]? { store.flatMap { SCDynamicStoreCopyValue($0, key as CFString) as? [String: Any] } }
        let global = value("State:/Network/Global/IPv4")
        let primary = global?["PrimaryInterface"] as? String
        let primaryService = global?["PrimaryService"] as? String
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
        let servers = value("State:/Network/Global/DNS")?["ServerAddresses"] as? [String] ?? []
        let proxies = store.flatMap { SCDynamicStoreCopyProxies($0) as? [String: Any] } ?? [:]
        func on(_ k: String) -> Bool { (proxies[k] as? NSNumber)?.boolValue ?? false }

        // a connected VPN from macOS's own list, and the tunnel it uses; or, for one that isn't in the list, a tunnel
        // that is the Mac's main connection (how this was read before)
        let tunnel = connectedVPN()
        let tunnelInterface = tunnel.flatMap { t in
            ["IPv4", "IPv6"].lazy.compactMap { value("State:/Network/Service/\(t.service)/\($0)")?["InterfaceName"] as? String }.first
        } ?? primary.flatMap { isVPN($0) ? $0 : nil }
        var vpn: VPN?
        if let i = tunnelInterface {
            // which way traffic to a public address would go: a lookup in the routing table, nothing is sent
            let v4 = routeInterface(cloudflareV4), v6 = routeInterface(cloudflareV6)
            let carries: VPN.Carries = v4 != i ? .someAddresses : (v6 == nil || v6 == i) ? .everything : .notIPv6
            vpn = VPN(name: tunnel?.name, carries: carries, lookups: servers.first.flatMap(routeInterface) == i)
        }
        let first = servers.first
        let setByHand = primaryService.flatMap { value("Setup:/Network/Service/\($0)/DNS")?["ServerAddresses"] as? [String] } ?? []
        let setByVPN = tunnel.flatMap { value("State:/Network/Service/\($0.service)/DNS")?["ServerAddresses"] as? [String] } ?? []
        let source: DNSSource = first.map { setByVPN.contains($0) } == true ? .vpn : first.map { setByHand.contains($0) } == true ? .thisMac : .network
        let address = primaryService.flatMap { value("State:/Network/Service/\($0)/IPv4")?["Addresses"] as? [String] }?.first
        return Setup(link: link,
                     awdlOn: interfaceUp("awdl0"),
                     vpn: vpn,
                     proxy: on("HTTPEnable") || on("HTTPSEnable") || on("SOCKSEnable"),
                     autoProxy: on("ProxyAutoConfigEnable") || on("ProxyAutoDiscoveryEnable"),
                     dns: dnsKind(servers, router: router),
                     dnsName: first.flatMap(resolverName),
                     dnsSetBy: source,
                     router: router.flatMap { isPrivate($0) && !$0.contains(":") ? $0 : nil },
                     selfAssigned: address?.hasPrefix("169.254.") == true,
                     physical: primary.flatMap { isVPN($0) ? nil : $0 } ?? (wifi.flatMap(reading) != nil ? wifi?.interfaceName : nil),
                     talkers: talkers(),
                     metered: metered())
    }

    /// Cloudflare's public addresses, used only to ask the routing table which way internet traffic would go (nothing is
    /// sent to them for that).
    static let cloudflareV4 = "1.1.1.1", cloudflareV6 = "2606:4700:4700::1111"

    /// The first connected VPN in macOS's list of network services (the list System Settings ▸ VPN shows), with its
    /// app's name when it's one installed from an app ("VPN" services carry the app's bundle id), from
    /// SystemConfiguration, as `scutil --nc list` reads it; no permission needed.
    static func connectedVPN() -> (service: String, name: String?)? {
        guard let prefs = SCPreferencesCreate(nil, "Cool Head" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return nil }
        for s in services {
            guard let i = SCNetworkServiceGetInterface(s), let type = SCNetworkInterfaceGetInterfaceType(i) as String?,
                  ["VPN", "IPSec", "PPP"].contains(type), let id = SCNetworkServiceGetServiceID(s) as String?,
                  let c = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil),
                  SCNetworkConnectionGetStatus(c) == .connected else { continue }
            // a phone or modem dialling out is a PPP service too, but not a VPN: only PPP over L2TP or PPTP is
            let inner = SCNetworkInterfaceGetInterface(i).flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
            if type == "PPP", !["L2TP", "PPTP"].contains(inner ?? "") { continue }
            return (id, type == "VPN" ? inner.flatMap(appName) : nil)
        }
        return nil
    }

    /// An app's name from its bundle id ("com.wireguard.macos" is "WireGuard"), from Launch Services.
    static func appName(_ bundle: String) -> String? {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundle as CFString, nil)?.takeRetainedValue() as? [URL] else { return nil }
        return urls.first?.deletingPathExtension().lastPathComponent
    }

    /// The interface the Mac would send traffic to an address through, from the routing table: a UDP socket "connected"
    /// to the address picks a route and a local address, and sends nothing (UDP has no handshake). Nil with no route.
    static func routeInterface(_ address: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        hints.ai_socktype = SOCK_DGRAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, "53", &hints, &found) == 0, let ai = found else { return nil }
        defer { freeaddrinfo(found) }
        let fd = socket(ai.pointee.ai_family, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 else { return nil }
        var local = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let got = withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard got == 0 else { return nil }
        let mine = withUnsafePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { numeric($0) } }
        // the interface that holds that local address
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var p = list
        while let a = p {
            if let sa = a.pointee.ifa_addr, mine != nil, numeric(sa) == mine { return String(cString: a.pointee.ifa_name) }
            p = a.pointee.ifa_next
        }
        return nil
    }

    /// An IPv4 or IPv6 socket address as text, or nil for any other kind.
    static func numeric(_ sa: UnsafePointer<sockaddr>) -> String? {
        let family = Int32(sa.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else { return nil }
        let length = socklen_t(family == AF_INET6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sa, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    /// Well-known public services that look website names up, by the addresses they publish.
    static let resolvers: [(name: String, addresses: [String])] = [
        ("Cloudflare", ["1.1.1.1", "1.0.0.1", "1.1.1.2", "1.0.0.2", "1.1.1.3", "1.0.0.3", "2606:4700:4700::"]),
        ("Google", ["8.8.8.8", "8.8.4.4", "2001:4860:4860::"]),
        ("Quad9", ["9.9.9.9", "149.112.112.112", "9.9.9.10", "149.112.112.10", "9.9.9.11", "2620:fe::"]),
        ("OpenDNS", ["208.67.222.222", "208.67.220.220", "208.67.222.123", "208.67.220.123", "2620:119:35::", "2620:119:53::"]),
        ("AdGuard", ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]),
        ("NextDNS", ["45.90.28.", "45.90.30.", "2a07:a8c0:", "2a07:a8c1:"]),
    ]

    /// The public service an address belongs to, or nil. An IPv4 address must match whole unless the list gives a
    /// prefix (ending in "."); an IPv6 address matches on the prefix the service publishes.
    static func resolverName(_ address: String) -> String? {
        let a = address.lowercased()
        return resolvers.first { r in
            r.addresses.contains { p in p.hasSuffix(".") || p.contains(":") ? a.hasPrefix(p) : a == p }
        }?.name
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

    // MARK: where websites see you, checked only when pressed

    /// Cloudflare's trace page: a few hundred bytes of plain text that include the address the request came from and
    /// that address's country. It is the only request this check makes; Apple has no such page.
    public static let tracePage = "https://www.cloudflare.com/cdn-cgi/trace"

    /// What a website saw: the address a request came from (kept in memory only, never shown or logged) and its
    /// country, as a two-letter code.
    public struct Seen: Equatable {
        public var address: String
        public var country: String
        public init(address: String, country: String) { self.address = address; self.country = country }
    }

    /// The check's answer. `around` is the same request sent over the Wi-Fi or cable directly, made only when a VPN
    /// carries websites' traffic: the same address means the VPN isn't hiding it; a refusal means the VPN blocks
    /// traffic that tries to go around it.
    public enum Around: Equatable { case notAsked, same, other(Seen), blocked }
    public enum Where: Equatable { case seen(Seen, around: Around), failed }

    /// What the test also does, said before it is run.
    public static func whereNote(_ s: Setup) -> String {
        s.vpn?.carriesWebsites == true
            ? "The test also asks Cloudflare, through the VPN and around it, which country websites see you in."
            : "The test also asks Cloudflare which country websites see you in."
    }

    /// The Privacy section's one sentence: before the test, what the VPN does and what the test will ask; after it,
    /// where websites see you, with any gap in the VPN after it.
    public static func privacySentence(_ s: Setup, _ w: Where?) -> String {
        let vpn = vpnSaid(s.vpn)
        guard let w else { return vpn.detail + " " + whereNote(s) }
        return whereSaid(w, s.vpn).detail + (vpn.level == 1 ? " " + vpn.detail : "")
    }

    /// Asks Cloudflare's trace page where the Mac's traffic comes from, through `/usr/bin/curl` by its full path with
    /// fixed arguments, then, when a VPN carries websites' traffic, asks again bound to the Wi-Fi or cable. Takes up to
    /// about 16 seconds, so call it off the main thread.
    public static func whereSeen(_ s: Setup) -> Where {
        // with a VPN, both requests use IPv4, so the two addresses compare like with like (a VPN that lets IPv6 go
        // around it is told apart on the Mac, without a request)
        let compare = s.vpn?.carriesWebsites == true ? s.physical : nil
        guard let through = fetchTrace(interface: nil, ipv4: compare != nil).flatMap(trace) else { return .failed }
        guard let physical = compare else { return .seen(through, around: .notAsked) }
        guard let direct = fetchTrace(interface: physical, ipv4: true) else { return .seen(through, around: .blocked) }
        guard let seen = trace(direct) else { return .seen(through, around: .blocked) }
        return .seen(through, around: seen.address == through.address ? .same : .other(seen))
    }

    /// The trace page's text, or nil when it couldn't be fetched (in 8 seconds, over HTTPS only).
    static func fetchTrace(interface: String?, ipv4: Bool) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["--silent", "--max-time", "8", "--proto", "=https", "--max-filesize", "10000"]
            + (ipv4 ? ["--ipv4"] : []) + (interface.map { ["--interface", $0] } ?? []) + [tracePage]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data.prefix(10_000), as: UTF8.self) : nil
    }

    /// The trace page's "ip=" and "loc=" lines; nil without both, or with a country that isn't two letters or digits.
    public static func trace(_ text: String) -> Seen? {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { fields[String(kv[0])] = String(kv[1]).trimmingCharacters(in: .whitespaces) }
        }
        guard let ip = fields["ip"], !ip.isEmpty, let loc = fields["loc"]?.uppercased(), loc.count == 2,
              loc.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return Seen(address: ip, country: loc)
    }

    /// A country's name from its two-letter code, in US English ("NL" is "Netherlands"); Cloudflare's "T1" is Tor.
    public static func country(_ code: String) -> String {
        if code == "T1" { return "the Tor network" }
        return Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? "an unknown place"
    }

    /// The answer in a few words and one plain sentence, with how it went (0 fine, 1 worth a look, 2 couldn't tell).
    public static func whereSaid(_ w: Where, _ vpn: VPN?) -> (level: Int, value: String, detail: String) {
        guard case .seen(let s, let around) = w else {
            return (2, "Unknown", "Cloudflare didn't answer, so the connection may be down.")
        }
        let place = country(s.country)
        guard let v = vpn else { return (0, place, "Your own address: no VPN is on.") }
        guard v.carriesWebsites else { return (1, place, "Your own address: \(v.called) doesn't carry websites' traffic.") }
        switch around {
        case .same: return (1, place, "Your own address: \(v.called) isn't hiding it.")
        case .other(let o) where o.country == s.country: return (0, place, "Through \(v.called), from a different address in the same country.")
        case .other(let o): return (0, place, "Through \(v.called); without it, \(country(o.country)).")
        case .blocked: return (0, place, "Through \(v.called), which stops traffic going around it.")
        case .notAsked: return (0, place, "Through \(v.called).")
        }
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

    /// The result in one plain sentence: what the connection is fine for, then only what isn't and what it affects, at
    /// most two things (Phil, 16 November 2026: "only share key info "everything is good except..."").
    public static func summary(_ r: Result, _ link: Link) -> String {
        var problems: [String] = []
        if case .wifi(let w) = link, w.rssi <= weakSignal { problems.append("the Wi-Fi signal is weak") }
        if r.download < hdVideoMbps * 1_000_000 { problems.append("downloads are slow") }
        if r.upload < 3.8e6 { problems.append("uploads are slow, so video calls may break up") }
        if r.rpm <= poorRPM { problems.append("the delay is long, so calls and games may lag") }
        else if r.rpm < goodRPM { problems.append("the delay grows while the connection is busy") }
        if problems.isEmpty { return "Fast enough for everything, from 4K video to calls and games." }
        let phrase = ["Web": "browsing", "HD video": "HD video", "4K video": "4K video", "Video calls": "video calls", "Games": "games"]
        let fine = tasks.filter { fit($0, r) == .fine }.compactMap { phrase[$0.name] }
        let issues = problems.prefix(2).joined(separator: ", and ")
        guard !fine.isEmpty else { return issues.prefix(1).uppercased() + issues.dropFirst() + "." }
        let good = fine.count == 1 ? fine[0] : fine.dropLast().joined(separator: ", ") + " and " + fine.last!
        return "Fine for \(good), but \(issues)."
    }

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
                              steps: [s.router.map { "Open your router's settings: its app, or http://\($0) in a browser." }
                                          ?? "Open your router's settings (its app, or the address on its label).",
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
                           consequence: "If it's on (\(Fmt.path("Apple Account", "iCloud", "Private Relay"))), turn it off and test again. One tester found it cut responsiveness on two of three Macs.",
                           kind: .openPage(systemSettings, "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")))
        }
        if s.vpn?.carriesWebsites == true {
            out.append(.guide("net-vpn", "Test without the VPN", "Only if your work allows it.",
                              steps: ["Disconnect the VPN from its menu bar icon.", "Test again.", "Reconnect it."]))
        }
        if s.proxy || s.autoProxy {
            out.append(Fix(id: "net-proxy", title: "Check the proxy setting",
                           consequence: "In \(Fmt.path("Network", "Details", "Proxies")). Turn it off only if you know you don't need it.",
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
        if s.selfAssigned {
            out.append("The router didn't give this Mac an address, so it can't go online. Turn Wi-Fi off and on, or restart the router.")
        }
        if let v = s.vpn { out.append(vpnLine(v)) }
        if s.proxy { out.append("A proxy is set in Network settings, so web traffic goes through it first.") }
        if s.autoProxy { out.append("Automatic proxy setup is on in Network settings, so web traffic may go through a proxy first.") }
        out.append(dnsLine(s))
        let busy = s.talkers.filter { $0.bytesPerSecond >= talkerFloor }.prefix(3)
        out.append(busy.isEmpty ? "Nothing else was using much of the network\(result == nil ? "" : " before the test")."
                   : "Using the network\(result == nil ? "" : " before the test"): " + busy.map { "\($0.name) (\(rate($0.bytesPerSecond)))" }.joined(separator: ", ") + ".")
        return out
    }

    /// What a VPN carries, in a sentence with what to do about any gap.
    public static func vpnLine(_ v: VPN) -> String {
        switch v.carries {
        case .someAddresses:
            return "\(v.called) is on, but carries only traffic for a few addresses (a work or home network, say); websites go directly and see your own address. If you meant it to hide your address, look in its settings for an option to send all traffic through it."
        case .notIPv6:
            return "\(v.called) is on, but newer IPv6 traffic goes around it, so some websites still see your own address. Look in its settings for an option to block that, often called leak protection."
        case .everything where !v.lookups:
            return "\(v.called) carries all your traffic, but website names are looked up outside it, so your internet provider can still see which sites you visit. Look in its settings for DNS leak protection."
        case .everything:
            return "\(v.called) carries all your traffic, including looking up website names, which adds a stop on the way to every site."
        }
    }

    /// Who looks website names up, and who set that.
    public static func dnsLine(_ s: Setup) -> String {
        let who: String = {
            switch s.dns {
            case .router: return "your router"
            case .local: return "another machine on your network, not your router"
            case .internet: return s.dnsName ?? "a server on the internet"
            case .none: return ""
            }
        }()
        guard s.dns != .none else { return "No server is set to look up website names, so sites by name won't load." }
        switch s.dnsSetBy {
        case .network: return "Website names are looked up by \(who)" + (s.dns == .router ? "." : ", set by the network you joined.")
        case .thisMac: return "Website names are looked up by \(who), set by hand on this Mac (Network settings ▸ Details ▸ DNS). If sites stop loading on another network, this is the first thing to remove."
        case .vpn: return "Website names are looked up by \(who), set by \(s.vpn?.name ?? "your VPN")."
        }
    }

    /// The VPN in a word or two and a short sentence, for the panel, with how it went (0 good, 1 a gap, -1 neutral).
    public static func vpnSaid(_ v: VPN?) -> (level: Int, value: String, detail: String) {
        guard let v else { return (-1, "Off", "No VPN is connected.") }
        let name = v.name ?? "On"
        switch v.carries {
        case .someAddresses: return (-1, name, "It carries only a few addresses; websites go directly.")
        case .notIPv6: return (1, name, "Its IPv6 traffic goes around it, so some sites see your own address.")
        case .everything where !v.lookups: return (1, name, "Site names are looked up outside it, so your provider sees which sites you visit.")
        case .everything: return (0, name, "All your traffic goes through it.")
        }
    }

    /// Who looks website names up, in a word or two and a short sentence, for the panel.
    public static func dnsSaid(_ s: Setup) -> (value: String, detail: String) {
        let value: String = {
            switch s.dns {
            case .router: return "Router"
            case .local: return "Local server"
            case .internet: return s.dnsName ?? "Internet"
            case .none: return "None"
            }
        }()
        if s.dns == .none { return (value, "Sites won't load by name.") }
        switch s.dnsSetBy {
        case .network: return (value, s.dns == .router ? "Set by your network, the usual setup." : "Set by the network you joined.")
        case .thisMac: return (value, "Set by hand on this Mac.")
        case .vpn: return (value, "Set by \(s.vpn?.name ?? "the VPN").")
        }
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

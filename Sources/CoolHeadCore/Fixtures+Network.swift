import Foundation

/// Checks for "Test my network" (see NetworkCheck.swift). Apple's test itself is never run here: it fills the connection
/// and uses data, so it runs only when a person presses the button.
extension Fixture {
    static func networkChecks(_ now: Date) -> [(String, Bool, String)] {
        typealias N = NetworkCheck
        var review: [(String, Bool, String)] = []

        // networkQuality's JSON, with the fields its man page lists; a run that couldn't finish has error_code
        let good = #"{"dl_throughput":241830000,"ul_throughput":38200000,"responsiveness":1240.6,"base_rtt":18,"interface_name":"en0"}"#
        let failed = #"{"error_code":-1009,"error_domain":"NSURLErrorDomain"}"#
        let p1 = N.parse(Data(good.utf8)) == .done(.init(download: 241_830_000, upload: 38_200_000, rpm: 1241))
        let p2 = { if case .failed = N.parse(Data(failed.utf8)) { return true }; return false }()
        let p3 = { if case .failed = N.parse(Data("killed".utf8)) { return true }; return false }()
        review.append(("network-test-result", p1 && p2 && p3, "result \(p1), couldn't finish \(p2), stopped \(p3)"))

        // the verdict follows the responsiveness draft's bands: 300 or fewer is poor, 1,000 or more is good
        let poor = N.verdict(.done(.init(download: 300_000_000, upload: 20_000_000, rpm: 300)))
        let fair = N.verdict(.done(.init(download: 300_000_000, upload: 20_000_000, rpm: 301)))
        let fine = N.verdict(.done(.init(download: 4_000_000, upload: 1_000_000, rpm: 1000)))
        let v = poor.contains("slow to respond") && poor.contains("the Mac is fine") && fair.contains("fairly well")
            && fine.contains("unlikely to be the cause")
        review.append(("network-verdict-bands", v, "300: \(poor) | 301: \(fair) | 1,000: \(fine)"))

        // the facts: weak Wi-Fi is Apple's -75 dBm line; AWDL is mentioned, hedged, only when it is on and the router
        // is off its channels; Private Relay (one tester) only when responsiveness isn't good; names never appear,
        // since Cool Head doesn't ask for Location
        let weak = N.Setup(link: .wifi(.init(rssi: -78, noise: -90, rate: 144, channel: 36, band: "5 GHz")), awdlOn: true)
        let strong149 = N.Setup(link: .wifi(.init(rssi: -54, noise: -89, rate: 864, channel: 149, band: "5 GHz")), awdlOn: true)
        let cable = N.Setup(link: .cable, awdlOn: true, vpn: true, proxy: true, dns: .internet)
        let slow = N.Result(download: 90_000_000, upload: 10_000_000, rpm: 210)
        let quick = N.Result(download: 900_000_000, upload: 40_000_000, rpm: 2400)
        let wl = N.lines(slow, weak), sl = N.lines(quick, strong149), cl = N.lines(nil, cable)
        let l1 = wl.contains { $0.hasPrefix("Wi-Fi signal is weak: -78 dBm") } && sl.contains { $0.hasPrefix("Wi-Fi signal is fine: -54 dBm") }
            && N.lines(nil, .init(link: .wifi(.init(rssi: -75, noise: -90, rate: 6, channel: 1, band: "2.4 GHz")))).contains { $0.hasPrefix("Wi-Fi signal is weak") }
        let l2 = wl.contains { $0.contains("router's 36") && $0.contains("Apple hasn't said so") }
            && !sl.contains { $0.contains("AirDrop") } && !cl.contains { $0.contains("AirDrop") }
        let l3 = wl.contains { $0.contains("Private Relay") && $0.contains("one tester") } && !sl.contains { $0.contains("Private Relay") }
            && !cl.contains { $0.contains("Private Relay") }
        let l4 = wl.first == "Speed: 90 Mbps down, 10 Mbps up." && sl[1].hasPrefix("Responsiveness: 2,400 round trips a minute")
            && cl.contains("Connected by cable.") && cl.contains { $0.hasPrefix("A VPN") } && cl.contains { $0.hasPrefix("A proxy") }
            && cl.contains { $0.contains("a server on the internet") } && !cl.contains { $0.hasPrefix("Speed") }
        let l5 = N.mbps(4_520_000) == "4.5 Mbps" && N.mbps(400_000) == "under 1 Mbps" && N.mbps(1_234_000_000) == "1,234 Mbps"
        review.append(("network-facts", l1 && l2 && l3 && l4 && l5,
                       "signal \(l1), AirDrop \(l2), Private Relay \(l3), lines \(l4), speeds \(l5): \(wl.joined(separator: " "))"))

        // who looks names up: the router (by its address, or IPv6 link-local), another local machine, or the internet
        let d = N.dnsKind(["192.168.1.1"], router: "192.168.1.1") == .router && N.dnsKind(["fe80::1%en0"], router: nil) == .router
            && N.dnsKind(["192.168.1.53"], router: "192.168.1.1") == .local && N.dnsKind(["172.20.0.2"], router: nil) == .local
            && N.dnsKind(["172.32.0.2"], router: nil) == .internet && N.dnsKind(["1.1.1.1"], router: "10.0.0.1") == .internet
            && N.dnsKind([], router: nil) == .none
        review.append(("network-dns-kind", d, "router, local and internet servers told apart: \(d)"))

        // nettop's second sample is what moved in the last second; one app's processes are added together, macOS's
        // own say so, and Cool Head and the test itself are left out
        let csv = """
        ,bytes_in,bytes_out,
        Dropbox.501,9000000,100,
        nsurlsessiond.300,5000,0,
        ,bytes_in,bytes_out,
        Dropbox.501,1800000,200000,
        Dropbox Helper.502,100000,0,
        nsurlsessiond.300,250000,50000,
        networkQuality.700,90000000,0,
        coolhead.42,500000,0,
        syslogd.363,0,0,
        """
        let paths: [pid_t: String] = [501: "/Applications/Dropbox.app/Contents/MacOS/Dropbox",
                                      502: "/Applications/Dropbox.app/Contents/Frameworks/Helper.app/Contents/MacOS/Dropbox Helper",
                                      300: "/usr/libexec/nsurlsessiond"]
        let t = N.talkers(nettop: csv, mine: 42, path: { paths[$0] })
        let t1 = t == [.init(name: "Dropbox", bytesPerSecond: 2_100_000), .init(name: "macOS's nsurlsessiond", bytesPerSecond: 300_000)]
        let said = N.lines(nil, .init(link: .cable, talkers: t)).last ?? ""
        let t2 = said == "Using the network: Dropbox (2.1 MB a second), macOS's nsurlsessiond (300 KB a second)."
        review.append(("network-who-is-using-it", t1 && t2, said))

        // every sentence follows the house style: no em dashes, no exclamation marks
        let all = [poor, fair, fine, N.explainer] + wl + sl + cl + N.lines(nil, .init(link: .none, dns: .none)) + N.lines(nil, .init(link: .other, autoProxy: true, dns: .local))
        let bad = all.filter { $0.contains("\u{2014}") || $0.contains("!") }
        review.append(("network-wording", bad.isEmpty, bad.isEmpty ? "\(all.count) sentences" : "breaks: \(bad)"))

        // and on this Mac: the connection reads with no permission prompt in about a second, and Apple's test is there
        // to be pressed (it isn't run). A Mac with no Wi-Fi or network (as on CI) reads as cable, other or none.
        let start = Date()
        let s = N.readSetup()
        let took = Date().timeIntervalSince(start)
        let tool = FileManager.default.isExecutableFile(atPath: "/usr/bin/networkQuality")
        let kind: String = { switch s.link { case .wifi: return "Wi-Fi"; case .cable: return "cable"; case .other: return "other"; case .none: return "none" } }()
        review.append(("network-read", took < 5 && tool,
                       "\(kind), AirDrop link \(s.awdlOn ? "on" : "off"), VPN \(s.vpn), \(s.talkers.count) processes moving data, read in \(String(format: "%.1f", took)) s; networkQuality present \(tool)"))
        return review
    }
}

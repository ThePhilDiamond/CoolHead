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
        review.append(("network-test-result", p1 && p2 && p3, "result \(p1), could not finish \(p2), stopped \(p3)"))

        // the verdict follows the responsiveness draft's bands (300 or fewer is poor, 1,000 or more is good) and the speed
        // HD video needs (5 Mbps); each task is checked against its own published speed and, for calls and games, responsiveness
        func res(_ down: Double, _ up: Double, _ rpm: Int) -> N.Result { .init(download: down * 1e6, upload: up * 1e6, rpm: rpm) }
        let poor = N.verdict(.done(res(300, 20, 300))), fair = N.verdict(.done(res(300, 20, 301))), fine = N.verdict(.done(res(300, 20, 1000)))
        let thin = N.verdict(.done(res(4, 1, 2000))), down = N.verdict(.failed("x"))
        let v1 = poor.level == 2 && poor.meaning.hasPrefix("The Mac is fine") && fair.level == 1 && fine.level == 0
            && fine.meaning.contains("the cause is on the Mac") && thin.level == 2 && thin.title == "The network is slow" && down.level == 2
        let calls = N.tasks.first { $0.name == "Video calls" }!, hd = N.tasks.first { $0.name == "HD video" }!, uhd = N.tasks.first { $0.name == "4K video" }!
        let v2 = N.fit(calls, res(300, 20, 250)) == .laggy && N.fit(calls, res(300, 3, 2000)) == .tooSlow && N.fit(calls, res(300, 20, 301)) == .fine
            && N.fit(hd, res(300, 20, 100)) == .fine && N.fit(uhd, res(12, 20, 2000)) == .tooSlow && N.delay(res(1, 1, 300)) == 200
        review.append(("network-verdict-and-tasks", v1 && v2, "verdicts \(v1), tasks \(v2): \(poor.title) | \(fair.title) | \(fine.title) | \(thin.title)"))

        // the result in one plain sentence: what's fine, then at most two things that aren't and what each affects
        let strong = N.Link.wifi(.init(rssi: -55, noise: -92, rate: 864, channel: 44, band: "5 GHz"))
        let weakLink = N.Link.wifi(.init(rssi: -80, noise: -90, rate: 50, channel: 1, band: "2.4 GHz"))
        let sums = [N.summary(res(300, 40, 1500), strong), N.summary(res(300, 2, 1500), strong), N.summary(res(8, 20, 250), .cable),
                    N.summary(res(2, 0.5, 100), weakLink)]
        let summed = sums == [
            "Fast enough for everything, from 4K video to calls and games.",
            "Fine for browsing, HD video, 4K video, and games, but uploads are slow, so video calls may break up.",
            "Fine for browsing and HD video, but the delay is long, so calls and games may lag.",
            "Fine for browsing, but the Wi-Fi signal is weak, and downloads are slow.",
        ]
        review.append(("network-summary", summed, sums.joined(separator: " | ")))

        // fixes appear only when something is wrong, only for causes that apply, the busiest app first; a fine network
        // gets none (offering to fix it would do harm), and a VPN is never turned off by Cool Head
        let busySync = N.Setup(link: .wifi(.init(rssi: -80, noise: -90, rate: 100, channel: 36, band: "5 GHz")), awdlOn: true, vpn: .init(),
                               talkers: [.init(name: "Dropbox", bytesPerSecond: 2_000_000, bundle: "/Applications/Dropbox.app")])
        let f1 = N.fixes(res(50, 10, 200), busySync).map(\.id)
        let f2 = N.fixes(res(500, 40, 2400), busySync)
        let f3 = N.fixes(res(500, 40, 2400), N.Setup(link: .cable)).isEmpty && N.fixes(res(3, 1, 2400), N.Setup(link: .cable)).map(\.id) == ["net-provider"]
        let fx = f1 == ["net-pause-sync", "net-signal", "net-diagnostics", "net-smart-queue", "net-airdrop", "net-private-relay", "net-vpn", "net-provider"].filter { f1.contains($0) }
            && f1.first == "net-pause-sync" && f1.contains("net-airdrop") && f1.contains("net-vpn") && f2.isEmpty && f3
            && N.fixes(res(50, 10, 200), busySync).first?.recommended == true
            && N.fixes(res(50, 10, 200), busySync).allSatisfy { $0.doer == .you }
        review.append(("network-fixes", fx, "poor, weak, busy: \(f1); fine: \(f2.count) options; cable \(f3)"))

        // the facts: weak Wi-Fi is Apple's -75 dBm line; AWDL is mentioned, hedged, only when it is on and the router
        // is off its channels; Private Relay (one tester) only when responsiveness isn't good; names never appear,
        // since Cool Head doesn't ask for Location
        let weak = N.Setup(link: .wifi(.init(rssi: -78, noise: -90, rate: 144, channel: 36, band: "5 GHz")), awdlOn: true)
        let strong149 = N.Setup(link: .wifi(.init(rssi: -54, noise: -89, rate: 864, channel: 149, band: "5 GHz")), awdlOn: true)
        let cable = N.Setup(link: .cable, awdlOn: true, vpn: .init(), proxy: true, dns: .internet)
        let slow = N.Result(download: 90_000_000, upload: 10_000_000, rpm: 210)
        let quick = N.Result(download: 900_000_000, upload: 40_000_000, rpm: 2400)
        let wl = N.lines(slow, weak), sl = N.lines(quick, strong149), cl = N.lines(nil, cable)
        let l1 = wl.contains { $0.hasPrefix("Wi-Fi signal is weak: -78 dBm") } && sl.contains { $0.hasPrefix("Wi-Fi signal is fine: -54 dBm") }
            && N.lines(nil, .init(link: .wifi(.init(rssi: -75, noise: -90, rate: 6, channel: 1, band: "2.4 GHz")))).contains { $0.hasPrefix("Wi-Fi signal is weak") }
        let l2 = wl.contains { $0.contains("router's 36") && $0.contains("Apple has not said so") }
            && !sl.contains { $0.contains("AirDrop") } && !cl.contains { $0.contains("AirDrop") }
        let l3 = !wl.contains { $0.contains("Private Relay") } && wl.contains { $0.contains("a wait of about 286 ms") }
        let l4 = wl.first == "Speed: 90 Mbps down, 10 Mbps up." && sl[1].hasPrefix("Responsiveness: 2,400 round trips a minute")
            && cl.contains("Connected by cable.") && cl.contains { $0.hasPrefix("The VPN carries all your traffic") } && cl.contains { $0.hasPrefix("A proxy") }
            && cl.contains { $0.contains("a server on the internet") } && !cl.contains { $0.hasPrefix("Speed") }
        let l5 = N.mbps(4_520_000) == "4.5 Mbps" && N.mbps(400_000) == "under 1 Mbps" && N.mbps(1_234_000_000) == "1,234 Mbps"
            && N.lines(nil, .init(link: .wifi(.init(rssi: -50, noise: -89, rate: 1200, channel: 157, band: "5 GHz")))).contains("Wi-Fi is sending at up to 1,200 Mbps on channel 157 (5 GHz).")
        review.append(("network-facts", l1 && l2 && l3 && l4 && l5,
                       "signal \(l1), AirDrop \(l2), delay \(l3), lines \(l4), speeds \(l5): \(wl.joined(separator: " "))"))

        // who looks names up: the router (by its address, or IPv6 link-local), another local machine, or the internet
        let d = N.dnsKind(["192.168.1.1"], router: "192.168.1.1") == .router && N.dnsKind(["fe80::1%en0"], router: nil) == .router
            && N.dnsKind(["192.168.1.53"], router: "192.168.1.1") == .local && N.dnsKind(["172.20.0.2"], router: nil) == .local
            && N.dnsKind(["172.32.0.2"], router: nil) == .internet && N.dnsKind(["1.1.1.1"], router: "10.0.0.1") == .internet
            && N.dnsKind([], router: nil) == .none
        review.append(("network-dns-kind", d, "router, local, and internet servers told apart: \(d)"))

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
        x.501,99999999.666,10,0,
        """
        let paths: [pid_t: String] = [501: "/Applications/Dropbox.app/Contents/MacOS/Dropbox",
                                      502: "/Applications/Dropbox.app/Contents/Frameworks/Helper.app/Contents/MacOS/Dropbox Helper",
                                      300: "/usr/libexec/nsurlsessiond"]
        // a process named to look like "x.501,99999999" is read as itself (pid 666, 10 bytes), not as Dropbox
        let names: [pid_t: String] = [501: "Dropbox", 502: "Dropbox Helper", 300: "nsurlsessiond", 700: "networkQuality",
                                      42: "coolhead", 363: "syslogd", 666: "x.501,99999999"]
        let t = N.talkers(nettop: csv, mine: 42, path: { paths[$0] }, name: { names[$0] })
        let t1 = t.filter { $0.bytesPerSecond >= 100 } == [.init(name: "Dropbox", bytesPerSecond: 2_100_000, bundle: "/Applications/Dropbox.app"), .init(name: "macOS's nsurlsessiond", bytesPerSecond: 300_000)]
        let said = N.lines(nil, .init(link: .cable, talkers: t)).last ?? ""
        let t2 = said == "Using the network: Dropbox (2.1 MB a second), macOS's nsurlsessiond (300 KB a second)."
        let spoof = t.first { $0.name.hasPrefix("x.") }?.bytesPerSecond == 10
            && N.talkers(nettop: csv, mine: 42, path: { paths[$0] }, name: { _ in "other" }).isEmpty
        review.append(("network-who-is-using-it", t1 && t2 && spoof, "\(said) Spoofed name read as itself: \(spoof)"))

        // security review, 16 November 2026: the activity log (which can go into a public Report a problem issue) says
        // which fix was pressed by its fixed id only, never a title that names an app; a phone or metered connection
        // is warned about the data the test uses; a result that isn't a finite number reads as a failed test
        let secret = N.Setup(link: .wifi(.init(rssi: -80, noise: -90, rate: 100, channel: 36, band: "5 GHz")), awdlOn: true, vpn: .init(), proxy: true,
                             talkers: [.init(name: "Secret Thesis Renderer", bytesPerSecond: 3_000_000, bundle: "/Users/alice/Projects/Secret Thesis Renderer.app")])
        let logged = N.fixes(res(3, 1, 200), secret).map(N.logLine)
        let leaks = logged.filter { l in ["Secret", "Thesis", "alice", "Renderer"].contains { l.contains($0) } }
        let s1 = !logged.isEmpty && leaks.isEmpty && N.fixes(res(3, 1, 200), secret).first?.title.contains("Secret Thesis Renderer") == true
        let s2 = N.Setup(link: .other).mayBeMetered && N.Setup(link: .cable, metered: true).mayBeMetered && !N.Setup(link: .cable).mayBeMetered
        let s3 = { if case .failed = N.parse(Data(#"{"responsiveness":1e400,"dl_throughput":1}"#.utf8)) { return true }; return false }()
            && N.parse(Data(#"{"responsiveness":5e300,"dl_throughput":1}"#.utf8)) == .done(.init(download: 1, upload: 0, rpm: 1_000_000))
        review.append(("network-private-and-safe", s1 && s2 && s3,
                       "log names no app \(s1) (\(logged.count) lines), metered warning \(s2), odd numbers \(s3)"))

        // a VPN is told apart by what it carries, read on the Mac with nothing sent: only "Test without the VPN" when it
        // carries websites' traffic; each gap says what to look for in the VPN's settings; the app's name when known
        let full = N.VPN(name: "WireGuard"), split = N.VPN(name: "WireGuard", carries: .someAddresses, lookups: false)
        let v6 = N.VPN(carries: .notIPv6), dnsOut = N.VPN(name: "WireGuard", lookups: false)
        let wifi44 = N.Link.wifi(.init(rssi: -80, noise: -90, rate: 100, channel: 44, band: "5 GHz"))
        let vf1 = N.fixes(res(50, 10, 200), .init(link: wifi44, vpn: full)).contains { $0.id == "net-vpn" }
            && !N.fixes(res(50, 10, 200), .init(link: wifi44, vpn: split)).contains { $0.id == "net-vpn" }
        let vl = [N.vpnLine(full), N.vpnLine(split), N.vpnLine(v6), N.vpnLine(dnsOut)]
        let vf2 = vl[0].hasPrefix("WireGuard carries all your traffic") && vl[1].contains("websites go directly") && vl[1].contains("send all traffic")
            && vl[2].hasPrefix("The VPN is on, but newer IPv6 traffic") && vl[2].contains("leak protection")
            && vl[3].contains("your internet provider can still see") && vl[3].contains("DNS leak protection")
        let vf3 = N.vpnSaid(nil) == (-1, "Off", "No VPN is connected.") && N.vpnSaid(full).level == 0 && N.vpnSaid(dnsOut).level == 1
            && N.vpnSaid(split).detail.contains("websites go directly") && N.vpnSaid(v6).value == "On"
        review.append(("network-vpn", vf1 && vf2 && vf3, "test-without fix only when it carries websites \(vf1), lines \(vf2), panel words \(vf3): \(vl.joined(separator: " | "))"))

        // who looks names up, named when it's a well-known service, with who set it; the router's own page in the
        // Smart Queue steps; a Mac that gave itself an address is told to turn Wi-Fi off and on
        let rn = N.resolverName("1.1.1.1") == "Cloudflare" && N.resolverName("2606:4700:4700::1111") == "Cloudflare"
            && N.resolverName("8.8.4.4") == "Google" && N.resolverName("45.90.28.77") == "NextDNS" && N.resolverName("9.9.9.90") == nil
            && N.resolverName("1.1.1.10") == nil && N.resolverName("192.168.1.1") == nil
        let byHand = N.dnsLine(.init(link: .cable, dns: .internet, dnsName: "Cloudflare", dnsSetBy: .thisMac))
        let byVPN = N.dnsLine(.init(link: .cable, vpn: full, dns: .internet, dnsName: "Quad9", dnsSetBy: .vpn))
        let dl = byHand.hasPrefix("Website names are looked up by Cloudflare, set by hand on this Mac") && byHand.contains("first thing to remove")
            && byVPN == "Website names are looked up by Quad9, set by WireGuard."
            && N.dnsLine(.init(link: .cable)) == "Website names are looked up by your router."
            && N.dnsSaid(.init(link: .cable, dns: .internet, dnsSetBy: .thisMac)) == ("Internet", "Set by hand on this Mac.")
        let queue = N.fixes(res(300, 20, 250), .init(link: .cable, router: "192.168.1.1")).first { $0.id == "net-smart-queue" }
        let rq = { if case .guide(let steps)? = queue?.kind { return steps.first == "Open your router's settings: its app, or http://192.168.1.1 in a browser." }; return false }()
        let sa = N.lines(nil, .init(link: .wifi(.init(rssi: -50, noise: -90, rate: 600, channel: 44, band: "5 GHz")), selfAssigned: true))
            .contains { $0.hasPrefix("The router did not give this Mac an address") }
        review.append(("network-dns-and-address", rn && dl && rq && sa, "services named \(rn), who set it \(dl), router page \(rq), self-assigned \(sa): \(byHand)"))

        // where websites see you: Cloudflare's trace text read for its address and country (anything else refused); the
        // address is only compared, never shown; with a VPN, the request around it tells hiding, not hiding and blocking apart
        let traceText = "fl=12f1\nh=www.cloudflare.com\nip=203.0.113.7\nts=1763380000.1\nvisit_scheme=https\nloc=NL\ntls=TLSv1.3\nwarp=off\n"
        let nl = N.Seen(address: "203.0.113.7", country: "NL"), us = N.Seen(address: "198.51.100.4", country: "US")
        let tr = N.trace(traceText) == nl && N.trace("ip=1.2.3.4\nloc=<script>") == nil && N.trace("loc=US") == nil && N.trace("") == nil
            && N.country("NL") == "Netherlands" && N.country("US") == "United States" && N.country("T1") == "the Tor network"
        let seen = [N.whereSaid(.seen(nl, around: .other(us)), full), N.whereSaid(.seen(nl, around: .same), full),
                    N.whereSaid(.seen(nl, around: .blocked), full), N.whereSaid(.seen(us, around: .notAsked), nil),
                    N.whereSaid(.seen(us, around: .notAsked), split), N.whereSaid(.failed, nil)]
        let ws = seen.map { $0.level } == [0, 1, 0, 0, 1, 2] && seen[0].value == "Netherlands" && seen[0].detail == "Through WireGuard; without it, United States."
            && seen[1].detail == "Your own address: WireGuard is not hiding it." && seen[3].detail == "Your own address: no VPN is on."
            && !seen.contains { $0.value.contains("203.0") || $0.detail.contains("203.0") || $0.detail.contains("198.51") }
        let note = N.whereNote(.init(link: .cable, vpn: full, physical: "en0")).contains("around it") && !N.whereNote(.init(link: .cable, vpn: split)).contains("around")
            && N.privacySentence(.init(link: .cable), nil) == "No VPN is connected. The test also asks Cloudflare which country websites see you in."
            && N.privacySentence(.init(link: .cable, vpn: dnsOut), .seen(nl, around: .other(us))) == "Through WireGuard; without it, United States. Site names are looked up outside it, so your provider sees which sites you visit."
            && N.privacySentence(.init(link: .cable, vpn: full), .seen(nl, around: .blocked)) == "Through WireGuard, which stops traffic going around it."
        review.append(("network-where-seen", tr && ws && note, "trace read \(tr), said \(ws), note \(note): \(seen.map { "\($0.value): \($0.detail)" }.joined(separator: " | "))"))

        // every sentence follows the house style: no em dashes, no exclamation marks
        // built in typed parts: one long expression of + and flatMap is too slow for the compiler's type checker
        var all: [String] = [N.explainer, N.dataNote, N.meteredNote]
        for v in [poor, fair, fine, thin] { all += [v.title, v.meaning] }
        for f in N.fixes(res(50, 10, 200), busySync) { all += [f.title, f.consequence] }
        all += wl
        all += sl
        all += cl
        all += N.lines(nil, .init(link: .none, dns: .none))
        all += N.lines(nil, .init(link: .other, autoProxy: true, dns: .local))
        all += vl
        all += [byHand, byVPN, N.whereNote(.init(link: .cable)), N.whereNote(.init(link: .cable, vpn: full)),
                N.privacySentence(.init(link: .cable, vpn: v6), nil), N.privacySentence(.init(link: .cable, vpn: dnsOut), .failed)]
        for x in seen { all += [x.value, x.detail] }
        for v in [nil, full, split, v6, dnsOut] { let x = N.vpnSaid(v); all += [x.value, x.detail] }
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
                       "\(kind), AirDrop link \(s.awdlOn ? "on" : "off"), VPN \(s.vpn.map { "\($0.carries)" } ?? "off"), DNS set by \(s.dnsSetBy), \(s.talkers.count) processes moving data, read in \(String(format: "%.1f", took)) s; networkQuality present \(tool)"))
        return review
    }

    /// No sample cards of its own for `coolhead wording`.
    static func networkSamples(_ now: Date) -> [(String, Card)] { [] }
}

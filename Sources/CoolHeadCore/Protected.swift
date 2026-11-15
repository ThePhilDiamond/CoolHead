import Foundation

/// Security, device management and VPN software. Cool Head never offers to stop, slow or quit it: stopping one can
/// leave the Mac unprotected, break an employer's rules, or look like tampering.
///
/// The product list is from System Sentinel's `SecurityAgents.swift` (MIT License, Copyright (c) 2026 Andrew Baker,
/// https://github.com/andrewbakercloudscale/system-sentinel); see THIRD_PARTY_NOTICES.md.
public enum SecuritySoftware {
    public enum Kind { case security, vpn }

    static let known: [(match: [String], name: String, kind: Kind)] = [
        (["avasecurity", "ava.reveal", "avareveal", "ava-reveal", "ava_reveal"], "Ava Reveal", .security),
        (["forcepoint", "websense", "fpneo"], "Forcepoint", .security),
        (["code42", "incydr"], "Code42 Incydr", .security),
        (["digitalguardian", "dgagent", "com.dg."], "Digital Guardian", .security),
        (["symantec", "edpa"], "Symantec", .security),
        (["netskope", "stagentsvc"], "Netskope", .security),
        (["crowdstrike", "falcond"], "CrowdStrike Falcon", .security),
        (["sentinelone", "sentineld", "sentinelagent"], "SentinelOne", .security),
        (["wdav", "com.microsoft.wdav", "microsoft defender"], "Microsoft Defender", .security),
        (["jamf.protect", "jamfprotect"], "Jamf Protect", .security),
        (["mcafee", "trellix"], "Trellix (McAfee)", .security),
        (["sophos"], "Sophos", .security),
        (["carbonblack", "cbagentd"], "Carbon Black", .security),
        (["paloaltonetworks", "cortex xdr", "com.paloaltonetworks.cortex"], "Cortex XDR", .security),
        (["elastic-endpoint", "co.elastic.endpoint"], "Elastic Endpoint", .security),
        (["ampdaemon", "com.cisco.endpoint", "cisco.amp"], "Cisco Secure Endpoint", .security),
        (["eset"], "ESET", .security),
        (["kaspersky"], "Kaspersky", .security),
        (["tanium"], "Tanium", .security),
        (["teramind"], "Teramind", .security),
        (["activtrak"], "ActivTrak", .security),
        (["zscaler"], "Zscaler", .security),
        (["intunemdm", "com.microsoft.intune", "companyportal", "company portal"], "Microsoft Intune", .security),
        (["jamf"], "Jamf", .security),
        (["kandji"], "Kandji", .security),
        (["mosyle"], "Mosyle", .security),
        (["addigy"], "Addigy", .security),
        (["workspaceone", "airwatch", "hubcli"], "Workspace ONE", .security),
        (["cloudflare warp", "warp-svc", "com.cloudflare.1dot1dot1dot1"], "Cloudflare WARP", .vpn),
        (["tailscale"], "Tailscale", .vpn),
        (["globalprotect", "pangps"], "GlobalProtect", .vpn),
        (["vpnagentd", "acvpnagent", "anyconnect"], "Cisco Secure Client", .vpn),
        (["openvpn"], "OpenVPN", .vpn),
        (["wireguard"], "WireGuard", .vpn),
        (["nordvpn"], "NordVPN", .vpn),
        (["fortitray", "forticlient", "fortivpn"], "FortiClient", .vpn),
    ]

    /// The product a process belongs to, from its path, name and app's bundle identifier. A pattern must start a word
    /// ("eset" matches ESET or com.eset, never the middle of "Reset"). macOS's own programs are never matched.
    public static func product(path: String?, name: String) -> (name: String, kind: Kind)? {
        if let p = path, CaseReport.isMacOS(p) { return nil }
        var text = name + " " + (path ?? "")
        if let p = path, let r = p.range(of: ".app/"), let id = Bundle(path: String(p[..<r.lowerBound]) + ".app")?.bundleIdentifier {
            text += " " + id
        }
        let t = text.lowercased()
        func starts(_ pattern: String) -> Bool {
            var from = t.startIndex
            while let r = t.range(of: pattern, range: from..<t.endIndex) {
                if r.lowerBound == t.startIndex || !t[t.index(before: r.lowerBound)].isLetter { return true }
                from = t.index(after: r.lowerBound)
            }
            return false
        }
        return known.first { $0.match.contains(where: starts) }.map { ($0.name, $0.kind) }
    }
}

/// Apps that keep a folder in step with the cloud. Busy while catching up is normal; pausing is the fix that loses
/// nothing (from System Sentinel's advice, adapted).
public enum SyncApps {
    static let known: [String: String] = [
        "com.google.drivefs": "Google Drive",
        "com.getdropbox.dropbox": "Dropbox",
        "com.microsoft.OneDrive": "OneDrive",
        "com.microsoft.OneDrive-mac": "OneDrive",
        "com.box.desktop": "Box",
    ]

    /// The sync app a process belongs to (any process inside its app bundle), by bundle identifier.
    public static func app(bundle: String?) -> String? {
        guard let b = bundle else { return nil }
        if let id = Bundle(path: b)?.bundleIdentifier { return known[id] }
        // not installed here (as in the selftest): by the app's own name
        let name = ((b as NSString).lastPathComponent as NSString).deletingPathExtension
        return Set(known.values).contains(name) ? name : nil
    }
}

import Foundation

/// Security, device management and VPN software (Protected.swift): never stopped, slowed, or quit, since stopping one
/// can leave the Mac unprotected or break an employer's rules.
enum SecuritySoftwareCard: ProcessCard {
    static let name = "security software"
    static let id = "security-software"
    static let kind = CardKind.explanation
    static let rule = "System Sentinel's review, 15 November 2026: security software is never stopped, slowed, or quit"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this security product") }
    static let samples = ["security-software", "vpn"]

    static func card(_ s: Situation) -> Card? {
        guard var c = made(s) else { return nil }
        if let product = SecuritySoftware.product(path: s.e.path, name: s.e.name) {
            let vpn = product.kind == .vpn
            c.diagnosis = Diagnosis(saw: vpn ? "\(product.name) is your VPN, handling your network traffic" : "\(product.name) is security software, checking files as they're used")
            c.optionFacts["disconnect"] = OptionFacts(helps: "lightens the load", whyNot: "only you know when you can do without it")
        }
        return c
    }

    static func made(_ s: Situation) -> Card? {
        let e = s.e
        guard let product = SecuritySoftware.product(path: e.path, name: e.name) else { return nil }
        if e.coresNow < 0.25 { return Card(state: .quiet, CardTemplate(product.name, .quiet, nil), fixes: []) }
        let vpn = product.kind == .vpn
        return Card(state: .working,
                    CardTemplate(product.name, .words(vpn ? "is your VPN" : "is security software"), .normal,
                                 evidence: [vpn ? "It handles your network traffic." : "It checks files as they are used."],
                                 effect: ["Cool Head does not stop or slow it, because that can leave your Mac unprotected or break your organization's rules."]
                                    + (vpn ? [] : ["If it stays busy for hours, tell whoever manages this Mac, because it may be stuck on a big folder."])),
                    fixes: [vpn ? e.appBundle.map { Fix.openApp("disconnect", "Disconnect when you do not need it", bundle: $0, steps: "Disconnect there, or from its menu bar icon.") } : nil,
                            Card.lookUp(product.name, recommended: false)].compactMap { $0 })
    }
}

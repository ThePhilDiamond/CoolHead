import Foundation

/// Security, device management and VPN software (Protected.swift): never stopped, slowed or quit, since stopping one
/// can leave the Mac unprotected or break an employer's rules.
enum SecuritySoftwareCard: ProcessCard {
    static let name = "security software"
    static let id = "security-software"
    static let kind = CardKind.explanation
    static let rule = "System Sentinel's review, 15 November 2026: security software is never stopped, slowed or quit"
    static func confidence(_ s: Situation) -> Confidence { .named("we know this security product") }
    static let samples = ["security-software", "vpn"]

    static func card(_ s: Situation) -> Card? {
        let e = s.e
        guard let product = SecuritySoftware.product(path: e.path, name: e.name) else { return nil }
        if e.coresNow < 0.25 { return Card(state: .quiet, headline: "\(product.name) is quiet now.", explanation: "", fixes: []) }
        let vpn = product.kind == .vpn
        return Card(state: .working,
                    headline: vpn ? "\(product.name) is your VPN, handling your network traffic." : "\(product.name) is security software, checking files as they're used.",
                    explanation: "Cool Head won't stop or slow it: that could leave your Mac unprotected or break your organization's rules."
                        + (vpn ? "" : " If it's busy for hours, tell whoever manages this Mac: it may be stuck scanning a big folder."),
                    fixes: [vpn ? e.appBundle.map { Fix.openApp("disconnect", "Disconnect when you don't need it", bundle: $0, steps: "Disconnect there, or from its menu bar icon.") } : nil,
                            Card.lookUp(product.name, recommended: false)].compactMap { $0 })
    }
}

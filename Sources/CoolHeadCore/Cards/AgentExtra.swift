import Foundation

/// Another app's background helper (see BackgroundAgents): stopping it doesn't last, since launchd starts it again, so
/// turning it off is offered too; never on macOS's own or security software, which never get here as agents.
enum AgentExtra: CardExtra {
    static let id = "agent"
    static let rule = "BackgroundAgents.swift: a helper launchd restarts is turned off, not only stopped"

    static func add(to c: Card, _ s: Situation) -> Card? {
        guard let a = s.agent, s.e.mine, c.state != .quiet, !c.fixes.contains(where: { $0.id == "agent" }) else { return nil }
        return c.adding(fixes: c.fixes + [BackgroundAgents.fix(a)])
    }
}

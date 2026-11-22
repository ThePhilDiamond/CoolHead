import Foundation

// Menu items, buttons, headings, and addresses named in steps are underlined in the panel, so the words to look for
// stand out from the words around them and a path through menus is clear. The text carries two invisible marks around
// each name; the app draws what's between them underlined, and everything printed as plain text (`coolhead`, reports,
// checks) drops them with `Fmt.plain`.
extension Fmt {
    static let uiOpen: Character = "\u{E000}", uiClose: Character = "\u{E001}"

    /// A menu item, button, heading or address, to be underlined: `Fmt.ui("Window")`.
    public static func ui(_ name: String) -> String { "\(uiOpen)\(name)\(uiClose)" }

    /// A path of menu items, each underlined, joined by ▸: `Fmt.path("Apple menu", "Restart")`.
    public static func path(_ items: String...) -> String { items.map(ui).joined(separator: " ▸ ") }

    /// The text without its underline marks.
    public static func plain(_ s: String) -> String { s.filter { $0 != uiOpen && $0 != uiClose } }

    /// The text in runs, each saying whether it's underlined, for the app to draw.
    public static func uiRuns(_ s: String) -> [(text: String, underlined: Bool)] {
        var runs: [(text: String, underlined: Bool)] = [], current = "", inside = false
        for ch in s {
            if ch == uiOpen || ch == uiClose {
                if !current.isEmpty { runs.append((current, inside)) }
                current = ""; inside = ch == uiOpen
            } else { current.append(ch) }
        }
        if !current.isEmpty { runs.append((current, inside)) }
        return runs
    }
}

/// Steps for a browser's own list of what each tab is using: Task Manager in Chrome and the browsers built like it. A
/// single line, "Choose Window ▸ Task Manager, then click Memory to put the biggest first", proved unclear in use. No
/// URL or AppleScript command opens Chrome's Task Manager, and clicking its menu for you would need the Accessibility
/// permission, which Cool Head doesn't ask for.
public enum TaskManager {
    /// How to open it, as a sentence. Safari's Activity window may no longer list what each tab uses (not yet checked).
    static func open(_ browser: String) -> String {
        browser == "Safari" ? "Choose \(Fmt.path("Window", "Activity"))."
            : browser == "Firefox" ? "Type \(Fmt.ui("about:processes")) in the address bar and press Return."
            : "In the menu bar at the top of your screen, click \(Fmt.ui("Window")), then \(Fmt.ui("Task Manager"))."
    }

    /// How to sort it: "Click the Memory heading so the tab using the most is at the top."
    static func sort(by heading: String, so first: String) -> String { "Click the \(Fmt.ui(heading)) heading so \(first) is at the top." }
}

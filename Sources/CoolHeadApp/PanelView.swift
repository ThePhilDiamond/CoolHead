import AppKit
import CoolHeadCore
import SwiftUI
import CoolHeadChromeLink

struct PanelView: View {
    let watcher: Watcher
    @ObservedObject private var network = NetworkTester.shared
    @ObservedObject private var tools = Tools.shared
    @AppStorage("welcomed") private var welcomed = false
    // a screenshot limited to some cards shows neither, so it shows the cards as anyone would see them day to day
    @State private var whatsNew = PanelView.limitedSnapshot ? nil : WhatsNew.pending
    /// A screenshot limited to some cards (COOLHEAD_SNAPSHOT_ONLY) or to example cards (COOLHEAD_SNAPSHOT_SAMPLES):
    /// no welcome or What's new, and the header follows only the cards shown.
    static let limitedSnapshot = ["COOLHEAD_SNAPSHOT_ONLY", "COOLHEAD_SNAPSHOT_SAMPLES"].contains { ProcessInfo.processInfo.environment[$0] != nil }
    static let sampleSnapshot = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SAMPLES"] != nil
    /// In a screenshot limited to some of this Mac's cards (COOLHEAD_SNAPSHOT_ONLY), the processes they're about.
    static func onlyPIDs(_ w: Watcher) -> Set<pid_t>? {
        guard let only = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] else { return nil }
        let phrases = only.split(separator: "|").map(String.init)
        return Set(w.cards.filter { c in phrases.contains { c.card.headline.contains($0) } }.compactMap(\.pid))
    }

    /// The middle scrolls; the panel grows with it up to this height, so it stays easy to read. High enough for all of
    /// Test my network, results and an option included (it was 560, or 62% of the screen, which cut the network page
    /// short), and on a short screen, the screen less the top row, the tools, and a margin.
    static var maxMiddle: CGFloat {
        // screenshots of a whole long card (COOLHEAD_SNAPSHOT_TALL) aren't held to the screen's height
        if ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_TALL"] != nil { return 1600 }
        return min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 220)
    }
    @State private var middleHeight: CGFloat = 0

    /// The panel's width: a little wider than the 412 it was, to give the cards and tools more room.
    static let width: CGFloat = 440

    /// With scroll bars that take room (System Settings ▸ Appearance ▸ Show scroll bars: Always, or with a mouse plugged in),
    /// the panel grows by the scroll bar's width while the middle scrolls, so the scroll bar sits beside what's in the
    /// middle and never narrows it; a scroll bar inside the panel squeezed the content, so opening or closing a card
    /// changed the height of On hold above it. With scroll bars that float over the content, there's nothing to make
    /// room for.
    static var scrollerRoom: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }
    /// How much wider the panel is now: the scroll bar's room while the middle scrolls (it scrolls once it's taller than
    /// maxMiddle).
    var extra: CGFloat { middleHeight > PanelView.maxMiddle ? PanelView.scrollerRoom : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // fixed at the top: the snowflake, what's happening and how busy the chip and memory are, in one row; the
            // status is its title. There's no separate title bar above it, so the top is just the large icon, what's
            // happening, and the chip and memory figures. The version is in the toolbar along the bottom.
            RunningStrip(watcher: watcher, cards: shownCards, title: status, level: level, extra: extra,
                         back: backTo)
                // with a tool open, clicking the top goes back to the cards: the top names any problem, so a click on
                // it leads to the cards about it
                .contentShape(Rectangle())
                .onTapGesture { if toolOpen { withAnimation(.easeOut(duration: 0.15)) { Tools.closeAll(watcher) } } }
                .help(toolOpen ? "Back to the cards" : "")
                .accessibilityAddTraits(toolOpen ? .isButton : [])
            Divider()
            // scrolls once it is taller than the limit
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // screenshots can show the welcome beside made-up cards (COOLHEAD_SNAPSHOT_WELCOME)
                    if (!welcomed && !PanelView.limitedSnapshot) || ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_WELCOME"] != nil {
                        WelcomeCard { welcomed = true; WhatsNew.markSeen() }
                    }
                    else if let notes = whatsNew { WhatsNewCard(notes: notes) { WhatsNew.markSeen(); whatsNew = nil } }
                    UpdateBanner()
                    ForEach(watcher.notices, id: \.self) { n in
                        Label(n, systemImage: "hare").font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    // everything Cool Head is holding back, one line each, then a line before the cards
                    if !FrozenItem.all(watcher).isEmpty {
                        FrozenList(watcher: watcher)
                        Divider()
                    }
                    // the tools along the bottom open here, one at a time
                    if network.shown {
                        NetworkView(tester: network, watcher: watcher)
                    } else if tools.settings {
                        SettingsView()
                    } else if tools.trusted {
                        TrustedView(watcher: watcher)
                    } else if tools.battery {
                        BatteryView(watcher: watcher, close: { tools.battery = false })
                    } else if tools.hardware {
                        HardwareView(close: { tools.hardware = false })
                    } else if tools.cleaner {
                        CleanerView(close: { tools.cleaner = false })
                    } else if watcher.showReport {
                        ProblemView(watcher: watcher)
                    } else if shownCards.isEmpty && !watcher.syncPauses.contains(where: { $0.until <= Date() }) {
                        Text(watcher.mac.cores == 0 ? "Taking a first look…" : "Nothing needs a look.")
                            .foregroundStyle(Ink.muted)
                    } else {
                        ForEach(shownCards) { CardView(live: $0, watcher: watcher) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(watcher.panelSession)          // rebuilt after each close, so everything starts collapsed
                .background(GeometryReader { g in Color.clear.preference(key: MiddleHeight.self, value: g.size.height) })
            }
            .frame(height: min(max(middleHeight, 40), PanelView.maxMiddle))
            .onPreferenceChange(MiddleHeight.self) { middleHeight = $0 }
            // with nothing else open, Managed by Cool Head is: each time the panel opens, and when the last tool closes
            .onChange(of: watcher.panelSession) { PanelFocus.shared.open = PanelFocus.onHold }
            .onChange(of: toolOpen) { if !toolOpen { PanelFocus.shared.openSection() } }
            Divider()
            // fixed at the bottom
            VStack(alignment: .leading, spacing: 10) {
                // the battery's health is on the Battery tool's page now, not a line here
                ToolsBar(watcher: watcher)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            .padding(.trailing, extra)           // the tools stay where they were while the panel is wider
            // the same wash of the level's color as the top, so the two bars match as the frame outside the active
            // items in the middle
            .background(Color(nsColor: Badge.color(level)).opacity(0.10))
            .environment(\.barWash, Color(nsColor: Badge.color(level)).opacity(0.10))
        }
        .frame(width: PanelView.width + extra)
        // macOS's own controls (filled buttons) in Cool Head blue too, not the Mac's accent color (see Ink.accent)
        .tint(Ink.accent)
        // the panel's window takes exactly this size, growing and shrinking with it (see PanelSize)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { PanelSize.report?($0) }
    }

    /// For screenshots: COOLHEAD_SNAPSHOT_ONLY shows only cards whose headline contains that phrase (or any of several, separated by |),
    /// so a screenshot never shows the person's own processes.
    /// The header's level: the same rule, and the same cards, as the snowflake below it and the menu bar icon.
    var level: Watcher.Level { watcher.level(shownCards, thermal: RunningStrip.snapshotThermal) }

    /// A tool, Settings, or Report a problem is open in the middle.
    /// With a tool open and cards waiting, the pill in the top bar that goes back to them, saying what they hold: the
    /// fixes the cards recommend, or, when none recommends one, how many there are. No "The cards below need attention"
    /// line beside it, since going back to them is the pill's whole point.
    var backTo: String? {
        guard toolOpen, !shownCards.isEmpty else { return nil }
        let fixes = shownCards.filter { $0.card.fixes.contains { $0.recommended } }.count
        if fixes > 0 { return fixes == 1 ? "1 fix recommended" : "\(fixes) fixes recommended" }
        return shownCards.count == 1 ? "1 card to watch" : "\(shownCards.count) cards to watch"
    }

    var toolOpen: Bool {
        network.shown || tools.settings || tools.trusted || tools.battery || tools.hardware || tools.cleaner
            || watcher.showReport
    }

    var shownCards: [LiveCard] {
        // COOLHEAD_SNAPSHOT_SAMPLES shows example cards (as `coolhead wording` names them, separated by |) in place of
        // this Mac's, so a screenshot can show any kind of card and never the person's own processes
        if let names = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SAMPLES"] {
            let wanted = names.split(separator: "|").map(String.init)
            let samples = Wording.samples()
            return wanted.compactMap { w in samples.first { $0.0 == w }.map { s in
                // the night card's Nerdy stuff, made up to match its sample, so a screenshot shows the terminal filled
                guard s.0 == "power-night-upkeep" else { return LiveCard.sample(s.0, s.1) }
                return LiveCard.sample(s.0, s.1, details: ["Slept: 11:40pm on 15 November to 7:15am on 16 November",
                    "Charge: 85% to 66%", "Woke for macOS's own upkeep: 23", "Woke for the network: 7"])
            } }
        }
        guard let only = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONLY"] else { return watcher.cards + CardSources.all.flatMap { $0.cards(for: watcher) } }
        let phrases = only.split(separator: "|").map(String.init)      // several phrases, separated by |
        return watcher.cards.filter { c in phrases.contains { c.card.headline.contains($0) } }   // see onlyPIDs
    }

    /// The heat word appears only when the Mac is warm or hot; otherwise the line is about what needs watching.
    var status: String {
        let n = shownCards.filter { $0.needsLook || ($0.heatCause && !watcher.isCooled($0)) }.count
            + watcher.syncPauses.filter { $0.until <= Date() }.count                    // syncing to resume
        let stuck = shownCards.filter { $0.card.state == .stalled }.count
        // the calm memory card is no job (see MemoryAdvice: Chrome using the most while the Mac keeps up)
        let jobs = shownCards.filter { ($0.card.state == .working || $0.card.state == .starting) && !$0.id.hasPrefix("memory") }.count
        var watch: String?
        if stuck > 0 { watch = "\(stuck) looks stuck" + (n > stuck ? ", \(n - stuck) to watch" : "") }
        else if n > 0 { watch = "\(n) to watch" }
        let heat: String? = ["serious": "Running hot", "critical": "Running hot", "fair": "Running warm"][RunningStrip.snapshotThermal ?? watcher.mac.thermal]
        switch (heat, watch) {
        case let (h?, w?): return "\(h) · \(w)"
        case let (nil, w?): return w.prefix(1).uppercased() + w.dropFirst()
        case let (h?, nil): return jobs > 0 ? "\(h) · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running" : h
        default: return jobs > 0 ? "All calm · \(jobs == 1 ? "1 job" : "\(jobs) jobs") running" : "All calm"
        }
    }

}

/// Over each group of options: what pressing one means, in words, once for the group.
struct GroupHeading: View {
    let doer: Fix.Doer
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: doer == .coolHead ? "bolt.fill" : "hand.point.up.left.fill")
            Text(doer == .coolHead ? "ONE CLICK" : "DO IT YOURSELF").fontWeight(.bold).tracking(0.5)
            Text(doer == .coolHead ? "Cool Head does it for you" : "Cool Head takes you there and shows how").foregroundStyle(Ink.muted)
        }
        .font(.caption)
        .foregroundStyle(Ink.text)
    }
}

/// One thing open at a time in the middle: a card, or Managed by Cool Head. Opening one closes the other, so the panel
/// rarely needs to scroll.
final class PanelFocus: ObservableObject {
    static let shared = PanelFocus()
    /// The open card's id, or `onHold`; nil when everything is closed. Managed by Cool Head starts open, and opens
    /// again whenever nothing else is: each time the panel opens, and when the last tool or Settings closes, since that
    /// saves a click and shows more with nothing else using the room. Folding a card doesn't open it, so the cards
    /// don't move from under the pointer just after a click. Screenshots that open the first card
    /// (COOLHEAD_SNAPSHOT_OPEN) start with it folded, unless COOLHEAD_SNAPSHOT_ONHOLD_OPEN is set.
    @Published var open: String? = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ONHOLD_OPEN"] != nil
        || !PanelFocus.snapshotCard ? PanelFocus.onHold : nil
    static let onHold = "on-hold"
    /// Counts the panel's openings, so the frost is drawn fresh each time it opens.
    @Published var opened = 0
    /// Screenshots open the first card (COOLHEAD_SNAPSHOT_OPEN), unless Managed by Cool Head is shown open.
    static let snapshotCard = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_OPEN"] != nil
    /// Screenshots open the option groups too (COOLHEAD_SNAPSHOT_GROUPS=one-click or you).
    static let snapshotGroup = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_GROUPS"]
    func toggle(_ id: String) { withAnimation(.easeOut(duration: 0.15)) { open = open == id ? nil : id } }
    /// A tool opening folds Managed by Cool Head, and opening the section closes the tool, as one tool closes another,
    /// so the section and a tool are never open at once.
    func foldSection() { if open == PanelFocus.onHold { open = nil } }
    /// Opens Managed by Cool Head if nothing else is open: a card left open while a tool was shown stays open.
    func openSection() { if open == nil { withAnimation(.easeOut(duration: 0.15)) { open = PanelFocus.onHold } } }
}

/// What's typed in Report a problem, and what's picked, kept while the form closes, the panel closes, or another tool
/// opens, until the report is sent or Cancel is pressed, so a stray click or close doesn't lose what was written. In
/// memory only, like the activity it's sent with; quitting
/// Cool Head drops it.
final class ReportDraft: ObservableObject {
    static let shared = ReportDraft()
    @Published var kind = ProblemReport.kinds[0]
    @Published var words = ""
    /// A few words for the issue's title (see ProblemReport.title).
    @Published var summary = ""
    /// What went wrong with a managed item the report is about (see ProblemReport.heldProblems).
    @Published var heldProblem = ProblemReport.heldProblems[0]
    @Published var about: String?
    func clear() { kind = ProblemReport.kinds[0]; words = ""; summary = ""; heldProblem = ProblemReport.heldProblems[0]; about = nil }
}

/// A group of options folded to one line with how many it holds; a click opens it. Only the one recommended action
/// stays out of the groups, always shown.
struct GroupBar: View {
    let doer: Fix.Doer
    let count: Int
    /// A recommendation is shown above the groups, so every group holds more, and both groups say "more" the same way,
    /// which is clearer.
    let more: Bool
    let open: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: doer == .coolHead ? "bolt.fill" : "hand.point.up.left.fill")
                Text(doer == .coolHead ? "ONE CLICK" : "DO IT YOURSELF").fontWeight(.bold).tracking(0.5)
                Text("\(count)\(more ? " more" : "") option\(count == 1 ? "" : "s")").foregroundStyle(Ink.muted)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Ink.muted)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .font(.caption)
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(doer == .coolHead ? "One click" : "Do it yourself"): \(count)\(more ? " more" : "") option\(count == 1 ? "" : "s")")
        .accessibilityValue(open ? "shown" : "hidden")
    }
}

struct CardView: View {
    let live: LiveCard
    let watcher: Watcher
    @ObservedObject private var focus = PanelFocus.shared
    var open: Bool { focus.open == live.id }
    /// The option group that's open, one at a time; the recommendation is always shown.
    @State private var shownGroup: Fix.Doer? = PanelFocus.snapshotGroup.map { $0 == "you" ? .you : .coolHead }
    @State private var facts = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_FACTS"] != nil  // screenshots show it open
    @State private var confirmStop: Fix?
    @State private var note: String?          // what happened after a button, when it didn't simply work
    @State private var noteFor: String?       // the option it's about, so it shows right under that button
    @State private var copiedFacts = false
    @State private var noteFailed = false      // the note reports a failure (orange, with a way to report it)
    // Once an option has done something, the options give way to what was done, so nothing sits there to press again.
    // They're worked out afresh the next time the panel opens.
    @State private var acted = false
    @State private var sharing = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SHARE"] != nil  // screenshots

    /// The options in two groups: what Cool Head does in one click, then what you do, with Cool Head taking you there
    /// or showing the steps; one click comes first, since it's the least effort. Each group keeps the card's order: the
    /// recommendation, then what does most about the problem.
    var groups: [(Fix.Doer, [Fix])] {
        [Fix.Doer.coolHead, .you].compactMap { d in
            let fs = live.card.fixes.filter { $0.doer == d }
            return fs.isEmpty ? nil : (d, fs)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(live.card.headline)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // waiting is a reminder, not an option: hide the card for a while; it comes back sooner if it gets worse
                Menu {
                    Text("Check back in…")
                    ForEach([(10, "10 minutes"), (30, "30 minutes"), (60, "1 hour")], id: \.0) { m, label in
                        Button(label) { watcher.snooze(live, until: Date().addingTimeInterval(Double(m) * 60)) }
                    }
                    if live.trustKey != nil {
                        Divider()
                        if Trust.contains(live.trustKey) {
                            Button("Stop trusting \(live.trustName)") { watcher.setTrusted(live, false) }
                        } else {
                            Button("Always trust \(live.trustName)") { watcher.setTrusted(live, true) }
                        }
                    }
                } label: { Image(systemName: "clock").foregroundStyle(Ink.muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Check back later")
                .accessibilityLabel("Check back later")
            }
            if let t = live.trustNote {
                Label(t, systemImage: live.trusted ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(live.trusted ? Ink.muted : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canOpen && !open {
                // a warning offers fixes; a calm card only explains, with options if you want them anyway. Worth
                // watching (stuck, unexplained, or a cause of heat you can act on) says Explore fixes, in orange. A
                // click anywhere on the card opens it and another closes it; this label says so in words with an arrow
                // pointing the way it opens, and is itself a button for the keyboard and VoiceOver.
                let watch = live.needsLook || (live.heatCause && !watcher.isCooled(live))
                Disclosure(title: watch ? "Explore fixes" : "Learn more", open: open, tint: watch ? .orange : Ink.accentText) { toggle() }
            }
            if open {
                if !live.card.explanation.isEmpty {
                    Text(live.card.explanation)
                        .font(.callout).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if acted {
                        noteView
                    } else {
                        let rec = live.card.fixes.first { $0.recommended }
                        if let rec { row(rec) }
                        ForEach(groups, id: \.0) { doer, fixes in
                            let rest = fixes.filter { $0.id != rec?.id }
                            if !rest.isEmpty {
                                GroupBar(doer: doer, count: rest.count, more: rec != nil, open: shownGroup == doer) {
                                    withAnimation(.easeOut(duration: 0.15)) { shownGroup = shownGroup == doer ? nil : doer }
                                }
                                if shownGroup == doer { ForEach(rest) { row($0) } }
                            }
                        }
                        // an option that's no longer listed (the card changed): the note goes at the end
                        if note != nil, !live.card.fixes.contains(where: { $0.id == noteFor }) { noteView }
                    }
                }
                if sharing, let r = live.report { ShareView(title: r.title, report: r.body) { sharing = false } }
                // the whole line opens it, not just the arrow
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(facts ? 90 : 0))
                    Text("Nerdy stuff (detailed info)").font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { facts.toggle() } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(facts ? "Hide the nerdy stuff" : "Show the nerdy stuff")
                // open, the details are a little terminal with its copy button in the title bar; folded, no copy
                // button, since there's nothing shown to copy
                if facts {
                    TerminalPane(lines: live.details, copied: copiedFacts) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(live.details.joined(separator: "\n"), forType: .string)
                        copiedFacts = true
                    }
                    .onTapGesture {}              // selecting text here doesn't close the card
                }
                // the same color as the label that opened it, apart from Nerdy stuff by a line and space, so the two
                // aren't mistaken for each other; close together and styled alike, they were hard to click apart
                let watch = live.needsLook || (live.heatCause && !watcher.isCooled(live))
                Divider().padding(.top, 4)
                Disclosure(title: "Show less", open: open, tint: watch ? .orange : Ink.accentText) { toggle() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { toggle() }
        .onAppear { if PanelFocus.snapshotCard, focus.open == nil, canOpen { focus.open = live.id } }
        .hoverHighlight(canOpen)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
        .confirmationDialog(stopTitle, isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } })) {
            Button(confirmStop?.title ?? "Stop it", role: .destructive) {
                if case .stopAndTrash(let paths, let plist) = confirmStop?.kind {
                    show(watcher.stopAndTrash(live, paths: paths, launchItem: plist))
                } else if case .deleteBuildData(let folder) = confirmStop?.kind {
                    show(watcher.deleteBuildData(folder))
                } else if case .stopAgent(let label, let plist) = confirmStop?.kind {
                    let ok = watcher.turnOffAgent(label: label, plist: plist)
                    show(ok ? .done("Turned off. It won't start by itself, even after a restart. Turn it back on from the top of this panel.")
                            : .failed("macOS didn't turn it off"))
                } else {
                    show(confirmStop?.kind == .forceQuit ? watcher.forceQuit(live) : watcher.stop(live))
                }
                confirmStop = nil
            }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text(ui: confirmStop?.consequence ?? "")
        }
    }

    var canOpen: Bool { !live.card.fixes.isEmpty || !live.card.explanation.isEmpty }
    func toggle() { if canOpen { focus.toggle(live.id) } }

    /// One option, with what happened under it once pressed.
    @ViewBuilder func row(_ f: Fix) -> some View {
        FixRow(fix: f, cooled: watcher.isCooled(live), betterThanRecommended: live.card.betterThanRecommended.contains { $0.id == f.id },
               run: { act($0) }, runUntil: { act($0, until: $1) })
        if noteFor == f.id { noteView }
    }

    /// What a button did, in green (or orange when it didn't work), right under the button pressed.
    @ViewBuilder var noteView: some View {
        if let n = note {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: noteFailed ? "exclamationmark.circle" : "checkmark.circle")
                Text(ui: n).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(noteFailed ? Color.orange : Color.green)
            if noteFailed {
                Button("Report a problem") { watcher.showReport = true }.buttonStyle(.link).font(.callout)
            }
        }
    }

    /// Names the process, so the person knows exactly what they are stopping.
    var stopTitle: String {
        // a browser tab or extension: say exactly that, not "Stop Google Chrome?"
        if let t = confirmStop?.title, t != "Stop it" { return t + "?" }
        let s = live.displaySubject
        guard !s.isEmpty else { return "Stop this process?" }
        return "Stop " + (s.hasPrefix("Your ") ? "your " + s.dropFirst(5) : s) + "?"
    }

    func show(_ o: Watcher.Outcome) {
        switch o {
        case .done(let what): note = what; noteFailed = false; acted = true
        case .gone: note = "It already finished, so nothing was done."; noteFailed = false; acted = true
        case .failed(let why): note = "That didn't work: \(why)."; noteFailed = true
        }
    }

    func act(_ fix: Fix, until: Date? = nil) {
        noteFor = fix.id
        switch fix.kind {
        case .pauseJob:
            show(watcher.pauseJob(live))
        case .pauseSync(let bundle, let name):
            // Cool Head can't pause a sync app itself: it opens it, and reminds you to resume (saved, so it survives a restart)
            guard let until else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            watcher.addSyncPause(name: name, bundle: bundle, until: until)
            note = "Opened \(name). Pause it from its menu bar icon. We'll remind you to resume at \(Fmt.time(until))."; noteFailed = false; acted = true
        case .wait(let until):
            watcher.snooze(live, until: until)
        // Stop and Force Quit warn about unsaved work on the option itself before this runs (see FixRow)
        case .stop:
            show(watcher.stop(live))
        case .forceQuit:
            show(watcher.forceQuit(live))
        case .stopAgent, .stopAndTrash, .deleteBuildData:
            confirmStop = fix
        case .chromeCompanion(let action):
            if action == "setup" {
                // the one file Chrome needs to start Cool Head's helper for the extension, then how to add the extension
                let ok = ChromeCompanion.installHostFile()
                NSWorkspace.shared.open(URL(string: ChromeCompanion.getPage)!)
                note = ok ? "Set up. Add \(ChromeCompanion.name) to Chrome from the page that opened; it links to Cool Head by itself."
                          : "That didn't work: Cool Head couldn't write Chrome's file for its helper."
                noteFailed = !ok; acted = ok
                watcher.log("Set up Cool Head for Chrome pressed: " + (ok ? "done" : "failed"))
            } else if let a = ChromeLink.Action(rawValue: action) {
                // asked of the extension, which says what it did (see ChromeLinkServer)
                note = "Asked \(ChromeCompanion.name)."; noteFailed = false; acted = true
                Task {
                    let r = await withCheckedContinuation { c in ChromeLinkServer.shared.request(a) { c.resume(returning: $0) } }
                    note = r.map { $0.done } ?? "\(ChromeCompanion.name) didn't answer. Is Chrome open?"
                    noteFailed = r?.ok != true; acted = r?.ok == true
                }
            }
        case .unloadModels(let names):
            show(watcher.unloadModels(names))
        case .keepOutOfBackup(let path):
            let ok = watcher.keepOutOfBackup(path)
            let name = (path as NSString).lastPathComponent
            note = ok ? "Time Machine now skips \(name). Back it up again from the top of this panel." : "That didn't work: Time Machine's setting for \(name) didn't change."
            noteFailed = !ok; acted = ok
        case .resume:
            show(watcher.resumeStopped(live))
        case .lookUp(let name):
            watcher.log("Look it up pressed for \(live.reportSubject)")
            // only the process name is searched for: no paths, nothing about this Mac
            var u = URLComponents(string: "https://duckduckgo.com/")!
            // a stuck process is searched for as stuck, not as busy
            u.queryItems = [URLQueryItem(name: "q", value: "macOS \(name) " + (live.id.hasPrefix("hang-") ? "stuck not responding" : "high CPU"))]
            if let url = u.url { NSWorkspace.shared.open(url) }
        case .cooler:
            // background priority: macOS runs it on the efficiency cores and slows its disk use; checked and undoable
            show(watcher.setCooler(live, on: !watcher.isCooled(live)))
        case .quitApp(let bundle):
            // found by where the app is installed, not by its display name (which can differ, or be shared)
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == bundle }) {
                let ok = app.terminate()
                let name = app.localizedName ?? "The app"
                if ok { note = "Asked \(name) to quit. If anything is unsaved, it asks you first."; noteFailed = false; acted = true }
                else { note = "\(name) didn't quit. It may be asking you something."; noteFailed = true }
                watcher.log("Quit pressed for \(live.reportSubject): " + (ok ? "asked to quit" : "didn't quit"))
            } else { note = "It's already closed."; noteFailed = false; acted = true }
        case .restartBrowser(let bundle):
            // a normal quit (so it can ask about downloads), up to 20 seconds for it to close, then reopened with its
            // last session; the waiting happens off the main thread, and the note says how it went
            let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            note = "Asked \(name) to quit. It reopens with your tabs once it has closed."; noteFailed = false; acted = true
            // Set Memory Saver to Maximum: written while Chrome is closed (see ChromeMemorySaver)
            let saver = fix.id == "saver-max"
            let wrote = SaverResult()
            var whileClosed: (@Sendable () -> Void)? = nil
            if saver { whileClosed = { SaverResult.write(into: wrote) } }
            Task {
                let w = watcher
                let o = await BrowserRestart.restart(bundle: bundle, whileClosed: whileClosed, log: { step in w.log("Restart \(name) pressed: \(step)") })
                var n = BrowserRestart.note(o, name: name)
                if saver, !n.failed {
                    if wrote.value == .set { n.text += " Memory Saver is now at Maximum; change it any time in Chrome's Performance settings." }
                    else { n.text += " Memory Saver didn't change, since Chrome's settings couldn't be written safely; set it in Chrome's Performance settings."; n.failed = true }
                    let result = wrote.value.map { "\($0)" } ?? "not run"
                    w.log("Memory Saver at Maximum: " + result)
                }
                note = n.text; noteFailed = n.failed; acted = !n.failed
                // the panel may have closed while the browser came to the front: a failure is also a notification
                if n.failed { Alerts.remind(n.text) }
            }
        case .restartApp(let bundle):
            // the same quit, wait and reopen as a browser, without the browser's switch: the app reopens what it keeps
            let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            note = "Asked \(name) to quit. It opens again once it has closed."; noteFailed = false; acted = true
            Task {
                let w = watcher
                let o = await BrowserRestart.restart(bundle: bundle, arguments: [], log: { step in w.log("Quit and reopen \(name) pressed: \(step)") })
                let n: (text: String, failed: Bool) = {
                    if case .restarted = o { return ("Reopened \(name). The memory it had built up is free.", false) }
                    if case .stillOpen = o { return ("\(name) is still open after \(Int(BrowserRestart.wait)) seconds, so it wasn't reopened. It may be asking you something.", true) }
                    if case .reopenFailed(let why) = o { return ("\(name) closed but didn't reopen: \(why). Open it again from Applications.", true) }
                    return BrowserRestart.note(o, name: name)
                }()
                note = n.text; noteFailed = n.failed; acted = !n.failed
                if n.failed { Alerts.remind(n.text) }
            }
        case .share:
            if !sharing { watcher.log("Share this case opened for \(live.reportSubject)") }
            withAnimation(.easeOut(duration: 0.15)) { sharing.toggle() }
        case .openPage(_, let address) where address.hasPrefix("x-apple.systempreferences:"):
            // System Settings opens its own pages from another app; it has no address bar to paste into (Command-L does
            // nothing there)
            let ok = URL(string: address).map { NSWorkspace.shared.open($0) } ?? false
            note = ok ? "Opened System Settings." : "That didn't work: System Settings didn't open."
            noteFailed = !ok; acted = ok
            watcher.log("Opened a System Settings page for \(live.reportSubject): " + (ok ? "opened" : "failed"))
        case .openPage(let bundle, let address):
            // Chrome refuses chrome:// addresses opened from another app (Chromium's url_util.cc allows only one), so the
            // address is copied and the browser brought forward, with the keys to press. Nothing changes until the
            // person switches something on that page.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            note = "Copied the address and opened \(app). There, press ⌘L, then ⌘V, then Return."; noteFailed = false; acted = true
            watcher.log("Copied a settings address for \(live.reportSubject)")
        case .openApp(let bundle, let steps):
            // what Cool Head can't do itself: it opens the app where it's done, and says how
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundle), configuration: NSWorkspace.OpenConfiguration())
            let app = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            note = "Opened \(app). \(steps)"; noteFailed = false; acted = true
            watcher.log("Opened an app to help with \(live.reportSubject)")
        case .reveal(let path, let steps):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            note = "Showed \((path as NSString).lastPathComponent) in Finder. \(steps)"; noteFailed = false; acted = true
            watcher.log("Showed a folder in Finder for \(live.reportSubject)")
        case .guide:
            break              // the steps open under the option itself (FixRow)
        }
    }
}

/// Exactly what would be shared, before anything happens. Opening it in GitHub is the person's choice, and they
/// can still edit or abandon the issue there; Cool Head sends nothing itself.
struct ShareView: View {
    let title: String
    let report: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is everything we'd share:")
                .font(.caption.weight(.semibold))
            ScrollView {
                Text(report.replacingOccurrences(of: "**", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(8)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button("Open in GitHub") {
                    if let u = CaseReport.issueURL(title: title, report: report) { NSWorkspace.shared.open(u) }
                    done()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(title)\n\n\(report)", forType: .string)
                    copied = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Cancel", action: done).buttonStyle(.plain).font(.caption).foregroundStyle(Ink.muted)
            }
            Text("Nothing is posted until you press Submit on GitHub. No GitHub account? Use Copy.")
                .font(.caption2).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// "Report a problem": what kind, what happened in the person's words, and the full report shown before anything
/// leaves. Open in GitHub sends it to GitHub in the link and opens the form there; Copy keeps it on the Mac.
struct ProblemView: View {
    let watcher: Watcher
    @ObservedObject private var draft = ReportDraft.shared
    @State private var copied = false

    /// Opened from Report a problem under what Cool Head is holding back: the form opens in that section, under the
    /// button, with no title of its own, and closes with `close`.
    var inline = false
    var close: (() -> Void)? = nil
    /// Which of the things held back caused it: asked first whenever something is held back, since that's what a report
    /// about a hold most needs to say. Opened from under them, the first is picked to start; opened from the tools,
    /// None of these is, so a report isn't pinned on a hold by default.
    static let somethingElse = "None of these"
    var freezes: [String] { FrozenItem.all(watcher).map(\.line) }
    var pick: String {
        if let about = draft.about, about == ProblemView.somethingElse || freezes.contains(about) { return about }
        return inline ? (freezes.first ?? ProblemView.somethingElse) : ProblemView.somethingElse
    }
    /// Sent or cancelled: the draft goes, and the form closes.
    func finish() { draft.clear(); if let close { close() } else { watcher.showReport = false } }
    /// Screenshots can show the first choice open (COOLHEAD_SNAPSHOT_CHOICE_OPEN).
    static let choiceOpen = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CHOICE_OPEN"] != nil
    /// The hold it's about, if one was picked; then a fix caused the trouble, so that isn't asked.
    var chosen: String? { freezes.isEmpty || pick == ProblemView.somethingElse ? nil : pick }
    var problem: String { chosen == nil ? draft.kind : ProblemReport.kinds[0] }
    /// The picked hold as the report says it (see `FrozenItem.reportLine`).
    var chosenForReport: String? { chosenItem?.reportLine }
    var chosenItem: FrozenItem? { chosen.flatMap { c in FrozenItem.all(watcher).first { $0.line == c } } }
    /// About a managed item, the few words are asked only for Something else.
    var asksSummary: Bool { chosen == nil || draft.heldProblem == ProblemReport.heldProblems.last }

    /// The issue's title: about a managed item, what Cool Head did and what went wrong ("Problem: Chrome's memory
    /// limit caused an app to crash or quit"); otherwise the person's few words.
    var issueTitle: String {
        if let item = chosenItem { return ProblemReport.heldTitle(doing: item.reportDoing, problem: draft.heldProblem, summary: draft.summary) }
        return ProblemReport.title(kind: problem, summary: draft.summary)
    }
    /// Nothing for the title yet: sending waits, so every report has its own title.
    var noSummary: Bool { asksSummary && draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var report: String { ProblemReport.make(kind: problem, words: draft.words, activity: watcher.activity, cards: watcher.cards, mac: watcher.mac, about: chosenForReport,
                                                problem: chosen == nil ? nil : draft.heldProblem) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !inline { Text("Report a problem").font(.body.weight(.semibold)) }
            // each question on its own line, its choices in a field under it that opens in place
            if !freezes.isEmpty {
                Text("Which of these caused it?").font(.callout.weight(.medium))
                SelectField(options: freezes + [ProblemView.somethingElse], selection: Binding(get: { pick }, set: { draft.about = $0 }),
                            open: ProblemView.choiceOpen)
            }
            if chosen == nil {
                Text("What went wrong?").font(.callout.weight(.medium))
                SelectField(options: ProblemReport.kinds, selection: $draft.kind, open: ProblemView.choiceOpen && freezes.isEmpty)
            } else {
                Text("What went wrong?").font(.callout.weight(.medium))
                SelectField(options: ProblemReport.heldProblems, selection: $draft.heldProblem, open: false)
            }
            // the issue's title, so no two reports share one; sending waits for at least a word. Any number of words, up
            // to the limit, with the count in the field's corner; about a managed item, only for Something else
            if asksSummary {
            Text("In a few words, what happened?").font(.callout.weight(.medium))
            TextField("For example: Chrome's limit didn't lift", text: $draft.summary)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(6).padding(.trailing, 44)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.edge, lineWidth: 1))
                .overlay(alignment: .trailing) {
                    let n = draft.summary.count, limit = ProblemReport.summaryLimit
                    Text("\(n)/\(limit)").font(.caption2).monospacedDigit()
                        .foregroundStyle(n >= limit ? Color.orange : Ink.muted)
                        .padding(.trailing, 8)
                        .accessibilityLabel("\(n) of \(limit) characters")
                }
                .onChange(of: draft.summary) {
                    if draft.summary.count > ProblemReport.summaryLimit { draft.summary = String(draft.summary.prefix(ProblemReport.summaryLimit)) }
                }
            }
            Text("Tell us more (optional). It's public, so skip anything private.")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft.words)
                .font(.callout)
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.edge, lineWidth: 1))
            Text("We'll also send what Cool Head did lately:")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(report.replacingOccurrences(of: "**", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Ink.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 130)
            .padding(8)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button("Open in GitHub") {
                    watcher.log("Report a problem sent to GitHub")
                    if let u = ProblemReport.issueURL(title: issueTitle, words: draft.words, report: report) { NSWorkspace.shared.open(u) }
                    finish()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(noSummary)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(issueTitle)\n\n\(draft.words)\n\n\(report)", forType: .string)
                    copied = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(noSummary)
                Button("Cancel") { finish() }.buttonStyle(.plain).font(.callout).foregroundStyle(Ink.muted)
            }
            Text("Nothing is posted until you press Submit on GitHub. No GitHub account? Use Copy.")
                .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(inline ? 4 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inline ? Color.clear : Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(inline ? Color.clear : Ink.edge, lineWidth: 1))
    }
}

/// What's new in this version, shown once after an update that brought something worth telling.
struct WhatsNewCard: View {
    let notes: [String]
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What's new in \(CoolHead.version)", systemImage: "sparkles").font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(notes, id: \.self) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Ink.muted)
                        Text(n).font(.callout).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Got it", action: done).buttonStyle(.borderedProminent).controlSize(.small)
                Button("All notes") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ThePhilDiamond/CoolHead/blob/main/CHANGELOG.md")!)
                }
                .buttonStyle(.link).font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }
}

/// The notes the app shows after updating: only versions worth telling about have an entry. They're the short
/// versions of CHANGELOG.md.
enum WhatsNew {
    static let notes: [String: [String]] = [
        "0.18.0": [
            "The recommended option is easier to read: a deeper blue with full-strength white text, in light and dark.",
            "Cool Head for Chrome installed from the Chrome Web Store links with Cool Head too. If you set it up before, the link updates by itself.",
        ],
        "0.17.0": [
            "A new icon: Cool Head's own melting snowflake. The Status badge menu bar icon shows it too, with only the badge changing.",
            "Cool Head for Chrome, a free companion extension, puts Chrome tabs you aren't using to sleep. Set it up from Settings.",
            "With it, Chrome's memory card works in one click, and the extension follows Cool Head's reading of your Mac's memory.",
        ],
        "0.16.0": [
            "Cool Head has a color of its own now, Cool Head blue, the same on every Mac and easier to read.",
            "Chrome's memory card says how much is in tabs you aren't looking at and in its extensions, and when a restart would help.",
            "When memory keeps slowing your Mac, Chrome's card can set Memory Saver to Maximum as your own setting.",
            "Limit Chrome is gone: Chrome never applied it on your Mac. Cool Head removes what it set, so Chrome stops saying it's managed.",
        ],
        "0.15.0": [
            "The tools are now This Mac, Power, Network, and Cleaner: the three that show how your Mac is, then the one that changes things.",
            "Battery is now Power. It shows the three apps that used the most energy this week, and a Mac with no battery gets it too.",
            "Hardware is now This Mac, with your Mac's model, serial number, and how much of the disk is free.",
            "With a tool open, a pill at the top such as \"2 fixes recommended\" takes you back to the cards.",
        ],
        "0.14.1": [
            "Trusted is now at the right of the bar, with Report and Settings, since it's Cool Head's own list.",
            "Hardware shows your Mac, drawn as a laptop or a desktop, and Cleaner shows a hard disk with sparkles.",
            "While a network test runs out of sight, orange dashes circle the globe. A poor result is now red.",
        ],
        "0.14.0": [
            "The gauges at the top are off to start, for less to read. To see them, turn on Show usage and temperature in Settings.",
            "A network test keeps running when you open another tool or close the panel. Dashes circle the Network globe until it's done, then it shows the result's mark.",
            "Trends is gone: what used the most energy this week is on the Battery page.",
            "Battery Saver isn't a switch any more: on battery, a really hungry job always gets its card.",
            "Report a problem titles each report from a few words of yours, or from what went wrong with something Cool Head is managing.",
        ],
        "0.13.0": [
            "The gauges at the top are grouped under Usage and Temperature, and the temperature ring shows the battery or drive when one is nearer its own limit.",
            "Test my network keeps its results for 30 minutes, with the time of the test beside Test again.",
            "Managed by Cool Head is open whenever nothing else is: when the panel opens, and when you close a tool or Settings.",
            "Options that open System Settings, such as Open Battery settings, go straight to the page.",
            "Nerdy stuff opens as a small terminal, with its copy button in the title bar.",
        ],
        "0.12.0": [
            "What Cool Head is slowing, limiting, pausing, or has turned off is now Managed by Cool Head, and each line says what it is without a click.",
            "Cleaner checks any folder you choose for identical copies, and the folders inside it, starting with Downloads.",
            "Trends shows why your Mac woke as one bar split by reason, and says what each line means without a click.",
            "What you type in Report a problem is kept until you send it or press Cancel.",
            "About opens in front of the panel.",
        ],
        "0.11.0": [
            "One thing opens at a time: a card, or Managed by Cool Head, which folds to one line with its count. An open card shows its recommended option, with the others folded below it.",
            "The panel is a little wider, and tall enough for all of Test my network.",
            "Cleaner shows each item's size, checks Downloads for identical copies as part of Quick clean, and folds items under 20 MB into one line.",
            "About and the folder chooser open in front of the panel.",
        ],
        "0.10.0": [
            "Cleaner, the bubbles and sparkles along the bottom, finds what deleted apps left behind and what rebuilds itself, and moves what you choose to the Trash.",
            "When Chrome uses the most memory, its card can turn on Chrome's own memory display, so pointing at a tab shows how much it uses.",
            "Steps that send you somewhere say exactly where to click, with menu items and buttons underlined.",
            "Test my network's tiles have bigger symbols.",
        ],
        "0.9.0": [
            "Settings are in the panel, behind the gear at the right of the toolbar, with the menu bar icon to pick by sight.",
            "The top of the panel shows how your Mac is running, with gauges for the chip, memory, and heat.",
            "Each card says why it recommends what it does, and what that costs, under Nerdy stuff.",
            "Test my network shows your VPN, who looks website names up, and the country websites see you in.",
            "What Cool Head is holding back is one section, Managed by Cool Head, with one Report a problem for all of it.",
        ],
        "0.8.0": [
            "Cards for sleep and power: an app keeping your Mac awake, Low Power Mode left on while it's busy, and a battery that drained while asleep.",
            "A program pretending to be part of macOS says so, and one click moves it to the Trash.",
            "New cards for browser settings you didn't make, an app that keeps crashing, and an app using far more memory than it usually does.",
            "A Hardware tool along the bottom, and how your Mac is running at the top of the panel.",
            "Stop and Force Quit warn that anything unsaved will be lost. Rest the pointer on Caution to see why an option is risky.",
        ],
        "0.7.0": [
            "Options come in two groups: One click, which Cool Head does for you, then Do it yourself. Risky ones say Caution.",
            "Tools along the bottom: Test my network and Battery, each with its own page, and Trends for the past week's energy use.",
            "Hardware checks with no password: the drive, the battery and charging, crash restarts, and USB-C ports.",
            "The memory card notices memory moved to disk, and a startup disk that's nearly full.",
            "Turn off another app's background helper, or keep a build's output out of Time Machine, in one click.",
        ],
        // 0.6.1 repeats 0.6.0's notes without the Melting Snowflake bar, which 0.6.1 removed: only the newest version's
        // notes are shown, so someone updating from 0.5.0 straight to 0.6.1 still hears what 0.6.0 brought
        "0.6.1": [
            "Every option is a button. What Cool Head can't do itself, it opens or shows you, step by step.",
            "Stuck processes count too: paused, waiting on a drive, or Not Responding.",
            "Restart Chrome, keeping your tabs, to free the memory it builds up.",
            "An app keeping the graphics chip busy gets a card, even when it uses little CPU.",
        ],
        "0.6.0": [
            "Every option is a button. What Cool Head can't do itself, it opens or shows you, step by step.",
            "Stuck processes count too: paused, waiting on a drive, or Not Responding.",
            "Restart Chrome, keeping your tabs, to free the memory it builds up.",
            "An app keeping the graphics chip busy gets a card, even when it uses little CPU.",
            "The Melting Snowflake gets a yellow or red bar when something needs a look.",
        ],
        "0.5.0": [
            "Click anywhere on a card to open it, and again to close it. Each option is a clear button that says what it does.",
            "After an option works, it says what was done, instead of leaving the options to press again.",
            "Anything Cool Head is slowing, pausing, or limiting is one line at the top, with Speed up, Resume, or Remove.",
            "When memory is tight, Limit Chrome sets Chrome's own memory limit.",
        ],
        "0.4.4": [
            "Security software is never stopped or slowed.",
            "Pause syncing for a set time, with a reminder to resume.",
            "On battery, pause a heavy job until you plug in. Nothing is lost. Turn this off from the right-click menu.",
        ],
        "0.4.3": [
            "Chrome without quitting it: slow just the busy tab, turn on Energy Saver, or turn off an extension.",
            "Close just one tab before ever quitting the whole browser.",
        ],
        "0.4.2": [
            "Games are recognised as games, and never slowed down.",
            "While you play, other busy work is offered to run cooler, to leave the game more power.",
        ],
        "0.4.1": [
            "A warm Mac now shows what's warming it, with something to do.",
            "The recommended option comes first and is marked.",
            "Check back later from the clock on any card.",
            "Always trust an app or job from the clock. It's still flagged if it looks stuck, your Mac gets hot, or it runs for 8 hours.",
        ],
        "0.4.0": [
            "Shorter cards: one sentence, then Explore fixes or Learn more.",
            "A green note says what changed after you act.",
            "Things you slow down stay pinned at the top, frosted.",
            "Better memory advice: close heavy tabs, Memory Saver, or quit, with what each costs.",
            "Try the Melting Snowflake icon: right-click the menu bar icon.",
        ],
    ]

    /// Notes for this version, if it's newer than the last version seen and has any.
    static var pending: [String]? {
        guard UserDefaults.standard.bool(forKey: "welcomed") else { return nil }          // new users get the welcome
        let last = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? "0"
        guard Updater.newer(CoolHead.version, than: last) else { return nil }
        guard let n = notes[CoolHead.version] else { markSeen(); return nil }             // nothing worth telling
        return n
    }

    static func markSeen() { UserDefaults.standard.set(CoolHead.version, forKey: "lastSeenVersion") }
}

/// Shown once, on first launch, when the panel opens by itself: Cool Head has no window, and this is where it lives.
struct WelcomeCard: View {
    let done: () -> Void
    @AppStorage("iconStyle") private var iconStyle = "badge"
    @State private var login = LoginItem.on

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "snowflake").font(.title3).foregroundStyle(Ink.accent)
                Text("Cool Head lives up here, in your menu bar.").font(.body.weight(.semibold))
            }
            Text("No window to keep open. It quietly watches your Mac and tells you why it's hot or slow.")
                .font(.callout).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            // the two icons at each level, to pick one by sight; the columns say what each level means, so the
            // welcome shows the icon options before the person has to choose
            Text("Pick your menu bar icon").font(.callout.weight(.medium))
            IconStylePicker(style: $iconStyle)
                .onChange(of: iconStyle) { NotificationCenter.default.post(name: MenuIcon.changed, object: nil) }
            SettingSwitch(title: "Open at login", detail: nil, on: Binding(get: { login }, set: { LoginItem.set($0); login = LoginItem.on }))
            // offered at the start to people who use Chrome, so they find the extension while setting up Cool Head
            if ChromeCompanion.status == .notInstalled { CompanionRow() }
            Text("Click the snowflake to open. Change these and more any time with the gear below.")
                .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: done).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }
}

/// A line at the top of the panel about updates: shown only when there is something to say.
struct UpdateBanner: View {
    let updater = Updater.shared

    var body: some View {
        switch updater.phase {
        case .available(let v):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Ink.accent)
                Text("Cool Head \(v) is available.").font(.callout.weight(.medium))
                Spacer()
                if let page = updater.releasePage {
                    Button("What's new") { NSWorkspace.shared.open(page) }.buttonStyle(.plain).font(.callout).foregroundStyle(Ink.muted)
                }
                Button("Install") { Task { await updater.install() } }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        case .installing, .checking, .upToDate:
            EmptyView()          // the Settings page, beside the version, says these
        case .failed(let why):
            Label(why, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }
}

/// A process running cooler because the person chose it: pinned at the top until it ends or is set back, so it
/// is clear what Cool Head has changed. Reporting a problem with it sits beside it.
/// What opens a card or a line, in words with an arrow pointing the way it opens (down to open, up to close), not an
/// arrow alone, since a chevron in the corner was hard to see and didn't say what it did. A real button, so the
/// keyboard reaches it and VoiceOver reads it as one, with whether it's open; a click anywhere on the card does the
/// same.
struct Disclosure: View {
    let title: String
    let open: Bool
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Open" : "Closed")
        .frame(maxWidth: .infinity)          // centered under the card's text
    }
}

/// The panel's size, as SwiftUI lays it out: its width (wider by the scroll bar's room while the middle scrolls) and its
/// height. The window takes it each time it changes. The hosting controller's `preferredContentSize` was observed for
/// this, but it never reported a change, so after opening, the window followed Auto Layout alone, which could leave it
/// wider than its content once the middle stopped scrolling, with the panel's edge showing at the sides.
@MainActor enum PanelSize {
    static var report: ((CGSize) -> Void)?
}

/// A card or line that opens on a click shows it: a light wash and the pointing-hand cursor under the mouse.
struct HoverHighlight: ViewModifier {
    let on: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(on && hovering ? 0.05 : 0)).allowsHitTesting(false))
            .onHover { h in
                guard on else { return }
                hovering = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension View { func hoverHighlight(_ on: Bool) -> some View { modifier(HoverHighlight(on: on)) } }

/// Something Cool Head is holding back, with its undo: a job running cooler or paused until the Mac is plugged in, a
/// sync app paused, Chrome's memory limit.
enum FrozenItem: Identifiable {
    case cooled(Watcher.CooledItem), paused(PausedJob), sync(SyncPause), chrome(Int), agent(BackgroundAgents.Agent), backup(String)

    static func all(_ w: Watcher) -> [FrozenItem] {
        // a screenshot shows nothing of this Mac's own: with example cards, only made-up lines; limited to some of this
        // Mac's cards, only what Cool Head is doing to those (see COOLHEAD_SNAPSHOT_COOL and _PAUSE)
        if PanelView.sampleSnapshot { return heldBackSamples ? [.agent(Fixture.updaterAgent), .backup(NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData")] : [] }
        if let pids = PanelView.onlyPIDs(w) {
            return w.cooledList.filter { pids.contains($0.pid) }.map { .cooled($0) } + w.pausedJobs.filter { pids.contains($0.pid) }.map { .paused($0) }
        }
        return w.cooledList.map { .cooled($0) } + w.pausedJobs.map { .paused($0) } + w.syncPauses.map { .sync($0) }
            + (w.chromeLimitMB.map { [.chrome($0)] } ?? [])
            + w.agentsOff.map { .agent($0) } + w.backupExcluded.map { .backup($0) }
    }
    /// For screenshots: COOLHEAD_SNAPSHOT_SAMPLES naming "held-back" shows a made-up turned-off helper and a made-up
    /// folder left out of Time Machine, so the lines can be seen without changing anything on this Mac.
    static var heldBackSamples: Bool {
        ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_SAMPLES"]?.split(separator: "|").contains("held-back") ?? false
    }
    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func project(_ path: String) -> String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }

    var id: String {
        switch self {
        case .cooled(let c): return "cooled-" + c.key
        case .paused(let p): return "paused-" + p.key
        case .sync(let s): return "sync-" + s.name
        case .chrome: return "chrome"
        case .agent(let a): return "agent-" + a.label
        case .backup(let p): return "backup-" + p
        }
    }
    var due: Bool { if case .sync(let s) = self { return s.until <= Date() }; return false }
    var icon: String {
        switch self {
        case .cooled: return "tortoise.fill"
        case .paused: return "pause.circle.fill"
        case .sync: return due ? "exclamationmark.circle" : "pause.circle"
        case .chrome: return "memorychip"
        case .agent: return "power.circle"
        case .backup: return "clock.arrow.circlepath"
        }
    }
    var line: String {
        switch self {
        // says what's happening, in the present tense, so a slowed job never reads as frozen or stuck: "Running cooler"
        // beside ice and a restore button looked like a job that had stopped
        case .cooled(let c): return "Slowing \(c.name) to keep your Mac cool"
        case .paused(let p): return "\(p.name) is paused until you plug in"
        case .sync(let s): return due ? "Time to resume \(s.name) syncing" : "\(s.name) syncing is paused"
        case .chrome(let mb): return "Cool Head's \(ChromeLimit.gb(mb)) limit for Chrome is still set"
        case .agent(let a): return a.owner == a.label ? "A background helper is turned off" : "\(a.owner)'s background helper is turned off"
        case .backup(let p): return "Time Machine skips \(FrozenItem.name(p)) in \(FrozenItem.project(p))"
        }
    }
    /// The line as a problem report says it: anonymised as the activity log is, with no file, folder or project names
    /// (the README's promise for reports); the person sees it before anything leaves.
    /// What Cool Head did, as the start of a report's title, anonymised as `reportLine` is: "Chrome's memory limit"
    /// caused an app to crash or quit (see ProblemReport.heldTitle).
    var reportDoing: String {
        switch self {
        case .cooled(let c): return "Running \(c.reportSubject) cooler"
        case .paused(let p): return "Pausing \(p.reportSubject) until plugged in"
        case .sync(let s): return "Pausing \(s.name) syncing"
        case .chrome: return "Chrome's memory limit"
        case .agent(let a): return a.owner == a.label ? "Turning off a background helper" : "Turning off \(a.owner)'s background helper"
        case .backup: return "Skipping a build folder in Time Machine"
        }
    }
    var reportLine: String {
        switch self {
        case .cooled(let c): return "Slowing \(c.reportSubject)"
        case .paused(let p): return "\(p.reportSubject) is paused until you plug in"
        case .backup: return "Time Machine skips a build folder"
        case .sync, .chrome, .agent: return line
        }
    }
    var detail: String {
        switch self {
        case .cooled(let c): return "It's still working, just more slowly, since \(Fmt.time(c.since))."
        case .paused(let p): return "Paused since \(Fmt.time(p.since)). Nothing is lost, and it carries on by itself when you plug in."
        case .sync(let s): return due ? "Resume it from its menu bar icon, then press Resumed."
                                      : "We'll remind you to resume at \(Fmt.time(s.until)). Resume it from its menu bar icon."
        case .chrome: return "Chrome only applies it when an organization manages this Mac, so it does nothing here, and it makes Chrome say it's \u{201C}managed by your organization\u{201D}. Removing it changes nothing else."
        case .agent(let a): return "\(a.label) doesn't start by itself, even after a restart. Turning it back on starts it now if it's set to."
        case .backup(let p): return "It's build output, so it isn't backed up. Backing it up again makes the next backup larger. \((p as NSString).abbreviatingWithTildeInPath)"
        }
    }
    var undo: (title: String, icon: String) {
        switch self {
        case .cooled: return ("Back to full speed", "hare")
        case .paused: return ("Resume now", "play")
        case .sync: return ("I resumed it", "checkmark")
        case .chrome: return ("Remove the limit", "xmark")
        case .agent: return ("Turn it back on", "power")
        case .backup: return ("Back it up again", "arrow.uturn.backward")
        }
    }
    /// The undo, as a button on the line itself, so it's one click and nobody has to work out that the line opens
    /// first. It names what it does, not a general "Restore", in a few words so the line keeps its room.
    /// A sync app can't be resumed from here, so its button says it was.
    var button: String {
        switch self {
        case .cooled: return "Speed up"
        case .paused: return "Resume"
        case .sync: return "I resumed it"
        case .chrome: return "Remove limit"
        case .agent: return "Turn on"
        case .backup: return "Back it up"
        }
    }
}

/// Everything Cool Head is holding back, one line each at the top of the panel, in one frosted frame: a click opens a
/// line for more, with its button to undo it. Undo lives here, never on the Settings page or in the right-click menu.
struct FrozenList: View {
    let watcher: Watcher
    @ObservedObject private var tools = Tools.shared
    /// Folded to one frosted line with a count until clicked, and closed when a card opens, so it takes little room. A
    /// labelled line, not an icon in the top row: these are changes Cool Head made, such as Chrome's limit, which makes
    /// Chrome say it's managed, so they stay easy to notice.
    @ObservedObject private var focus = PanelFocus.shared
    var open: Bool { focus.open == PanelFocus.onHold }
    /// The lines' text in from the frost's sides: inside the section's own margin, a little less than on the panel, so
    /// the words keep the width they had.
    static let inset: CGFloat = 24

    var body: some View {
        let items = FrozenItem.all(watcher)
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Divider().opacity(0.6).padding(.horizontal, FrozenList.inset) }
                // the same margin above the first line and below the last, so the lines sit centered in the frame.
                // The margin is inside each line, so a click anywhere in the frame opens the line it's beside, and the
                // whole area is the target
                FrozenLine(item: item, watcher: watcher, inset: FrozenList.inset, top: i == 0 ? 14 : 0, bottom: i == items.count - 1 ? 14 : 0)
            }
        }
        // one titled section: the frosted lines, then Report a problem, outside the lines but inside the section, whose
        // form opens under it, within the section
        if !open {
            // the words on a dark band, like the lines' own buttons, so they read clearly over the frost; the count on
            // the frost alone was too low in contrast to read
            HStack(spacing: 8) {
                Image(systemName: "snowflake").font(.callout.weight(.semibold))
                FrozenTitle(count: items.count, open: false)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, FrozenList.inset - 8).padding(.vertical, 16)
            .frozen()
            .contentShape(Rectangle())
            .onTapGesture { Tools.closeAll(watcher); focus.toggle(PanelFocus.onHold) }
            .hoverHighlight(true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows what Cool Head is slowing, limiting, pausing, or has turned off")
        } else {
        VStack(alignment: .leading, spacing: 10) {
            FrozenTitle(count: items.count, open: true).padding(.horizontal, 8).padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture { focus.toggle(PanelFocus.onHold) }
            rows.frozen()
            FrozenReportButton(watcher: watcher, count: items.count)
            if tools.reportAboutHeld { ProblemView(watcher: watcher, inline: true) { tools.reportAboutHeld = false } }
        }
        .padding(6)
        // the section takes the frost's colors at its edge, so the button and form read as part of it
        .background(RoundedRectangle(cornerRadius: 13).fill(IceTint.color.opacity(0.12)))
        .background(RoundedRectangle(cornerRadius: 13).fill(Ink.card))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Frozen.ice.opacity(0.55), lineWidth: 1))
        }
    }
}

/// Nerdy stuff, open: the details in a small terminal, green on near-black in light and dark mode alike, with scan
/// lines and a blinking cursor, and the copy button in its title bar: a bit of fun, as Managed by Cool Head has its
/// frost. The dots are dim, so they don't pass for a window's buttons.
struct TerminalPane: View {
    let lines: [String]
    let copied: Bool
    let copy: () -> Void
    @Environment(\.accessibilityReduceMotion) private var still
    static let screen = Color(red: 0.035, green: 0.065, blue: 0.045)
    static let phosphor = Color(red: 0.45, green: 0.95, blue: 0.56)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.16)).frame(width: 7, height: 7) }
                Text("nerdy stuff").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.white.opacity(0.45)).padding(.leading, 4)
                Spacer(minLength: 0)
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "square.on.square")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TerminalPane.phosphor.opacity(0.85))
                .help(copied ? "Copied" : "Copy the details")
                .accessibilityLabel("Copy the details")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { Text($0) }
                // a cursor that blinks, or stays lit with Reduce Motion on
                TimelineView(.periodic(from: .now, by: 0.55)) { t in
                    let lit = still || Int(t.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                    Rectangle().fill(TerminalPane.phosphor).frame(width: 6, height: 11).opacity(lit ? 0.9 : 0)
                }
                .accessibilityHidden(true)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(TerminalPane.phosphor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // faint scan lines, every third point
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.035)))
                        y += 3
                    }
                }
            )
        }
        .background(TerminalPane.screen)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(TerminalPane.phosphor.opacity(0.22), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// The section's title: what these are, and how many, with a chevron that folds or opens it.
struct FrozenTitle: View {
    let count: Int
    var open = true
    var body: some View {
        HStack(spacing: 6) {
            // not "On hold", which could read as turned off when several are only slowed or limited
            Text("Managed by Cool Head").font(.callout.weight(.semibold))
            // folded, the count is dark on white, to read at a glance over the frost
            Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(open ? Ink.text : Color.black)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(open ? Frozen.ice.opacity(0.3) : Color.white.opacity(0.92)))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .foregroundStyle(Ink.text)
        .accessibilityElement(children: .combine)
    }
}

/// One line: its undo as a button on the line, one click, and what it is and since when, always shown: the section is
/// the only thing open, so there's room. Every undo puts things back as they were and can be redone from the card, so
/// it asks nothing first.
struct FrozenLine: View {
    let item: FrozenItem
    let watcher: Watcher
    /// How far the text sits in from the frost's sides.
    var inset: CGFloat = 30
    /// Extra room above and below: the frame's own margin for the first and last line.
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    @State private var failed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.icon).frame(width: 18)
                Text(item.line).font(.callout.weight(.semibold)).lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(item.button) { undo() }
                    .buttonStyle(IceButton()).font(.subheadline)
                    .fixedSize()
                    .help(item.undo.title)
            }
            .foregroundStyle(item.due ? Color.orange : Ink.text)
            Text(item.detail).font(.caption).foregroundStyle(Ink.text.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            if let f = failed { Text(f).font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, inset).padding(.top, 8 + top).padding(.bottom, 8 + bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func undo() {
        switch item {
        case .cooled(let c): if case .failed(let why) = watcher.restore(c) { failed = "That didn't work: \(why)." }
        case .paused(let p): watcher.resumeJob(p, why: "Resume now pressed")
        case .sync(let s): watcher.syncResumed(s.name)
        case .chrome: if !watcher.removeChromeLimit() { failed = "That didn't work: Chrome's settings didn't change." }
        case .agent(let a): if !watcher.turnOnAgent(a) { failed = "That didn't work: macOS didn't turn it back on." }
        case .backup(let p): if !watcher.backUpAgain(p) { failed = "That didn't work: Time Machine's setting didn't change." }
        }
    }
}

/// Report a problem, once, for everything held back, instead of under each line; the form then starts by asking which
/// one, which keeps each line uncluttered. One wide button, text and icon together, not a row: it's related to the
/// lines, but it doesn't read as another thing held back.
struct FrozenReportButton: View {
    let watcher: Watcher
    /// How many things are held back, so one reads "this", not "one of these".
    let count: Int
    @ObservedObject private var tools = Tools.shared
    var body: some View {
        Button {
            let open = !tools.reportAboutHeld
            Tools.closeAll(watcher)
            withAnimation(.easeOut(duration: 0.15)) { tools.reportAboutHeld = open }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble")
                Text(count == 1 ? "Report a problem with this" : "Report a problem with one of these")
                Image(systemName: tools.reportAboutHeld ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(IceButton(tinted: true)).font(.subheadline)
        .accessibilityValue(tools.reportAboutHeld ? "Open" : "Closed")
    }
}

/// A choice as a field that opens in place to a list, the chosen one ticked: cleaner than radio buttons, and every
/// choice shows at once when open, in a more modern style than a column of radio buttons.
struct SelectField: View {
    let options: [String]
    @Binding var selection: String
    @State private var open: Bool
    init(options: [String], selection: Binding<String>, open: Bool = false) {
        self.options = options; _selection = selection; _open = State(initialValue: open)
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        VStack(spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(selection).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Ink.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Divider()
                ForEach(options, id: \.self) { o in
                    Choice(text: o, on: o == selection) {
                        selection = o
                        withAnimation(.easeOut(duration: 0.12)) { open = false }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .font(.callout)
        .foregroundStyle(Ink.text)
        .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(shape.strokeBorder(open ? Ink.accent.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: 1))
        .clipShape(shape)
    }

    struct Choice: View {
        let text: String
        let on: Bool
        let action: () -> Void
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Ink.accent) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.primary.opacity(hovering ? 0.06 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

/// A "frozen" frame for things Cool Head has cooled: frost growing in from the edges, as on a cold window, on an ice
/// tint. No snowflake symbols, which would look like Christmas decorations rather than cold and frozen. All vector
/// lines, drawn from a fixed pattern, so it looks the same every time and costs almost nothing.
struct Frozen: ViewModifier {
    static let ice = Color(red: 0.55, green: 0.82, blue: 1.0)

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(IceTint.color)
                    Frost().clipShape(RoundedRectangle(cornerRadius: 10))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 0.70, green: 0.88, blue: 1.0).opacity(0.9), lineWidth: 1))
    }
}

extension View { func frozen() -> some View { modifier(Frozen()) } }

/// Pale ice blue, deep enough in light mode for white frost to show, and a cool slate in dark mode.
enum IceTint {
    static let color = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.20, green: 0.30, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.56, green: 0.75, blue: 0.94, alpha: 1)
    })
}

/// A button on the frosted frame: a pale backing, so it has better contrast and stands out from the ice instead of
/// blending into it. Lighter under the mouse, darker when pressed.
struct IceButton: ButtonStyle {
    /// Off the frost (Report a problem, under it): the frost's tint and edge, so it reads as part of the same section.
    var tinted = false
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration, tinted: tinted) }
    struct Tile: View {
        let configuration: ButtonStyleConfiguration
        let tinted: Bool
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 6)
            let wash = configuration.isPressed ? 0.5 : hovering ? 0.85 : 0.7
            configuration.label
                .foregroundStyle(Ink.text)
                .padding(.horizontal, 9).padding(.vertical, 3.5)
                .background(shape.fill(tinted ? AnyShapeStyle(IceTint.color.opacity(wash * 0.5)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(wash))))
                .overlay(shape.strokeBorder(tinted ? Frozen.ice.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

/// Frost on a cold window, as people know it: a frosted rim hugging the edges of the glass, thickest in the corners
/// and fading through a soft, uneven inner edge into clear glass, with a few feather-like crystals reaching in and
/// some sparkles. Vector shapes from a fixed pattern, so it never shimmers and costs almost nothing.
struct Frost: View {
    var style = FrostStyle.current
    @ObservedObject private var focus = PanelFocus.shared
    var body: some View {
        // drawn anew whenever the row's size changes: a row that grew as the panel opened kept the frost drawn for its
        // first, shorter size, with its bottom edge across the middle, until On hold was folded and opened again;
        // and each time the panel opens: after closing and reopening it quickly, the frost again stopped short of
        // the row's bottom
        GeometryReader { g in
            frost.id("\(Int(g.size.width))x\(Int(g.size.height))-\(focus.opened)")
        }
    }

    var frost: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var seed: UInt64 = style.seed
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            let phases = (0..<4).map { _ in rnd() * 6.28 }
            // smooth, uneven variation along the edge, 0 to 1
            func wobble(_ s: CGFloat) -> CGFloat {
                // long drifts plus smaller bumps, so the frost line rises and dips along each side
                let v = 0.4 * sin(s * 0.05 + phases[3]) + 0.3 * sin(s * 0.17 + phases[0]) + 0.2 * sin(s * 0.43 + phases[1]) + 0.1 * sin(s * 1.07 + phases[2])
                return (v + 1) / 2
            }
            // closeness to the nearest corner, 1 at the corner, 0 beyond `reach`
            func cornerness(_ x: CGFloat, _ y: CGFloat, reach: CGFloat) -> CGFloat {
                let d = min(hypot(x, y), hypot(w - x, y), hypot(x, h - y), hypot(w - x, h - y))
                return max(0, 1 - d / reach)
            }
            // the inner edge of a frost band: walk round the rectangle, pushing inward by an uneven amount
            func band(base: CGFloat, vary: CGFloat, corner: CGFloat, bottomExtra: CGFloat) -> Path {
                var pts: [CGPoint] = []
                let step: CGFloat = 3
                var s: CGFloat = 0
                func add(_ x: CGFloat, _ y: CGFloat, _ nx: CGFloat, _ ny: CGFloat) {
                    let c = cornerness(x, y, reach: 34)
                    let extra = ny < 0 ? bottomExtra : 0                    // frost settles thicker at the bottom
                    let d = base + vary * wobble(s) + corner * c * c + extra
                    pts.append(CGPoint(x: x + nx * d, y: y + ny * d))
                    s += step
                }
                var x: CGFloat = 0, y: CGFloat = 0
                while x < w { add(x, 0, 0, 1); x += step }
                while y < h { add(w, y, -1, 0); y += step }
                while x > 0 { add(x, h, 0, -1); x -= step }
                while y > 0 { add(0, y, 1, 0); y -= step }
                var p = Path(CGRect(origin: .zero, size: size))
                // a smooth curve through the midpoints, so the edge is soft rather than jagged
                guard pts.count > 2 else { return p }
                let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
                p.move(to: mid(pts[pts.count - 1], pts[0]))
                for i in 0..<pts.count { p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % pts.count]), control: pts[i]) }
                p.closeSubpath()
                return p
            }
            let even = FillStyle(eoFill: true)
            // blurred, so the frost fades into the glass instead of stepping like a contour map
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(band(base: 8, vary: 11, corner: 24, bottomExtra: 6), with: .color(.white.opacity(0.32)), style: even)   // haze
                layer.fill(band(base: 4, vary: 8, corner: 18, bottomExtra: 3), with: .color(.white.opacity(0.5)), style: even)
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.8))
                layer.fill(band(base: 2, vary: 6, corner: 12, bottomExtra: 2), with: .color(.white.opacity(0.92)), style: even) // the rim
            }

            // fern frost: a gently curving stem with side branches that alternate and shorten toward the tip, each
            // branch feathered with fine barbs, as frost grows across a cold pane
            func feather(_ from: CGPoint, _ angle: CGFloat, _ length: CGFloat, into path: inout Path) {
                let n = max(2, Int(length / 1.4))
                var p = from
                path.move(to: p)
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n)
                    let next = CGPoint(x: p.x + cos(angle) * 1.4, y: p.y + sin(angle) * 1.4)
                    path.addLine(to: next)
                    if i > 0 {
                        let barb = (1 - t) * length * 0.36 + 0.6
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let ba = angle + side * 0.7
                            path.move(to: next)
                            path.addLine(to: CGPoint(x: next.x + cos(ba) * barb, y: next.y + sin(ba) * barb))
                            path.move(to: next)
                        }
                    }
                    p = next
                }
            }
            func fern(from: CGPoint, angle: CGFloat, length: CGFloat, curl: CGFloat, opacity o: Double = 1) {
                var stem = Path(), branches = Path()
                let n = Int(length / 1.6)
                var p = from, a = angle
                stem.move(to: p)
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n)
                    a += curl / CGFloat(n)
                    let next = CGPoint(x: p.x + cos(a) * 1.6, y: p.y + sin(a) * 1.6)
                    stem.addLine(to: next)
                    if i % 2 == 1 && t < 0.94 {
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let len = ((1 - t) * length * 0.4 + 2) * (0.7 + rnd() * 0.3)
                            feather(next, a + side * (0.7 + rnd() * 0.25), len, into: &branches)
                        }
                    }
                    p = next
                }
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 1.4))
                    glow.stroke(branches, with: .color(.white.opacity(0.55 * o)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
                ctx.stroke(branches, with: .color(.white.opacity(0.8 * o)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                ctx.stroke(stem, with: .color(.white.opacity(0.95 * o)), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            }
            // ferns grow all along the edges, more and longer in the corners, and one or two reach further in, as ice
            // builds up most in a window's corners. Placed from the style's own seed, so the pattern looks random but
            // is the same every time it's drawn. The bottom edge keeps its ferns short, where text sits.
            let st = style
            let scale = min(1, h / 90)
            func range(_ r: ClosedRange<CGFloat>) -> CGFloat { r.lowerBound + rnd() * (r.upperBound - r.lowerBound) }
            // along each edge: (start, end, inward angle, whether it's the bottom)
            let edges: [(CGPoint, CGPoint, CGFloat, Bool)] = [
                (CGPoint(x: 0, y: 2), CGPoint(x: w, y: 2), .pi / 2, false),          // top, growing down
                (CGPoint(x: w - 2, y: 0), CGPoint(x: w - 2, y: h), .pi, false),      // right, growing left
                (CGPoint(x: w, y: h - 2), CGPoint(x: 0, y: h - 2), -.pi / 2, true),  // bottom, growing up
                (CGPoint(x: 2, y: h), CGPoint(x: 2, y: 0), 0, false),                // left, growing right
            ]
            for (a, b, inward, bottom) in edges {
                let len = hypot(b.x - a.x, b.y - a.y)
                var d = st.edgeSpacing * rnd()
                while d < len {
                    let t = d / len
                    let corner = min(t, 1 - t) * len < 26
                    if !corner {
                        let pt = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                        // hug the edge: lean well over to one side or the other
                        let lean = (rnd() < 0.5 ? -1 : 1) * (0.5 + rnd() * 0.6)
                        let l = range(st.edgeLength) * (bottom ? 0.6 : 1) * max(scale, 0.6)
                        fern(from: pt, angle: inward + lean, length: l, curl: (rnd() - 0.5) * st.curl)
                    }
                    d += st.edgeSpacing * (0.5 + rnd())
                }
            }
            // the corners, where frost gathers: several ferns fanning out from each
            let q: CGFloat = .pi / 4
            let corners: [(CGFloat, CGFloat, CGFloat)] = [(3, 3, q), (w - 3, 3, 3 * q), (w - 3, h - 3, -3 * q), (3, h - 3, -q)]
            for (cx, cy, diag) in corners {
                for k in 0..<st.cornerFerns {
                    let fan: CGFloat = CGFloat(k) / CGFloat(max(st.cornerFerns - 1, 1)) - 0.5
                    let spread: CGFloat = fan * 1.3 + (rnd() - 0.5) * 0.3
                    fern(from: CGPoint(x: cx + (rnd() - 0.5) * 6, y: cy + (rnd() - 0.5) * 6), angle: diag + spread,
                         length: range(st.cornerLength) * scale, curl: (rnd() - 0.5) * st.curl)
                }
            }
            // one or two that reach further in, from the sides or the top (never the bottom, where text sits)
            for _ in 0..<st.reachers {
                let side = rnd()
                let (pt, inward): (CGPoint, CGFloat) = side < 0.35 ? (CGPoint(x: 2, y: h * (0.2 + rnd() * 0.5)), 0)
                    : side < 0.7 ? (CGPoint(x: w - 2, y: h * (0.2 + rnd() * 0.5)), .pi)
                    : (CGPoint(x: w * (0.15 + rnd() * 0.7), y: 2), .pi / 2)
                let along = (rnd() < 0.5 ? -1 : 1) * (0.35 + rnd() * 0.4)
                fern(from: pt, angle: inward + along, length: st.reachLength * (0.8 + rnd() * 0.4) * max(scale, 0.7), curl: (rnd() - 0.5) * st.curl * 1.5)
            }
            // one or two wild ferns, placed by hand along an edge away from the corners, fading a little so text over
            // them stays readable
            for f in st.wild {
                let (pt, inward): (CGPoint, CGFloat) = switch f.edge {
                case .top: (CGPoint(x: w * f.at, y: 2), .pi / 2)
                case .left: (CGPoint(x: 2, y: h * f.at), 0)
                case .right: (CGPoint(x: w - 2, y: h * f.at), .pi)
                }
                fern(from: pt, angle: inward + f.lean, length: f.length * max(scale, 0.75), curl: f.curl, opacity: 0.75)
            }
            // texture: fine needles and specks of frost scattered through the frosted rim, densest in the corners
            for _ in 0..<st.grain {
                let e = rnd()
                var pt: CGPoint
                let depth = pow(rnd(), 1.6) * 18
                if e < 0.3 { pt = CGPoint(x: rnd() * w, y: 2 + depth) }
                else if e < 0.55 { pt = CGPoint(x: rnd() * w, y: h - 2 - depth * 1.2) }
                else if e < 0.78 { pt = CGPoint(x: 2 + depth, y: rnd() * h) }
                else { pt = CGPoint(x: w - 2 - depth, y: rnd() * h) }
                if rnd() < 0.55 {
                    let a = rnd() * .pi, l = 1.5 + rnd() * 3.5
                    var needle = Path()
                    needle.move(to: CGPoint(x: pt.x - cos(a) * l / 2, y: pt.y - sin(a) * l / 2))
                    needle.addLine(to: CGPoint(x: pt.x + cos(a) * l / 2, y: pt.y + sin(a) * l / 2))
                    ctx.stroke(needle, with: .color(.white.opacity(0.45 + rnd() * 0.35)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                } else {
                    let r = 0.35 + rnd() * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.5 + rnd() * 0.4)))
                }
            }

            // sparkles near the frost: dots, and a few four-pointed glints
            for i in 0..<14 {
                let side = rnd()
                let pt = side < 0.45 ? CGPoint(x: rnd() * w, y: h - 6 - rnd() * 12)
                    : side < 0.6 ? CGPoint(x: rnd() * w, y: 4 + rnd() * 8)
                    : CGPoint(x: side < 0.8 ? 4 + rnd() * 12 : w - 4 - rnd() * 12, y: rnd() * h)
                if i % 7 == 6 {
                    let r = 1.6 + rnd() * 0.8
                    var star = Path()
                    star.move(to: CGPoint(x: pt.x, y: pt.y - r))
                    star.addQuadCurve(to: CGPoint(x: pt.x + r, y: pt.y), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y + r), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x - r, y: pt.y), control: pt)
                    star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y - r), control: pt)
                    ctx.fill(star, with: .color(.white.opacity(0.95)))
                } else {
                    let r = 0.6 + rnd() * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The frost's ferns, as a few numbers, so the pattern can be tuned without redrawing it by hand: how far apart the
/// ferns along the edges are, how long they grow, how many fan out of each corner and how long, how many reach further
/// in, and how much they curl. `seed` picks the random pattern; the same seed draws the same frost every time.
struct FrostStyle {
    var seed: UInt64
    var edgeSpacing: CGFloat
    var edgeLength: ClosedRange<CGFloat>
    var cornerFerns: Int
    var cornerLength: ClosedRange<CGFloat>
    var reachers: Int = 0
    var reachLength: CGFloat = 0
    var curl: CGFloat
    /// Fine needles and specks of frost in the rim: how many.
    var grain = 0
    /// Ferns placed by hand: which edge, how far along it (0 to 1), how far they lean off straight in, how long, and
    /// how much they curl.
    var wild: [Wild] = []
    struct Wild { enum Edge { case top, left, right }; var edge: Edge; var at: CGFloat; var lean: CGFloat; var length: CGFloat; var curl: CGFloat }

    /// The frost in use, chosen from two batches of renders: ferns fanning from the corners, short ones along the
    /// edges, the most texture, and two short wild ferns from the top. Change a number here and render to tune it.
    static let current = FrostStyle(seed: 0x1CE, edgeSpacing: 26, edgeLength: 6...14, cornerFerns: 4, cornerLength: 26...50,
                                    curl: 0.5, grain: 320,
                                    wild: [Wild(edge: .top, at: 0.3, lean: 0.6, length: 46, curl: 0.9),
                                           Wild(edge: .top, at: 0.78, lean: -0.5, length: 40, curl: -0.7)])
}

/// One option: a button with what it would cause underneath. The recommended one stands out.
struct FixRow: View {
    let fix: Fix
    let cooled: Bool
    /// A task that does more about the problem than the recommended option: says "Fixes the cause".
    var betterThanRecommended = false
    /// The label in the option's bottom right corner, small: Caution for what has consequences that can't be undone or
    /// known, or Fixes the cause for a task that does more than the recommendation. Never both: the options that need
    /// Caution are all ones Cool Head does.
    var tag: OptionTag? {
        if fix.caution { return OptionTag(words: "CAUTION", symbol: "exclamationmark.triangle.fill", color: .red) }
        if betterThanRecommended { return OptionTag(words: "FIXES THE CAUSE", symbol: "checkmark.seal.fill", color: .green,
                                                    help: "This does more about the problem than the recommended option, but you do it yourself.") }
        return nil
    }
    let run: (Fix) -> Void

    /// A picture for each kind of option, so the list scans at a glance.
    var icon: String {
        switch fix.kind {
        case .wait: return "clock"
        case .stop: return "stop.circle"
        case .cooler: return cooled ? "hare" : "tortoise"
        case .lookUp: return "magnifyingglass"
        case .quitApp: return "xmark.circle"
        case .share: return "square.and.arrow.up"
        case .openApp: return "arrow.up.forward.app"
        case .reveal: return "folder"
        case .guide: return "list.bullet"
        case .openPage: return "gearshape"
        case .pauseJob: return "pause.circle"
        case .pauseSync: return "pause.circle"
        case .resume: return "play.circle"
        case .forceQuit: return "xmark.octagon"
        case .restartBrowser: return "arrow.clockwise.circle"
        case .restartApp: return "arrow.clockwise.circle"
        case .stopAgent: return "power.circle"
        case .unloadModels: return "memorychip"
        case .chromeCompanion: return "arrow.triangle.2.circlepath"   // the sign that Cool Head and its Chrome extension work together
        case .deleteBuildData: return "trash"
        case .stopAndTrash: return "trash"
        case .keepOutOfBackup: return "clock.arrow.circlepath"
        }
    }
    /// For Pause syncing: how long, before anything happens.
    var runUntil: (Fix, Date) -> Void = { _, _ in }
    @State private var choosing = false
    /// Every Caution option asks twice: the first click shows why it's risky on the option itself, and a second click
    /// within 5 seconds goes ahead; a tooltip on the label was easy to miss. The guard began with Stop and Force Quit,
    /// which end a program at once with no chance to save, so the first click warns that unsaved work will be lost and
    /// gives the person a moment to save first. A normal quit needs no guard: the app asks.
    @State private var armed = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_ARMED"] != nil
    var guarded: Bool { fix.caution }
    /// What the first click says: for Stop and Force Quit, that anything unsaved goes; otherwise why it's Caution.
    var warning: String {
        fix.kind == .stop || fix.kind == .forceQuit ? "Anything unsaved will be lost." : (fix.cautionReason ?? "This can't be undone.")
    }
    var isSyncPause: Bool { if case .pauseSync = fix.kind { return true }; return false }
    /// For an option that shows how: the steps, shown under it once pressed.
    var guideSteps: [String]? { if case .guide(let steps) = fix.kind { return steps }; return nil }
    @State private var showingSteps = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_STEPS"] != nil   // screenshots show the guides
    /// 1 hour, 3 hours, and until 8pm while that is more than an hour away.
    var pauseChoices: [(String, Date)] {
        let now = Date()
        var out: [(String, Date)] = [("1 hour", now.addingTimeInterval(3600)), ("3 hours", now.addingTimeInterval(3 * 3600))]
        if let eight = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: now), eight.timeIntervalSince(now) > 3600 * 3.5 {
            out.append(("Until \(Fmt.time(eight))", eight))
        }
        return out
    }

    /// Opens something outside Cool Head (a web search, an app's settings, a sync app): an arrow out, not along.
    var opensElsewhere: Bool {
        switch fix.kind { case .lookUp, .openPage, .pauseSync, .openApp, .reveal: return true; default: return false }
    }
    /// Risky (see `Fix.caution`): its icon in red, so the risk shows at a glance; quitting an app that loses nothing isn't.
    var ends: Bool { fix.caution }

    /// Once it is already running cooler, "Back to full speed" isn't the recommendation.
    var recommended: Bool { fix.kind == .cooler && cooled ? false : fix.recommended }
    var title: String { fix.kind == .cooler && cooled ? "Back to full speed" : fix.title }
    /// The recommended option Cool Head does itself, filled with blue: its text at full strength, since dimmed white on
    /// blue measured 4.0:1, under the 4.5:1 text needs.
    var filledTile: Bool { recommended && fix.doer == .coolHead }
    var line: String { fix.kind == .cooler && cooled ? "Runs at normal speed again." : fix.consequence }

    // Each option is its own bordered tile, title and what it does inside it, with an arrow at the end: plainly a
    // button, plainly separate from the next, since options that run together don't look clickable. Every option is
    // one: what Cool Head can't do itself opens the app where it's done, or shows the steps right under it.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
                Button {
                    if isSyncPause { withAnimation(.easeOut(duration: 0.15)) { choosing.toggle() } }
                    else if guideSteps != nil { withAnimation(.easeOut(duration: 0.15)) { showingSteps.toggle() } }
                    else if guarded && !armed {
                        withAnimation(.easeOut(duration: 0.15)) { armed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { withAnimation(.easeOut(duration: 0.15)) { armed = false } }
                    }
                    else { armed = false; run(fix) }
                } label: {
                    if guarded && armed {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.body).frame(width: 22)
                                .foregroundStyle(recommended && fix.doer == .coolHead ? Ink.onFill : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Text("Click again to \(title.prefix(1).lowercased() + title.dropFirst()).").font(.callout).opacity(0.8)
                            }
                            Spacer(minLength: 6)
                        }
                    } else {
                    HStack(alignment: tag == nil ? .center : .top, spacing: 10) {
                        Image(systemName: icon).font(.body).frame(width: 22)
                            .foregroundStyle(recommended && fix.doer == .coolHead ? Ink.onFill : ends ? Color.red : Ink.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            // the tag beside the name when both fit on one line, otherwise above it, so a long name
                            // isn't squeezed into three lines beside it
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) {
                                    Text(title).font(.callout.weight(.semibold)).fixedSize()
                                    if recommended { RecommendedTag(onAccent: fix.doer == .coolHead) }
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    if recommended { RecommendedTag(onAccent: fix.doer == .coolHead) }
                                    Text(title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if !line.isEmpty {
                                // the last line keeps room for the corner label, so the label never covers words
                                (Text(ui: line) + (tag.map { OptionTag.room($0.words) } ?? Text("")))
                                    .accessibilityLabel(Fmt.plain(line))
                                    .font(.callout).opacity(filledTile ? 1 : 0.8).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: opensElsewhere ? "arrow.up.right" : (isSyncPause && choosing) || (guideSteps != nil && showingSteps) ? "chevron.down" : "chevron.right")
                            .font(.callout.weight(.bold)).opacity(0.75)
                            .padding(.top, tag == nil ? 0 : 2)          // at the top, clear of the corner label
                            .help(opensElsewhere ? "Opens another app or your browser" : "")
                    }
                    .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(OptionStyle(recommended: recommended, yours: fix.doer == .you, tag: armed ? nil : tag))
                .accessibilityHint(line)
                if choosing {
                    HStack(spacing: 6) {
                        Text("For").font(.callout).foregroundStyle(Ink.muted)
                        ForEach(pauseChoices, id: \.0) { label, until in
                            Button(label) { choosing = false; runUntil(fix, until) }.buttonStyle(.bordered).controlSize(.regular)
                        }
                    }
                    .padding(.leading, 11)
                }
                // the mini-guide, for what Cool Head can't do itself: numbered steps under the option
                if showingSteps, let steps = guideSteps {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(i + 1).").monospacedDigit().foregroundStyle(Ink.muted)
                                Text(ui: step).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout).foregroundStyle(Ink.text)
                    .padding(.horizontal, 11).padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .onTapGesture {}              // reading the steps doesn't close the card
                }
        }
    }
}

/// An option's tile: a filled, bordered, full-width button that lightens under the mouse (with the pointing hand) and
/// darkens when pressed. The recommended one is filled with the accent color, in white.
struct OptionStyle: ButtonStyle {
    let recommended: Bool
    /// A task for you (Cool Head opens the place or shows the steps): an outline with a dashed border and no fill.
    /// What Cool Head does itself stays a filled, solid tile.
    let yours: Bool
    var tag: OptionTag? = nil
    func makeBody(configuration: Configuration) -> some View { OptionTile(configuration: configuration, recommended: recommended, yours: yours, tag: tag) }

    struct OptionTile: View {
        let configuration: ButtonStyleConfiguration
        let recommended: Bool
        let yours: Bool
        let tag: OptionTag?
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9)
            let wash: Double = configuration.isPressed ? 0.22 : hovering ? 0.13 : 0.07
            let line = Color.primary.opacity(hovering ? 0.55 : 0.4)
            let filled = recommended && !yours
            configuration.label
                .foregroundStyle(filled ? Ink.onFill : Ink.text)
                .padding(.horizontal, 11).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(filled ? AnyShapeStyle(Ink.fill.opacity(configuration.isPressed ? 0.85 : 1))
                                       : yours ? AnyShapeStyle(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.05 : 0))
                                       : AnyShapeStyle(Color.primary.opacity(wash))))
                .overlay {
                    if yours {
                        shape.strokeBorder(recommended ? Ink.accent : line, style: StrokeStyle(lineWidth: recommended ? 1.6 : 1.3, dash: [4, 3]))
                    } else {
                        shape.strokeBorder(filled ? Ink.fillEdge : Color.primary.opacity(hovering ? 0.45 : 0.28), lineWidth: 1)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let tag {
                        OptionTag(words: tag.words, symbol: tag.symbol, color: tag.color, onAccent: filled).padding(.trailing, 7).padding(.bottom, 6)
                    }
                }
                .contentShape(shape)
                .onHover { h in
                    hovering = h
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
        }
    }
}

/// The recommended option: filled with the accent color, white text, whether or not the panel is the active window
/// (macOS greys its own prominent buttons in an inactive window).
struct RecommendedButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 6).fill(Ink.accent.opacity(configuration.isPressed ? 0.75 : 1)))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// A small label in an option's bottom right corner, with a symbol, in its color.
struct OptionTag: View {
    let words: String
    let symbol: String
    let color: Color
    /// Why it's there, shown when the pointer rests on it (see `Fix.cautionReason`).
    var help: String? = nil
    var onAccent = false
    static let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(words).tracking(0.5)
        }
        .font(Font(OptionTag.font))
        .foregroundStyle(onAccent ? Ink.onFill : color)
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(Capsule().fill(onAccent ? Color.white.opacity(0.22) : color.opacity(0.13)))
        .fixedSize()
        .help(help ?? "")
    }
    /// Room for the label at the end of the option's last line. The arrow's column already leaves about 49 points clear
    /// at the right of the text; only a label wider than that needs more. The room is invisible letters, not spaces:
    /// spaces at the end of a line hang past its edge instead of moving words down, so they'd let the label cover them.
    static func room(_ words: String) -> Text {
        let width = (words as NSString).size(withAttributes: [.font: font, .kern: 0.5]).width + 10 + 12 + 3   // ends, symbol, gap
        let needed = width + 7 + 4 - 49                                                                     // its inset, and a gap
        guard needed > 0 else { return Text("") }
        let m = ("M" as NSString).size(withAttributes: [.font: NSFont.preferredFont(forTextStyle: .callout)]).width
        return Text(" ") + Text(String(repeating: "M", count: Int((needed / m).rounded(.up)))).foregroundStyle(.clear)
    }
}

/// "Recommended", as a small rounded tag beside the option's name.
struct RecommendedTag: View {
    let onAccent: Bool
    var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.semibold))
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            // on the blue option it's the option's text color with the blue as its text; elsewhere, the blue with that text
            .foregroundStyle(onAccent ? Ink.fill : Ink.onFill)
            .background(Capsule().fill(onAccent ? Ink.onFill : Ink.fill))
    }
}

/// A line-icon button with its tooltip centred above it on hover (the system tooltip appears at the pointer instead).
struct IconButton: View {
    let symbol: String
    let tip: String
    let action: () -> Void
    @State private var hovering = false

    init(symbol: String, tip: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.tip = tip; self.action = action
        // screenshots: COOLHEAD_SNAPSHOT_HOVER names a tooltip to show
        _hovering = State(initialValue: ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_HOVER"] == tip)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Ink.text : Ink.muted)
        .onHover { hovering = $0 }
        .overlay(alignment: .top) {
            if hovering {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(Ink.text)
                    .fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.edge, lineWidth: 1))
                    .offset(y: -26)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(tip)
    }
}

/// Text and surface colors chosen for contrast in both light and dark, instead of macOS's paler secondary greys.
enum Ink {
    /// Main text.
    static let text = Color.primary
    /// Cool Head blue, its own color on every Mac and in its Chrome extension, rather than the Mac's accent color, which
    /// is blue, orange, or another on each Mac and which Chrome hides from extensions, so Cool Head looks the same on
    /// every computer. Light #1769D1, white text on it 5.3:1 and as text on the panel 4.9:1; dark #4A9EFF, near-black
    /// text on it 7.6:1 and as text 6.1:1. A blue also keeps "do this" apart from the yellow, orange, and red that say
    /// "watch out". See docs/BRAND.md.
    static let accent = dynamic(0x1769D1, 0x4A9EFF)
    /// Blue behind text (the recommended option, the Recommended pill): one deep blue with white text in light and dark,
    /// 7.4:1, the stricter AAA level, where the accent with dimmed text measured 4.0:1 and was harder to read.
    static let fill = Color(nsColor: rgb(0x0F52AD))
    static let onFill = Color.white
    /// On a dark card the deep blue stands apart only 1.9:1, so it gets an edge in the accent there (5.1:1).
    static let fillEdge = Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(0x4A9EFF) : .clear })
    /// Text on a filled accent: white in light mode, near-black in dark, where the lighter blue needs it.
    static let onAccent = Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(0x1A1A1A) : .white })
    /// Text in the accent color on the panel.
    static let accentText = accent
    static func rgb(_ h: Int) -> NSColor { NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1) }
    static func dynamic(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light) })
    }
    /// Supporting text: still well above 7:1 contrast on the card in light and dark.
    static let muted = Color.primary.opacity(0.82)
    /// A card: a slightly raised surface with a visible edge.
    static let card = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.19, alpha: 1) : NSColor(white: 0.965, alpha: 1)
    })
    static let edge = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.08)
    })
}

/// The scrolling middle's natural height, so the panel can fit it exactly until it reaches the limit.
struct MiddleHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// What the Memory Saver write returned, from the restart's background thread.
final class SaverResult: @unchecked Sendable {
    var value: ChromeMemorySaver.Write?
    /// Sets Maximum, and notes when, so a person who lowers it again isn't asked for 30 days.
    static func write(into r: SaverResult) {
        r.value = ChromeMemorySaver.setMaximum()
        if r.value == .set { UserDefaults.standard.set(Date(), forKey: ChromeMemorySaver.setKey) }
    }
}

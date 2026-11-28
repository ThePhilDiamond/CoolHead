import AppKit
import CoolHeadCore
import ServiceManagement
import SwiftUI

/// The Cleaner tool's page: a verdict; Quick clean, a list of what nothing uses, done with one button, since nothing in it
/// is needed or has any effect when cleared; Deep clean, a list to choose from, folded, with what rebuilds itself ticked
/// and what Cool Head can't be sure of left for the person to tick. Then what Cool Head moved, to put back, and the two
/// places in System Settings Cool Head can't clear itself, with a button to open each.
struct CleanerView: View {
    let close: () -> Void
    @ObservedObject var model = CleanerModel.shared
    /// Screenshots can show Deep clean's list open (COOLHEAD_SNAPSHOT_CLEANER=open).
    @State private var showDeep = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] == "open"
    /// Which lists have their small items unfolded ("quick", "rebuilds", "check", "moved"); all, in an open screenshot.
    @State private var openSmall: Set<String> = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] == "open"
        ? ["quick", "rebuilds", "check", "moved"] : []
    @State private var showMoved = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] == "open"
    /// Deep clean's ticks the person changed; otherwise what rebuilds itself is ticked and the rest isn't.
    @State private var ticks: [String: Bool] = [:]
    /// The first click on a clean button arms it; a second within 5 seconds goes ahead.
    @State private var armed: String?

    /// In a screenshot, made-up finds (never this Mac's own).
    static let snapshot = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] != nil
    var finds: [Cleaner.Find] { CleanerView.snapshot ? Cleaner.sample() : model.finds }
    var quick: [Cleaner.Find] { finds.filter { $0.group == .quick && $0.blocked == nil } }
    var deep: [Cleaner.Find] { finds.filter { $0.group != .quick } }
    func ticked(_ f: Cleaner.Find) -> Bool { f.blocked == nil && (ticks[f.id] ?? (f.group == .rebuilds)) }
    var deepNow: [Cleaner.Find] { deep.filter(ticked) }
    /// What Cool Head moved: in a screenshot, made-up items.
    var moved: [Cleaner.Moved] { CleanerView.snapshot ? Cleaner.sampleMoved() : model.moved }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text("Cleaner") } icon: { ToolIcon(symbol: HardDisk.name, size: 13) }.font(.body.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            if CleanerView.snapshot {
                Text("Made-up finds, not this Mac's").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if model.scanning && !CleanerView.snapshot {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(Ink.muted) }
            } else {
                let v = Cleaner.verdict(finds)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: finds.isEmpty ? "checkmark.circle.fill" : "sparkles")
                        .font(.title3).foregroundStyle(finds.isEmpty ? Color.green : Ink.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(.callout.weight(.semibold))
                        Text(v.meaning).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let m = CleanerView.snapshot ? "Moved 3 items (272 MB) to the Trash." : model.message { Text(m).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
                quickBox
                if !deep.isEmpty { deepBox }
            }
            if !moved.isEmpty { movedBox }
            Divider()
            // what Cool Head can't see or clear itself: where to do it
            VStack(alignment: .leading, spacing: 10) {
                linkRow(symbol: "hand.raised", title: "Deleted apps in permission lists",
                        detail: "macOS doesn't let apps read these lists. Select the app there and press −.",
                        button: "Open Privacy & Security", url: "x-apple.systempreferences:com.apple.preference.security?Privacy")
                linkRow(symbol: "internaldrive", title: "Large files, iPhone backups, and the Trash",
                        detail: "Apple's Storage settings already sort these by size.",
                        button: "Open Storage", url: "x-apple.systempreferences:com.apple.settings.Storage")
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
        .onAppear { if !CleanerView.snapshot { model.scan() } }
    }

    /// A clean button: the first click asks ("Move 3 items (1.2 GB) to the Trash?"), a second within 5 seconds goes ahead.
    func cleanButton(_ id: String, _ words: String, count: Int, bytes: UInt64, admin: Bool, prominent: Bool, run: @escaping () -> Void) -> some View {
        let isArmed = armed == id
        let label = HStack(spacing: 4) {
            if admin { Image(systemName: "lock.fill").font(.system(size: 9)) }
            Text(isArmed ? "Move \(Cleaner.count(count, bytes: bytes)) to the Trash?" : words).padding(.horizontal, 4)
        }
        let action = {
            if isArmed { armed = nil; run() } else {
                armed = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if armed == id { armed = nil } }
            }
        }
        return Group {
            if prominent {
                Button(action: action) { label }.buttonStyle(.borderedProminent)
                    // drawn as in a key window: a screenshot's window never is, which would grey the main button
                    .environment(\.controlActiveState, .key)
            } else {
                Button(action: action) { label }.buttonStyle(.bordered)
            }
        }
        .controlSize(.regular).fixedSize().disabled(count == 0 || model.working)
        .help(admin ? "macOS asks for an administrator's password for what's in a folder for all users; it runs one command and keeps nothing installed." : "")
    }

    /// Quick clean: each thing it moves, listed, and one button. Nothing in it is used, so there's nothing to choose.
    /// The check for identical copies in a folder is here too, not in Deep clean: the original always stays, so it's quick
    /// and carries no risk.
    var quickBox: some View {
        let bytes = quick.compactMap(\.bytes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Ink.accent).frame(width: 18)
                Text("Quick clean").font(.callout.weight(.semibold))
                Spacer()
                if bytes > 0 { Text(Fmt.fileSize(bytes)).foregroundStyle(Ink.muted) }
            }
            Text(quick.isEmpty ? "Nothing to clear now." : "Nothing uses these, and nothing has to rebuild them.")
                .font(.caption).foregroundStyle(Ink.muted).padding(.leading, 26)
            folding("quick", quick, bytes: \.bytes) { f in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.muted).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(f.title)
                                Spacer(minLength: 8)
                                if let b = f.bytes, b > 0 { Text(Fmt.fileSize(b)).foregroundStyle(Ink.muted) }
                            }
                            Text(f.detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
            } summary: { title, total, _, open in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.muted).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title)
                            Spacer(minLength: 8)
                            if total > 0 { Text(Fmt.fileSize(total)).foregroundStyle(Ink.muted) }
                        }
                        eachOne(open)
                    }
                }
            }
            .padding(.leading, 26)
            if !quick.isEmpty {
                HStack {
                    Spacer()
                    cleanButton("quick", "Quick clean", count: quick.count, bytes: bytes, admin: false, prominent: true) { model.clean(quick, label: "quick clean") }
                }
                .padding(.leading, 26)
            }
            copiesRow.padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Deep clean: what's ticked in a sentence, the list folded under it, and one button for what's ticked.
    var deepBox: some View {
        let bytes = deepNow.compactMap(\.bytes).reduce(0, +)
        let check = deep.filter { $0.group == .check }
        let rebuild = deep.contains { $0.group == .rebuilds }
        let sentence = [rebuild ? "What rebuilds itself is ticked; rebuilding can need the internet." : nil,
                        check.isEmpty ? nil : "What Cool Head can't be sure of isn't: \(Fmt.list(Cleaner.kinds(check)))."]
            .compactMap { $0 }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(Ink.muted).frame(width: 18)
                Text("Deep clean").font(.callout.weight(.semibold))
                Spacer()
                if bytes > 0 { Text(Fmt.fileSize(bytes)).foregroundStyle(Ink.muted) }
            }
            Text(sentence).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
            HStack {
                disclosure(showDeep ? "Hide the list" : "Choose what's included", open: $showDeep)
                Spacer()
                cleanButton("deep", bytes > 0 ? "Deep clean \(Fmt.fileSize(bytes))" : "Deep clean", count: deepNow.count, bytes: bytes,
                            admin: deepNow.contains(where: \.needsAdmin), prominent: false) { model.clean(deepNow, label: "deep clean") }
            }
            .padding(.leading, 26)
            if showDeep {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([Cleaner.Group.rebuilds, .check], id: \.self) { g in
                        let here = deep.filter { $0.group == g }
                        if !here.isEmpty {
                            Text(g.title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Ink.muted)
                                .padding(.top, g == .check ? 6 : 0)
                            folding(g == .check ? "check" : "rebuilds", here, bytes: \.bytes, ticked: ticked) { deepRow($0) } summary: { title, total, on, open in
                                // no tick of its own: each is chosen with the list open, Caution items included
                                HStack(alignment: .top, spacing: 8) {
                                    Toggle("", isOn: .constant(false)).toggleStyle(.checkbox).labelsHidden().hidden()
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(title)
                                            Spacer(minLength: 8)
                                            if total > 0 { Text(Fmt.fileSize(total)).foregroundStyle(Ink.muted) }
                                        }
                                        HStack(spacing: 6) {
                                            eachOne(open)
                                            if on > 0 { Text("\(on) ticked").font(.caption).foregroundStyle(Ink.muted) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 26).padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// One item in Deep clean: a tick, what it is and its size, and what removing it costs; Caution and a padlock where
    /// they apply.
    func deepRow(_ f: Cleaner.Find) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { ticked(f) }, set: { ticks[f.id] = $0 }))
                .toggleStyle(.checkbox).labelsHidden().disabled(f.blocked != nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(f.title)
                    if f.needsAdmin {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Ink.muted)
                            .help("macOS asks for an administrator's password, because this is in a folder for all users.")
                    }
                    Spacer(minLength: 8)
                    if let b = f.bytes, b > 0 { Text(Fmt.fileSize(b)).foregroundStyle(Ink.muted) }
                }
                Text(f.blocked.map { "Left out while \($0.lowercasedFirst). " + f.detail } ?? f.detail)
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if f.caution {
                    OptionTag(words: "CAUTION", symbol: "exclamationmark.triangle.fill", color: .white,
                              help: "Cool Head can't be sure nothing still uses this.", solid: Ink.cautionFill)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// What Cool Head moved and can put back: folded, each with Put back (or, for what needed a password, Show, since
    /// putting it back needs Finder and the password again).
    var movedBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(Ink.muted).frame(width: 18)
                Text("Moved to the Trash by Cool Head")
                Spacer()
                Text(Cleaner.count(moved.count, bytes: moved.compactMap(\.bytes).reduce(0, +))).foregroundStyle(Ink.muted)
            }
            disclosure(showMoved ? "Hide them" : "Show them", open: $showMoved).padding(.leading, 26)
            if showMoved {
                folding("moved", Array(moved.suffix(30).reversed()), bytes: \.bytes) { m in
                        HStack(spacing: 8) {
                            Text((m.from as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let b = m.bytes, b > 0 { Text(Fmt.fileSize(b)).foregroundStyle(Ink.muted) }
                            if m.admin {
                                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: m.to)]) }
                                    .buttonStyle(.bordered).controlSize(.small).fixedSize()
                            } else {
                                Button("Put back") { model.putBack(m) }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                            }
                        }
                        .font(.caption)
                } summary: { title, total, _, open in
                    HStack(spacing: 8) {
                        Text(title)
                        Spacer(minLength: 8)
                        if total > 0 { Text(Fmt.fileSize(total)).foregroundStyle(Ink.muted) }
                        eachOne(open)
                    }
                    .font(.caption)
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 12)
    }

    /// Identical copies, in Quick clean, in any folder the person chooses, worded to check anywhere, with Downloads chosen
    /// to start. A copy is a second download ("Report (1).pdf") or a Finder duplicate ("Report copy.pdf") whose bytes
    /// match the original's, compared in full, never by name or size alone. Old installers found in the same folder go
    /// under Deep clean.
    var copiesRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.on.doc").foregroundStyle(Ink.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Identical copies in a folder")
                Text("A copy that matches its original byte for byte, such as Report (1).pdf or Report copy.pdf beside Report.pdf. The original stays. Cool Head looks in the folder you choose, Downloads to start, and the folders inside it, and lists old installers it finds there under Deep clean.")
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if model.checking { ProgressView().controlSize(.small); Text("Checking…").font(.caption).foregroundStyle(Ink.muted) }
                    Button("Choose a folder…") { model.checkFolder() }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                        .disabled(model.checking)
                }
                .padding(.top, 2)
            }
        }
    }

    /// A list with its items under 50 MB folded into one line that opens them ("17 smaller items under 50 MB each, 87 MB
    /// in total"), so the big ones, which free the most, stand out.
    /// The folded small items are one line laid out like the list's others (`summary`: its name, their total, how many
    /// are ticked, and whether it's open), so it reads as part of the list, with "Show each one" in blue where the
    /// others have their detail. Opened, the items follow it.
    func folding<Item: Identifiable, Row: View, Summary: View>(_ key: String, _ items: [Item], bytes: KeyPath<Item, UInt64?>,
                                               ticked: ((Item) -> Bool)? = nil, @ViewBuilder row: @escaping (Item) -> Row,
                                               @ViewBuilder summary: (String, UInt64, Int, Binding<Bool>) -> Summary) -> some View {
        let (shown, small) = Cleaner.split(items) { $0[keyPath: bytes] }
        let open = Binding(get: { openSmall.contains(key) }, set: { if $0 { openSmall.insert(key) } else { openSmall.remove(key) } })
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { row($0) }
            if !small.isEmpty {
                summary(Cleaner.foldedLine(small.count), small.compactMap { $0[keyPath: bytes] }.reduce(0, +),
                        ticked.map { t in small.filter(t).count } ?? 0, open)
                if open.wrappedValue { ForEach(small) { row($0) } }
            }
        }
    }

    /// The blue words that open the folded small items, in place of a line's detail.
    func eachOne(_ open: Binding<Bool>) -> some View {
        disclosure(open.wrappedValue ? "Hide them" : "Show each one", open: open)
    }

    func disclosure(_ words: String, open: Binding<Bool>) -> some View {
        Button { open.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                Text(words)
            }
            .font(.caption)
        }
        .buttonStyle(.plain).foregroundStyle(Ink.accent)
    }

    func linkRow(symbol: String, title: String, detail: String, button: String, url: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Ink.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(button) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
                        .buttonStyle(.bordered).controlSize(.small).fixedSize()
                }
                .padding(.top, 2)
            }
        }
    }
}

/// The Cleaner's finds and what it moved, kept while Cool Head runs; scanned when the page opens (at most once a
/// minute), off the main thread.
@MainActor
final class CleanerModel: ObservableObject {
    static let shared = CleanerModel()
    @Published var finds: [Cleaner.Find] = []
    /// Found in a folder the person chose (Downloads), kept beside the scan's own finds.
    @Published var chosen: [Cleaner.Find] = []
    @Published var scanning = false
    /// Checking a folder the person chose.
    @Published var checking = false
    @Published var working = false
    @Published var message: String?
    @Published var moved: [Cleaner.Moved] = Cleaner.movedList()
    private var scanned: Date?

    func scan(force: Bool = false) {
        moved = Cleaner.movedList()
        guard !scanning, force || scanned.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let found = Cleaner.scan(Cleaner.Roots.thisMac())
            await MainActor.run {
                let ids = Set(found.map(\.id))
                self.finds = found + self.chosen.filter { !ids.contains($0.id) && $0.paths.allSatisfy { FileManager.default.fileExists(atPath: $0) } }
                self.scanned = Date(); self.scanning = false
            }
        }
    }

    /// Moves what's chosen to the Trash: what needs no password first, then, in one one-shot job with one password
    /// prompt, what does. Logs only the counts, never a name or path.
    func clean(_ list: [Cleaner.Find], label: String) {
        working = true
        let plain = list.filter { !$0.needsAdmin }, admin = list.filter(\.needsAdmin)
        Task.detached(priority: .userInitiated) {
            var moved = 0, failed = 0, bytes: UInt64 = 0
            for f in plain {
                let r = Cleaner.trash(f)
                moved += r.moved.count; failed += r.failed.count; bytes += r.moved.compactMap(\.bytes).reduce(0, +)
            }
            let moves = admin.flatMap { Cleaner.adminMoves($0) }
            var adminOK = true
            if !moves.isEmpty {
                // measured before they move: once in the Trash, they're behind its privacy
                var sizes: [String: UInt64] = [:]
                for m in moves { sizes[m.from] = Cleaner.size(m.from) }
                adminOK = AdminJob.run(Cleaner.adminArguments(moves),
                                       prompt: "Cool Head: move \(moves.count == 1 ? "1 item" : "\(moves.count) items") from a folder for all users to your Trash. Nothing stays installed.\n")
                let done = Cleaner.rememberAdmin(moves, sizes: sizes)
                moved += done.count; failed += moves.count - done.count; bytes += done.compactMap(\.bytes).reduce(0, +)
            }
            let (m, f, ok, b) = (moved, failed, adminOK, bytes)
            await MainActor.run {
                Watcher.shared.log("Cleaner: \(label), \(m) moved to the Trash, \(f) not moved")
                self.message = (m > 0 ? "Moved \(Cleaner.count(m, bytes: b)) to the Trash. " : "")
                    + (f > 0 ? (ok ? "\(f == 1 ? "1 item" : "\(f) items") couldn't be moved." : "Nothing in the folders for all users was moved.") : "")
                self.working = false
                self.chosen.removeAll { c in list.contains { $0.id == c.id } }
                self.scan(force: true)
            }
        }
    }

    func putBack(_ m: Cleaner.Moved) {
        if Cleaner.putBack(m) { Watcher.shared.log("Cleaner: put one item back") }
        moved = Cleaner.movedList()
        scan(force: true)
    }

    /// The person chooses the folder, anywhere, with Downloads chosen to start; choosing it is also how macOS lets Cool
    /// Head read a private folder such as Downloads without asking.
    func checkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = "Check"
        // the button asks for a folder, so the chooser matches it (a button that said Check Downloads and then asked for
        // a folder didn't match)
        panel.message = "Choose a folder to check for identical copies and old installers. Downloads is chosen to start."
        NSApp.activate(ignoringOtherApps: true)
        // in front of Cool Head's panel: `begin`, not `runModal`, which puts it back at the level for dialogs, under the
        // panel, where it can't be seen
        panel.level = .abovePanel
        MenuPanel.keepOpen = true
        panel.begin { [weak self] answer in
            MenuPanel.keepOpen = false
            guard answer == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.chose(url) }
        }
    }

    /// Checks the folder and the folders inside it away from the panel's own work, so a big folder doesn't freeze it.
    private func chose(_ url: URL) {
        checking = true
        message = nil
        Task.detached(priority: .userInitiated) {
            let (found, stopped) = Cleaner.scanFolder(url.path)
            await MainActor.run {
                Watcher.shared.log("Cleaner: checked a chosen folder, \(found.count) found\(stopped ? ", stopped early" : "")")
                // what an earlier folder found goes, so only this folder's finds are listed
                let old = Set(self.chosen.map(\.id))
                self.chosen = found
                let ids = Set(found.map(\.id))
                self.finds = self.finds.filter { !old.contains($0.id) && !ids.contains($0.id) } + found
                self.message = stopped ? "That folder holds more than 100,000 files, so Cool Head stopped there. Choose a folder inside it to check the rest."
                    : found.isEmpty ? "Nothing to clear in that folder or the folders inside it." : nil
                self.checking = false
            }
        }
    }
}

/// One command run as administrator through a one-shot launchd job: macOS asks for the password, launchd runs the
/// command, and the job is removed straight after, so nothing stays installed; a permanent helper is the fallback only if
/// this stops working. Waits up to 15 seconds for the command; false when not allowed or it failed.
enum AdminJob {
    static func run(_ arguments: [String], prompt: String) -> Bool {
        var ref: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess, let auth = ref else { return false }
        defer { AuthorizationFree(auth, [.destroyRights]) }
        let status: OSStatus = kSMRightModifySystemDaemons.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { p in
                var rights = AuthorizationRights(count: 1, items: p)
                let flags: AuthorizationFlags = [.extendRights, .preAuthorize, .interactionAllowed]
                return kAuthorizationEnvironmentPrompt.withCString { key in
                    prompt.withCString { value in
                        var env = AuthorizationItem(name: key, valueLength: strlen(value), value: UnsafeMutableRawPointer(mutating: value), flags: 0)
                        return withUnsafeMutablePointer(to: &env) { e in
                            var environment = AuthorizationEnvironment(count: 1, items: e)
                            return AuthorizationCopyRights(auth, &rights, &environment, flags, nil)
                        }
                    }
                }
            }
        }
        guard status == errAuthorizationSuccess else { return false }
        let label = "io.github.thephildiamond.coolhead.oneshot.\(getpid()).\(Int(Date().timeIntervalSince1970))"
        let done = NSTemporaryDirectory() + label + ".done"
        // the command, then a mark that it finished, both run by launchd as root
        let job: [String: Any] = ["Label": label, "RunAtLoad": true,
                                  "ProgramArguments": ["/bin/sh", "-c", "\"$@\"; /usr/bin/touch \"\(done)\"", "sh"] + arguments]
        var err: Unmanaged<CFError>?
        guard SMJobSubmit(kSMDomainSystemLaunchd, job as CFDictionary, auth, &err) else { return false }
        var finished = false
        for _ in 0..<60 where !finished { if FileManager.default.fileExists(atPath: done) { finished = true } else { usleep(250_000) } }
        _ = SMJobRemove(kSMDomainSystemLaunchd, label as CFString, auth, true, nil)
        try? FileManager.default.removeItem(atPath: done)
        return finished
    }
}

private extension String {
    var lowercasedFirst: String {
        // names stay as they are ("Xcode's", "Chrome's", "Homebrew"); only an ordinary first word is lowered
        let first = prefix(while: { $0 != " " })
        return ["Logs", "Old"].contains(first) ? prefix(1).lowercased() + dropFirst() : self
    }
}

extension Cleaner.Moved: Identifiable {
    public var id: String { from + "\u{0}" + to }
}

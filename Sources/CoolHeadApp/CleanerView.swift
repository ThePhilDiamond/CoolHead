import AppKit
import CoolHeadCore
import ServiceManagement
import SwiftUI

/// The Cleaner tool's page: a verdict; Quick clean, a list of what nothing uses, done with one button; Deep clean, a list
/// to choose from, folded, with what rebuilds itself ticked and what Cool Head can't be sure of left for the person to
/// tick (Phil, 18 November 2026: "The first section one-button should be stuff that definitely isn't needed and has no
/// impact, trash. Then the second section, something like "Deep Clean", where you can select things should auto-check
/// the stuff that rebuilds and have the "check these first" as options to check."). Then what Cool Head moved, to put
/// back, and the two places in System Settings Cool Head can't clear itself, with a button to open each.
struct CleanerView: View {
    let close: () -> Void
    @ObservedObject var model = CleanerModel.shared
    /// Screenshots can show Deep clean's list open (COOLHEAD_SNAPSHOT_CLEANER=open).
    @State private var showDeep = ProcessInfo.processInfo.environment["COOLHEAD_SNAPSHOT_CLEANER"] == "open"
    @State private var showMoved = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text("Cleaner") } icon: { Image(nsImage: Broom.image(size: 15)) }.font(.body.weight(.semibold))
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
                        .font(.title3).foregroundStyle(finds.isEmpty ? Color.green : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.title).font(.callout.weight(.semibold))
                        Text(v.meaning).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let m = model.message { Text(m).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
                if !quick.isEmpty { quickBox }
                if !deep.isEmpty { deepBox }
            }
            downloadsRow
            if !model.moved.isEmpty && !CleanerView.snapshot { movedBox }
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

    /// A clean button: the first click asks ("Move 3 items to the Trash?"), a second within 5 seconds goes ahead.
    func cleanButton(_ id: String, _ words: String, count: Int, admin: Bool, prominent: Bool, run: @escaping () -> Void) -> some View {
        let isArmed = armed == id
        let label = HStack(spacing: 4) {
            if admin { Image(systemName: "lock.fill").font(.system(size: 9)) }
            Text(isArmed ? "Move \(count == 1 ? "1 item" : "\(count) items") to the Trash?" : words).padding(.horizontal, 4)
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
    var quickBox: some View {
        let bytes = quick.compactMap(\.bytes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor).frame(width: 18)
                Text("Quick clean").font(.callout.weight(.semibold))
                Spacer()
                if bytes >= 50_000_000 { Text(MemoryAdvice.diskGB(bytes)).foregroundStyle(Ink.muted) }
            }
            Text("Nothing uses these, and nothing has to rebuild them.")
                .font(.caption).foregroundStyle(Ink.muted).padding(.leading, 26)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(quick) { f in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.muted).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(f.title)
                                Spacer(minLength: 8)
                                if let b = f.bytes, b >= 50_000_000 { Text(MemoryAdvice.diskGB(b)).foregroundStyle(Ink.muted) }
                            }
                            Text(f.detail).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.leading, 26)
            HStack {
                Spacer()
                cleanButton("quick", "Quick clean", count: quick.count, admin: false, prominent: true) { model.clean(quick, label: "quick clean") }
            }
            .padding(.leading, 26)
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
                        check.isEmpty ? nil : "What Cool Head can't be sure of isn't: \(Cleaner.joined(Cleaner.kinds(check)))."]
            .compactMap { $0 }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bubbles.and.sparkles").foregroundStyle(Ink.muted).frame(width: 18)
                Text("Deep clean").font(.callout.weight(.semibold))
                Spacer()
                if bytes > 0 { Text(MemoryAdvice.diskGB(bytes)).foregroundStyle(Ink.muted) }
            }
            Text(sentence).font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
            HStack {
                disclosure(showDeep ? "Hide the list" : "Choose what's included", open: $showDeep)
                Spacer()
                cleanButton("deep", bytes >= 50_000_000 ? "Deep clean \(MemoryAdvice.diskGB(bytes))" : "Deep clean", count: deepNow.count,
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
                            ForEach(here) { deepRow($0) }
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
                    if let b = f.bytes, b >= 50_000_000 { Text(MemoryAdvice.diskGB(b)).foregroundStyle(Ink.muted) }
                }
                Text(f.blocked.map { "Left out while \($0.lowercasedFirst). " + f.detail } ?? f.detail)
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if f.caution {
                    OptionTag(words: "CAUTION", symbol: "exclamationmark.triangle.fill", color: .red,
                              help: "Cool Head can't be sure nothing still uses this.")
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
                Text("\(model.moved.count)").foregroundStyle(Ink.muted)
            }
            disclosure(showMoved ? "Hide them" : "Show them", open: $showMoved).padding(.leading, 26)
            if showMoved {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.moved.suffix(30).reversed(), id: \.self) { m in
                        HStack(spacing: 8) {
                            Text((m.from as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            if m.admin {
                                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: m.to)]) }
                                    .buttonStyle(.bordered).controlSize(.small).fixedSize()
                            } else {
                                Button("Put back") { model.putBack(m) }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 12)
    }

    /// Installers and second copies in Downloads: only when the person chooses the folder, so macOS doesn't ask.
    var downloadsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.circle").foregroundStyle(Ink.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("Installers and copies in Downloads")
                Text("Old .dmg and .pkg files, and identical second downloads. Cool Head looks only when you choose the folder.")
                    .font(.caption).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Check Downloads…") { model.checkDownloads() }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
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
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
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
            var moved = 0, failed = 0
            for f in plain { let r = Cleaner.trash(f); moved += r.moved.count; failed += r.failed.count }
            let moves = admin.flatMap { Cleaner.adminMoves($0) }
            var adminOK = true
            if !moves.isEmpty {
                adminOK = AdminJob.run(Cleaner.adminArguments(moves),
                                       prompt: "Cool Head: move \(moves.count == 1 ? "1 item" : "\(moves.count) items") from a folder for all users to your Trash. Nothing stays installed.\n")
                Cleaner.rememberAdmin(moves)
                let done = moves.filter { FileManager.default.fileExists(atPath: $0.to) }.count
                moved += done; failed += moves.count - done
            }
            let (m, f, ok) = (moved, failed, adminOK)
            await MainActor.run {
                Watcher.shared.log("Cleaner: \(label), \(m) moved to the Trash, \(f) not moved")
                self.message = (m > 0 ? "Moved \(m == 1 ? "1 item" : "\(m) items") to the Trash. " : "")
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

    /// The person chooses the folder (Downloads to start), which is how macOS lets Cool Head read it without asking.
    func checkDownloads() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = "Check"
        panel.message = "Cool Head looks for old installers and identical second downloads in the folder you choose."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let found = Cleaner.scanDownloads(url.path)
        Watcher.shared.log("Cleaner: checked a chosen folder, \(found.count) found")
        chosen = found
        let ids = Set(found.map(\.id))
        finds = finds.filter { !ids.contains($0.id) } + found
        message = found.isEmpty ? "Nothing to clear in that folder." : nil
    }
}

/// One command run as administrator through a one-shot launchd job: macOS asks for the password, launchd runs the
/// command, and the job is removed straight after, so nothing stays installed (Phil, 16 November 2026: "one-shot job
/// and if that doesn't work we'll do the permanent helper"; tested on this Mac that day, notes/research_graph/
/// apple-silicon-issues/padlock.md). Waits up to 15 seconds for the command; false when not allowed or it failed.
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

/// A broom, drawn: macOS's own symbols have none. The handle runs up to the right; the bristles fan out at the bottom
/// left, with a band where they're bound. A template image, so it takes the button's colour like the symbols do.
enum Broom {
    static func image(size s: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let k = s / 18
            cg.scaleBy(x: k, y: k)
            cg.translateBy(x: 9, y: 9)
            cg.rotate(by: -.pi / 5)
            cg.setFillColor(NSColor.black.cgColor)
            cg.setStrokeColor(NSColor.black.cgColor)
            // handle
            cg.setLineWidth(1.6); cg.setLineCap(.round)
            cg.move(to: CGPoint(x: 0, y: -1)); cg.addLine(to: CGPoint(x: 0, y: 9.2)); cg.strokePath()
            // band
            cg.fill(CGRect(x: -2.4, y: -2.6, width: 4.8, height: 1.8))
            // bristles: a fan, with the strands' gaps cut out
            let fan = CGMutablePath()
            fan.move(to: CGPoint(x: -2.4, y: -3.2)); fan.addLine(to: CGPoint(x: 2.4, y: -3.2))
            fan.addLine(to: CGPoint(x: 4.6, y: -9.2)); fan.addLine(to: CGPoint(x: -4.6, y: -9.2)); fan.closeSubpath()
            cg.addPath(fan); cg.fillPath()
            cg.setBlendMode(.clear); cg.setLineWidth(0.7)
            for x in [-1.5, 0.0, 1.5] as [CGFloat] {
                cg.move(to: CGPoint(x: x * 0.55, y: -4.2)); cg.addLine(to: CGPoint(x: x * 1.25, y: -9.4)); cg.strokePath()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

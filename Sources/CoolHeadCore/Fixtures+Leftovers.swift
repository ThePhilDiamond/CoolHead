import Foundation

/// Checks for what tools leave holding memory or disk (see Leftovers): a local AI model kept loaded, and Xcode's build
/// data on a nearly full disk; and the example cards `coolhead wording` shows for them.
extension Fixture {
    static func leftoversMac(freeGB: Double? = nil) -> MacState {
        var s = MacState(); s.memoryPressure = "warning"; s.swapUsedMB = 1500; s.swapTotalMB = 3000
        s.diskFreeBytes = freeGB.map { UInt64($0 * 1_000_000_000) }
        return s
    }
    static func memGroup(_ name: String, _ gb: Double, bundle: String? = nil, kind: MemGroup.Kind = .other) -> MemGroup {
        MemGroup(key: name, name: name, kind: kind, bundle: bundle, bytes: UInt64(gb * 1_000_000_000), count: 1)
    }
    static let llama = Leftovers.Model(name: "llama3.2:3b", bytes: 3_400_000_000)

    /// The example cards (see Wording).
    static func leftoversSamples(_ now: Date) -> [(String, Card)] {
        [("memory-ollama-model", MemoryAdvice.card([memGroup("llama-server", 3.6), memGroup("Slack", 1.2, bundle: "/Applications/Slack.app", kind: .app)],
                                                   mac: leftoversMac(), now: now, models: [llama])),
         ("memory-low-disk-xcode", MemoryAdvice.card([memGroup("Xcode", 6.2, bundle: "/Applications/Xcode.app", kind: .app)],
                                                     mac: leftoversMac(freeGB: 11), now: now, buildData: 14_300_000_000))]
    }

    static func leftoversChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []

        // Ollama: its answer read; its processes recognised wherever it's installed
        let json = Data(#"{"models":[{"name":"smollm:135m","model":"smollm:135m","size":153385696,"size_vram":153385696}]}"#.utf8)
        let parsed = Leftovers.parseLoaded(json)
        let r1 = parsed == [.init(name: "smollm:135m", bytes: 153_385_696)] && Leftovers.parseLoaded(Data("{}".utf8)) == nil
            && Leftovers.parseLoaded(Data(#"{"models":[]}"#.utf8)) == []
            && Leftovers.isOllama("/Applications/Ollama.app/Contents/Resources/ollama") && Leftovers.isOllama("/opt/homebrew/Cellar/ollama/0.40.16/libexec/lib/ollama/llama-server")
            && Leftovers.isOllama("/usr/local/bin/ollama") && !Leftovers.isOllama("/opt/homebrew/bin/llama-cli") && !Leftovers.isOllama(nil)
        review.append(("leftovers-ollama-read", r1, "parsed \(String(describing: parsed))"))

        // the memory card: unloading is recommended when Ollama is the biggest, offered when it's among the three biggest,
        // and never Caution (nothing is lost)
        let top = MemoryAdvice.card([memGroup("llama-server", 3.6), memGroup("Slack", 1.2, bundle: "/Applications/Slack.app", kind: .app)],
                                    mac: leftoversMac(), now: now, models: [llama])
        let second = MemoryAdvice.card([memGroup("Slack", 4.1, bundle: "/Applications/Slack.app", kind: .app), memGroup("llama-server", 3.6)],
                                       mac: leftoversMac(), now: now, models: [llama])
        let notThere = MemoryAdvice.card([memGroup("Slack", 4.1, bundle: "/Applications/Slack.app", kind: .app)], mac: leftoversMac(), now: now, models: [llama])
        let u = top.recommended
        // Ollama's size is the headline's when it uses the most, so the title doesn't say it again; second, it does
        let r2 = u?.id == "unload" && u?.title == "Unload llama3.2:3b" && u?.kind == .unloadModels(["llama3.2:3b"]) && u?.caution == false && u?.doer == .coolHead
            && u?.consequence.hasPrefix("Nothing is lost. Ollama loads it again") == true && u?.consequence.contains("GB") == false
            && second.fixes.contains { $0.id == "unload" && !$0.recommended && $0.title == "Unload llama3.2:3b to free 3.2 GB" } && !notThere.fixes.contains { $0.id == "unload" }
        review.append(("leftovers-unload-option", r2, top.headline + " Options: \(top.fixes.map { "\($0.id)\($0.recommended ? " (recommended)" : "")" }); \(u?.consequence ?? "")"))

        // Xcode's build data: offered on a nearly full disk when it's 1 GB or more, never Caution, and asks first
        let low = MemoryAdvice.card([memGroup("Xcode", 6.2, bundle: "/Applications/Xcode.app", kind: .app)], mac: leftoversMac(freeGB: 11), now: now, buildData: 14_300_000_000)
        let small = MemoryAdvice.card([memGroup("Xcode", 6.2, bundle: "/Applications/Xcode.app", kind: .app)], mac: leftoversMac(freeGB: 11), now: now, buildData: 400_000_000)
        let roomy = MemoryAdvice.card([memGroup("Xcode", 6.2, bundle: "/Applications/Xcode.app", kind: .app)], mac: leftoversMac(freeGB: 80), now: now, buildData: 14_300_000_000)
        let bd = low.fixes.first { $0.id == "builddata" }
        let r3 = bd?.title == "Delete Xcode's build data to free 14 GB of storage"
            && bd?.consequence == "This makes the next build of each project take longer, because Xcode builds what it needs again." && bd?.caution == false && low.recommended?.id == "builddata"
            && !small.fixes.contains { $0.id == "builddata" } && !roomy.fixes.contains { $0.id == "builddata" }
        review.append(("leftovers-build-data-option", r3, bd.map { "\($0.title): \($0.consequence)" } ?? "not offered"))

        // for real, with a stand-in folder: its contents are deleted and the folder stays; any other folder is refused
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "coolhead-leftovers-\(getpid())-\(UUID().uuidString.prefix(8))/coolhead-selftest-DerivedData"
        try? fm.createDirectory(atPath: dir + "/App-abc/Build/Intermediates", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/App-abc/Build/Intermediates/x.o", contents: Data(count: 200_000))
        let before = Leftovers.size(of: dir) ?? 0
        let deleted = Leftovers.deleteBuildData(dir)
        let after = ((try? fm.contentsOfDirectory(atPath: dir)) ?? ["?"]).isEmpty && fm.fileExists(atPath: dir)
        try? fm.removeItem(atPath: (dir as NSString).deletingLastPathComponent)
        let refused = !Leftovers.deleteBuildData(NSTemporaryDirectory()) && fm.fileExists(atPath: NSTemporaryDirectory())
        review.append(("leftovers-build-data-deletes", before >= 200_000 && deleted && after && refused,
                       "stand-in held \(before) bytes; emptied \(deleted), folder kept \(after); another folder refused \(refused)"))

        // on this Mac: Ollama answers, or not answering is found quickly
        let t = Date()
        let live = Leftovers.loaded()
        let quick = Date().timeIntervalSince(t) < 3
        review.append(("leftovers-ollama-this-mac", live != nil || quick,
                       live.map { "Ollama answering, \($0.count) model(s) loaded" } ?? "Ollama not answering (not running here), found in \(String(format: "%.1f", Date().timeIntervalSince(t))) s"))
        return review
    }
}

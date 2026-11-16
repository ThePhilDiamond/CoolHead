import Foundation

/// Checks for the catalogue's entries (see Catalogue.swift), and an example card for each, shown by `coolhead wording`.
extension Fixture {
    /// A macOS or app process as Cool Head would see it: `mine` false for processes run by macOS's own users.
    static func catalogueProcess(_ name: String, _ path: String, mine: Bool = true, start: Date, cores: Double, gpu: Double? = nil) -> Evidence {
        var e = Evidence(pid: 99999, name: name, path: path, args: [path], cwd: nil, start: start, mine: mine, coresNow: cores,
                         coresAverage: cores, performanceShare: nil, memoryBytes: 500_000_000, ancestors: [], writing: [], locks: [],
                         progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil, savesAsItGoes: false, workStart: start)
        e.gpuShare = gpu
        return e
    }

    /// One example process for each entry this file covers, with how long it has been busy in the "long" example.
    static func catalogueExamples(_ now: Date) -> [(id: String, evidence: Evidence, long: TimeInterval)] {
        let start = now.addingTimeInterval(-48 * 3600)
        func p(_ name: String, _ path: String, mine: Bool = true, cores: Double = 1, gpu: Double? = nil) -> Evidence {
            catalogueProcess(name, path, mine: mine, start: start, cores: cores, gpu: gpu)
        }
        return [
            ("sound", p("coreaudiod", "/usr/sbin/coreaudiod", mine: false, cores: 1.5), 3600),
            ("contacts-sync", p("peopled", "/System/Library/PrivateFrameworks/People.framework/peopled", cores: 0.8), 3 * 3600),
            ("messages-sync", p("imagent", "/System/Library/PrivateFrameworks/IMCore.framework/imagent.app/Contents/MacOS/imagent"), 5 * 3600),
            ("aerial-downloads", p("idleassetsd", "/usr/libexec/idleassetsd", mine: false, cores: 0.6), 3 * 3600),
            ("displaylink", p("DisplayLink Manager", "/Applications/DisplayLink Manager.app/Contents/MacOS/DisplayLink Manager", cores: 1.4), 2 * 3600),
            ("local-ai-model", p("ollama", "/Applications/Ollama.app/Contents/Resources/ollama", cores: 0.6, gpu: 0.8), 2 * 3600),
        ]
    }

    /// The example cards: each entry while it's usual, and once it's gone on longer than usual; Docker while running.
    static func catalogueSamples(_ now: Date) -> [(String, Card)] {
        let docker = catalogueProcess("com.docker.virtualization", "/Applications/Docker.app/Contents/MacOS/com.docker.virtualization",
                                      start: now.addingTimeInterval(-10 * 3600), cores: 1)
        return [("catalogue-docker-vm", Card.make(docker, now: now, busySince: now.addingTimeInterval(-10 * 3600)))]
            + catalogueExamples(now).flatMap { x in
                [("catalogue-\(x.id)", Card.make(x.evidence, now: now, busySince: now.addingTimeInterval(-5 * 60))),
                 ("catalogue-\(x.id)-long", Card.make(x.evidence, now: now, busySince: now.addingTimeInterval(-x.long)))]
            }
    }

    static func catalogueChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        func entry(_ id: String) -> Pattern? { Pattern.catalogue.first { $0.id == id } }

        // Docker's Resource Saver (on by default) stops the virtual machine 5 minutes after the last container: the card
        // says it ends, and still offers to quit Docker, saying that stops every container
        let docker = catalogueSamples(now).first { $0.0 == "catalogue-docker-vm" }?.1
        let dockerOK = entry("docker-vm")?.endsOnItsOwn == true
            && docker?.headline == "Docker's virtual machine is running. That's normal."
            && docker?.explanation.contains("for 5 minutes after the last one stops. It stops on its own.") == true
            && docker?.fixes.contains { $0.id == "quit" && $0.consequence == "Quitting Docker stops every container." } == true
        review.append(("catalogue-docker-stops-when-idle", dockerOK, docker.map { $0.headline + " " + $0.explanation } ?? "no card"))

        // every example matches its own entry; macOS's names count only for macOS's own copy
        var wrong: [String] = []
        for x in catalogueExamples(now) {
            let found = Pattern.match(name: x.evidence.name, path: x.evidence.path)?.id
            if found != x.id { wrong.append("\(x.evidence.name) matched \(found ?? "nothing"), expected \(x.id)") }
        }
        for (name, path) in [("peopled", "/Users/x/bin/peopled"), ("coreaudiod", "/opt/homebrew/bin/coreaudiod"), ("imagent", "/Users/x/imagent")]
            where Pattern.match(name: name, path: path) != nil { wrong.append("\(name) at \(path) matched") }
        // the other names each entry covers
        let others = [("contactsd", "/System/Library/Frameworks/Contacts.framework/Support/contactsd", "contacts-sync"),
                      ("CallHistorySyncHelper", "/System/Library/PrivateFrameworks/CallHistory.framework/Support/CallHistorySyncHelper", "contacts-sync"),
                      ("IMDPersistenceAgent", "/System/Library/PrivateFrameworks/IMDPersistence.framework/XPCServices/IMDPersistenceAgent.xpc/Contents/MacOS/IMDPersistenceAgent", "messages-sync"),
                      ("LM Studio", "/Applications/LM Studio.app/Contents/MacOS/LM Studio", "local-ai-model"),
                      ("ollama", "/opt/homebrew/Cellar/ollama/0.13.0/bin/ollama", "local-ai-model")]
        for (name, path, id) in others where Pattern.match(name: name, path: path)?.id != id { wrong.append("\(name) didn't match \(id)") }
        review.append(("catalogue-entries-match", wrong.isEmpty, wrong.isEmpty ? "\(catalogueExamples(now).count + others.count) processes match their entries" : wrong.joined(separator: "; ")))

        // while usual: calm, saying what is normal; once longer than usual: the entry's advice is recommended, as steps
        // when there's no app to open (Messages' imagent is a .app inside a framework, not an app anyone opens)
        var cards: [String] = []
        for x in catalogueExamples(now) {
            guard let k = entry(x.id) else { cards.append("\(x.id) missing"); continue }
            let calm = Card.make(x.evidence, now: now, busySince: now.addingTimeInterval(-5 * 60))
            let long = Card.make(x.evidence, now: now, busySince: now.addingTimeInterval(-x.long))
            if calm.state != .working || calm.headline != "\(k.doing). That's normal." || !calm.explanation.hasPrefix(k.usually) { cards.append("\(x.id) usual: \(calm.headline) \(calm.explanation)") }
            if long.state != .unknown || !long.headline.contains("longer than usual") || long.recommended?.title != k.whenLong { cards.append("\(x.id) long: \(long.headline) → \(long.recommended?.title ?? "none")") }
            if case .openApp(let b, _) = long.recommended?.kind, b.contains(".framework/") { cards.append("\(x.id) opens \(b)") }
        }
        let imagent = catalogueExamples(now).first { $0.id == "messages-sync" }!.evidence
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        if imagent.appBundle != nil || Evidence.bundle(helper) != "/Applications/Google Chrome.app" { cards.append("bundle: imagent \(imagent.appBundle ?? "none"), Chrome helper \(Evidence.bundle(helper) ?? "none")") }
        review.append(("catalogue-cards", cards.isEmpty, cards.isEmpty ? "\(catalogueExamples(now).count) entries: calm while usual, their advice once longer" : cards.joined(separator: "; ")))

        // every entry names its source, and its text follows the house style: no em dashes or exclamation marks
        let style = Pattern.catalogue.filter { k in
            k.source.isEmpty || [k.doing, k.usually, k.whenLong, k.risk ?? ""].contains { $0.contains("\u{2014}") || $0.contains("!") }
        }.map(\.id)
        review.append(("catalogue-sources-and-style", style.isEmpty, style.isEmpty ? "\(Pattern.catalogue.count) entries name a source" : "check \(style)"))
        return review
    }
}

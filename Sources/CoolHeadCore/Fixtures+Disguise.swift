import Foundation

/// Checks for names counted only in macOS's own folders (`Pattern.matches`, research rule 1) and for programs that
/// borrow macOS's name or an Apple launch label (see Disguise, research rule 2), and the example cards
/// `coolhead wording` shows for them.
extension Fixture {
    static let qtopProgram = NSHomeDirectory() + "/Library/Application Support/qtop/qtop"
    static let qtopItem = Disguise.LaunchItem(label: "com.apple.qtop", plist: NSHomeDirectory() + "/Library/LaunchAgents/com.apple.qtop.plist",
                                              program: qtopProgram, signer: .other)
    static let mdsPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores"

    static func disguiseEvidence(_ name: String, _ path: String?, args: [String]? = nil, pid: pid_t = 99999, mine: Bool = true, now: Date) -> Evidence {
        Evidence(pid: pid, name: name, path: path, args: args ?? path.map { [$0] } ?? [], cwd: nil, start: now.addingTimeInterval(-3 * 3600), mine: mine,
                 coresNow: 2, coresAverage: 2, performanceShare: nil, memoryBytes: 300_000_000, ancestors: [], writing: [], locks: [],
                 progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil, savesAsItGoes: false, workStart: nil)
    }

    /// The example cards (see Wording).
    static func disguiseSamples(_ now: Date) -> [(String, Card)] {
        func make(_ e: Evidence, _ f: Disguise.Finding?) -> Card { Card.make(e, now: now, busySince: now.addingTimeInterval(-40 * 60), disguise: f) }
        let other: (String) -> Disguise.Signer = { _ in .other }
        let miner = disguiseEvidence("mdworker_local", "/private/tmp/mdworker_local", now: now)
        let qtop = disguiseEvidence("qtop", qtopProgram, now: now)
        let mds = disguiseEvidence("mds_stores", mdsPath, mine: false, now: now)
        let broken = Disguise.Protection(sipOff: true, sealBroken: true)
        return [("disguise-macos-name", make(miner, Disguise.judge(miner, protection: .init(), signer: other, launchItems: []))),
                ("disguise-apple-label", make(qtop, Disguise.judge(qtop, protection: .init(), signer: other, launchItems: [qtopItem]))),
                ("disguise-protection-off", make(mds, Disguise.judge(mds, protection: broken, signer: other, launchItems: [])))]
    }

    static func disguiseChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let other: (String) -> Disguise.Signer = { _ in .other }
        let apple: (String) -> Disguise.Signer = { _ in .apple }
        let unknown: (String) -> Disguise.Signer = { _ in .unknown }

        // rule 1: a catalogue name with no path counts as macOS only for pid 0 (kernel_task has no program file)
        let r1 = Pattern.match(name: "mds_stores", path: nil, pid: 4321) == nil && Pattern.match(name: "kernel_task", path: nil, pid: 0)?.id == "kernel-task"
            && Pattern.match(name: "kernel_task", path: nil, pid: 4321) == nil && Pattern.match(name: "mds_stores", path: mdsPath, pid: 4321)?.id == "spotlight"
        review.append(("disguise-missing-path-is-not-macos", r1, "mds_stores with no path matches nothing; kernel_task with no path matches only as pid 0"))

        // rule 2: a macOS name outside macOS's folders, with a definite non-Apple signature; by the kernel's name or the name
        // it gave itself. A check that failed for another reason finds nothing.
        func judge(_ e: Evidence, protection: Disguise.Protection = .init(), signer: @escaping (String) -> Disguise.Signer = other,
                   items: [Disguise.LaunchItem] = []) -> Disguise.Finding? {
            Disguise.judge(e, protection: protection, signer: signer, launchItems: items)
        }
        let miner = disguiseEvidence("mdworker_local", "/private/tmp/mdworker_local", now: now)
        let renamed = disguiseEvidence("helper", "/usr/local/bin/helper", args: ["mdworker", "-s", "mdworker"], now: now)
        let own = disguiseEvidence("bird", "/Users/x/bin/bird", now: now)
        let simulator = disguiseEvidence("mediaanalysisd", "/Library/Developer/CoreSimulator/Volumes/iOS_23A343/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.0.simruntime/Contents/Resources/RuntimeRoot/usr/libexec/mediaanalysisd", now: now)
        let script = Evidence.sample(name: "python3", path: "/opt/homebrew/bin/python3", args: ["python3", "mds"], start: now, cores: 1)
        let unrelated = disguiseEvidence("mdserve", "/Users/x/bin/mdserve", now: now)
        let r2 = judge(miner) == .macOSName(name: "mdworker_local", path: "/private/tmp/mdworker_local")
            && judge(renamed) == .macOSName(name: "mdworker", path: "/usr/local/bin/helper")
            && judge(own) == .macOSName(name: "bird", path: "/Users/x/bin/bird")
            && judge(miner, signer: unknown) == nil
            && judge(simulator, signer: apple) == nil && judge(script) == nil && judge(unrelated) == nil
        review.append(("disguise-macos-name-elsewhere", r2, "miner \(String(describing: judge(miner))); renamed \(String(describing: judge(renamed))); not flagged: a failed check, an Apple-signed simulator copy, a script, mdserve"))

        // the card: what Cool Head thinks, one short disclaimer, then its advice as one click (Phil, 16 November 2026: "Say
        // what we think, use a brief disclaimer, then give our advice"; stopping, then deleting as a separate task, "is not
        // a good user flow"); the Caution option says why; not yours: shown in Finder to delete
        let minerCard = Card.make(miner, now: now, disguise: judge(miner))
        let theirs = disguiseEvidence("mdworker_shared", "/usr/local/bin/mdworker_shared", mine: false, now: now)
        let theirsCard = Card.make(theirs, now: now, disguise: judge(theirs))
        let text = { (c: Card) in c.headline + " " + c.explanation }
        let remove = minerCard.recommended
        let r3 = minerCard.state == .unknown && minerCard.headline == "mdworker_local is pretending to be part of macOS."
            && minerCard.explanation == "It uses a macOS name but runs from a temporary folder, without Apple's signature: a common malware trick. We can't be certain it's harmful."
            && remove?.id == "remove" && remove?.kind == .stopAndTrash(["/private/tmp/mdworker_local"], nil) && remove?.caution == true
            && minerCard.fixes.map(\.id) == ["remove", "share"]
            && theirsCard.recommended?.id == "delete" && !theirsCard.fixes.contains { $0.interrupts }
            && text(theirsCard).contains("runs from /usr/local/bin")
        review.append(("disguise-card", r3, text(minerCard) + " Options: \(minerCard.fixes.map { "\($0.id): \($0.consequence)" }); not yours: \(theirsCard.fixes.map(\.id))"))

        // a path that couldn't be read: probably macOS's, said calmly, nothing to press but sharing
        let unread = disguiseEvidence("mds_stores", nil, args: [], pid: 4321, mine: false, now: now)
        let kernel = disguiseEvidence("kernel_task", nil, args: [], pid: 0, mine: false, now: now)
        let unreadCard = Card.make(unread, now: now, disguise: judge(unread))
        let r4 = judge(unread) == .unchecked(name: "mds_stores") && judge(kernel) == nil
            && unreadCard.headline == "mds_stores is probably part of macOS, but we couldn't confirm it." && unreadCard.fixes.map(\.id) == ["share"]
        review.append(("disguise-unchecked-path", r4, unreadCard.headline))

        // "isn't Apple's" inside macOS's folders needs a folder that could have been changed and a definite answer (Phil:
        // "make sure our confidence interval is higher"): the sealed system volume only with its seal off, /Library/Apple
        // with protection off; turning protection back on is recommended, a reinstall only offered
        let mds = disguiseEvidence("mds_stores", mdsPath, mine: false, now: now)
        let dataPath = "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect"
        let xp = disguiseEvidence("XProtect", dataPath, mine: false, now: now)
        let sipOnly = Disguise.Protection(sipOff: true, sealBroken: false), broken = Disguise.Protection(sipOff: true, sealBroken: true)
        let offCard = Card.make(mds, now: now, disguise: judge(mds, protection: broken))
        let r5 = judge(mds) == nil && judge(mds, protection: sipOnly) == nil && judge(mds, protection: broken, signer: apple) == nil
            && judge(mds, protection: broken, signer: unknown) == nil
            && judge(mds, protection: broken) == .notAppleSigned(name: "mds_stores", path: mdsPath)
            && judge(xp, protection: sipOnly) == .notAppleSigned(name: "XProtect", path: dataPath) && judge(xp) == nil
            && offCard.recommended?.id == "protect" && offCard.fixes.contains { $0.id == "reinstall" && !$0.recommended }
            && !offCard.fixes.contains { $0.interrupts }
            && Disguise.disabledSaid("System Integrity Protection status: disabled.") && !Disguise.disabledSaid("System Integrity Protection status: enabled.")
            && Disguise.disabledSaid("System Integrity Protection status: enabled (Custom Configuration).\n\n\tFilesystem Protections: disabled")
            && Disguise.disabledSaid("Authenticated Root status: disabled") && !Disguise.disabledSaid("Authenticated Root status: enabled")
            && Disguise.signer(status: errSecCSUnsigned) == .other && Disguise.signer(status: errSecCSReqFailed) == .other
            && Disguise.signer(status: errSecCSSignatureFailed) == .other && Disguise.signer(status: errSecCSStaticCodeNotFound) == .unknown
        review.append(("disguise-protection-off", r5, text(offCard) + " Options: \(offCard.fixes.map { "\($0.id)\($0.recommended ? " (recommended)" : "")" })"))

        // a launch item labelled com.apple.… outside macOS's folders whose program Apple didn't sign: by the process or a
        // parent; yours: turned off, stopped and moved to the Trash in one click; the system's needs an administrator
        let qtop = disguiseEvidence("qtop", qtopProgram, now: now)
        let child = Evidence(pid: 99998, name: "sh", path: "/bin/sh", args: ["/bin/sh"], cwd: nil, start: now, mine: true, coresNow: 2,
                             coresAverage: 2, performanceShare: nil, memoryBytes: 0, ancestors: [.init(pid: 500, name: "qtop", path: qtopProgram, args: [])],
                             writing: [], locks: [], progress: nil, bytesWrittenDuringSample: 0, lastOutput: nil, lastLine: nil, savesAsItGoes: false, workStart: nil)
        let daemonItem = Disguise.LaunchItem(label: "com.apple.qtop", plist: "/Library/LaunchDaemons/com.apple.qtop.plist", program: qtopProgram, signer: .other)
        let signedItem = Disguise.LaunchItem(label: "com.apple.installer.osmessagetracing", plist: "/Library/LaunchDaemons/com.apple.installer.osmessagetracing.plist",
                                             program: qtopProgram, signer: .apple)
        let unknownItem = Disguise.LaunchItem(label: "com.apple.gone", plist: "/Library/LaunchAgents/com.apple.gone.plist", program: qtopProgram, signer: .unknown)
        let yours = Card.make(qtop, now: now, disguise: judge(qtop, items: [qtopItem]))
        let system = Card.make(qtop, now: now, disguise: judge(qtop, items: [daemonItem]))
        let r6 = judge(qtop, items: [qtopItem]) == .appleLabel(label: "com.apple.qtop", plist: qtopItem.plist, program: qtopProgram)
            && judge(child, items: [qtopItem]) != nil && judge(qtop, items: [signedItem]) == nil && judge(qtop, items: [unknownItem]) == nil
            && yours.fixes.map(\.id) == ["remove", "share"] && yours.recommended?.kind == .stopAndTrash([qtopProgram, qtopItem.plist], qtopItem.plist)
            && system.recommended?.id == "loginitems" && !system.fixes.contains { $0.interrupts }
            && text(yours).contains("com.apple.qtop starts qtop from your LaunchAgents folder")
        review.append(("disguise-apple-label", r6, text(yours) + " Options: \(yours.fixes.map(\.id)); system's: \(system.fixes.map(\.id))"))

        // every finding's card: a verdict, the one disclaimer, advice as the recommended option; at most 40 words; never
        // "is malware"; every Caution option says what could go wrong in its own description
        let all = [minerCard, theirsCard, yours, system, offCard]
        let short = all.allSatisfy { text($0).split(separator: " ").count <= 40 && text($0).contains(Disguise.disclaimer) && !text($0).contains("is malware") && $0.recommended != nil }
            && all.flatMap(\.fixes).filter(\.caution).allSatisfy { $0.consequence.contains("it stops working") }
        review.append(("disguise-wording", short, all.map { "\(text($0).split(separator: " ").count) words" }.joined(separator: ", ")))

        // on this Mac, for real: Apple's own program passes `anchor apple`, an unsigned file Cool Head writes doesn't, and
        // a missing file is no answer; plists labelled com.apple.… are read, others left alone; a com.apple label is turned
        // off only when Apple's signature is definitely missing
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "coolhead-disguise-\(getpid())-\(UUID().uuidString.prefix(8))"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        let fake = dir + "/fake-tool"
        fm.createFile(atPath: fake, contents: Data("#!/bin/sh\nexit 0\n".utf8), attributes: [.posixPermissions: 0o755])
        func plist(_ file: String, _ d: [String: Any]) {
            fm.createFile(atPath: dir + "/" + file, contents: try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0))
        }
        plist("com.apple.fake.plist", ["Label": "com.apple.fake", "ProgramArguments": [fake, "--run"]])
        plist("com.apple.real.plist", ["Label": "com.apple.real", "Program": "/usr/bin/true"])
        plist("com.example.other.plist", ["Label": "com.example.other", "Program": fake])
        let items = Disguise.launchItems(in: [dir])
        let signedTrue = Disguise.signer("/usr/bin/true"), signedFake = Disguise.signer(fake), missing = Disguise.signer(dir + "/nothing-here")
        let refuses = !BackgroundAgents.turnOff(BackgroundAgents.Agent(label: "com.apple.never", plist: "/dev/null", program: "/usr/bin/true", owner: "x"), marker: "selftestDisguise-\(getpid())")
        UserDefaults.standard.removeObject(forKey: "selftestDisguise-\(getpid())")
        let r7 = signedTrue == .apple && signedFake == .other && missing == .unknown && items.map(\.label) == ["com.apple.fake", "com.apple.real"]
            && items.first?.signer == .other && items.last?.signer == .apple && refuses
        review.append(("disguise-reads-signatures", r7, "/usr/bin/true \(signedTrue); a file written now \(signedFake); a missing file \(missing); items \(items.map { "\($0.label) \($0.signer)" }); refuses an Apple-signed com.apple item \(refuses)"))

        // Stop and delete: a file Cool Head wrote goes to the Trash (and is taken out again, by the exact name the Trash gave
        // it, so a selftest leaves nothing there); macOS's own programs are refused
        let victim = dir + "/coolhead-selftest-\(UUID().uuidString)"
        fm.createFile(atPath: victim, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        var inTrash: URL?
        let failed = Disguise.moveToTrash([victim]) { inTrash = $0 }
        let wentToTrash = failed.isEmpty && !fm.fileExists(atPath: victim) && inTrash.map { fm.fileExists(atPath: $0.path) } == true
        if let u = inTrash { try? fm.removeItem(at: u) }
        let r8 = wentToTrash && Disguise.refusesTrash(["/usr/bin/true"]) && Disguise.refusesTrash([mdsPath]) && !Disguise.refusesTrash([fake])
        review.append(("disguise-stop-and-trash", r8, "a file Cool Head wrote went to the Trash \(wentToTrash) and was removed from it again; macOS's own refused \(Disguise.refusesTrash(["/usr/bin/true"]))"))
        return review
    }
}

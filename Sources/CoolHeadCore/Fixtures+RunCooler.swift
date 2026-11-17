import Foundation

/// Checks for offering Run it cooler only where it helps (see RunCooler, research rule 14), and the example card
/// `coolhead wording` shows for a virtual machine.
extension Fixture {
    static let qemuPath = "/Applications/UTM.app/Contents/XPCServices/QEMUHelper.xpc/Contents/MacOS/qemu-system-aarch64"

    /// The example card (see Wording).
    static func runCoolerSamples(_ now: Date) -> [(String, Card)] {
        let vm = Evidence.sample(name: "qemu-system-aarch64", path: qemuPath, start: now.addingTimeInterval(-3 * 3600), cores: 2.5)
        return [("virtual-machine", Card.make(vm, now: now, busySince: now.addingTimeInterval(-2 * 3600), warm: true))]
    }

    static func runCoolerChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let start = now.addingTimeInterval(-3 * 3600)
        func card(_ e: Evidence) -> Card { Card.make(e, now: now, busySince: now.addingTimeInterval(-2 * 3600), warm: true) }
        func offers(_ c: Card) -> Bool { c.fixes.contains { $0.kind == .cooler } }

        // offered for your own work above background priority (or not yet read); not once it's already at background
        // priority; never for macOS's own programs
        let tool = Evidence.sample(name: "render", path: "/Users/x/bin/render", start: start, cores: 2)
        var low = tool; low.atBackgroundPriority = true
        var high = tool; high.atBackgroundPriority = false
        let apple = Evidence.sample(name: "someagent", path: "/System/Library/PrivateFrameworks/Some.framework/someagent", start: start, cores: 2)
        let script = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos", start: start, cores: 2)
        let r1 = offers(card(tool)) && offers(card(high)) && !offers(card(low)) && !offers(card(apple)) && offers(card(script))
        review.append(("cooler-only-where-it-helps", r1, "not read \(offers(card(tool))); above background \(offers(card(high))); already background \(offers(card(low))); macOS's own \(offers(card(apple))); a script run by macOS's Python \(offers(card(script)))"))

        // a virtual machine: offered, saying everything inside it slows sharply
        let vm = card(Evidence.sample(name: "qemu-system-aarch64", path: qemuPath, start: start, cores: 2.5)).fixes.first { $0.kind == .cooler }
        let r2 = vm?.consequence == "Everything running inside it slows down sharply. Undo any time." && vm?.recommended == false
            && RunCooler.isVirtualMachine(Evidence.sample(name: "prl_vm_app", path: "/Applications/Parallels Desktop.app/Contents/MacOS/Parallels VM.app/Contents/MacOS/prl_vm_app", start: start, cores: 2))
            && !RunCooler.isVirtualMachine(tool)
        review.append(("cooler-warns-for-virtual-machines", r2, vm?.consequence ?? "not offered"))

        // on this Mac, for real: a busy loop of Cool Head's own reads as above background priority, and the same loop
        // started at background priority (taskpolicy -b) reads as already there
        func loop(background: Bool) -> Bool? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: background ? "/usr/sbin/taskpolicy" : "/bin/sh")
            p.arguments = background ? ["-b", "/bin/sh", "-c", "while :; do :; done"] : ["-c", "while :; do :; done"]
            guard (try? p.run()) != nil else { return nil }
            // a loop at background priority gets little of a busy Mac, and its priority can't be judged until it has used
            // 5% of a core: read every second, for up to 10 seconds, until it can be (it failed now and then on a busy Mac)
            var v: Bool?
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                v = RunCooler.alreadyBackground(p.processIdentifier)
                if v != nil { break }
            }
            p.terminate(); p.waitUntilExit()
            return v
        }
        let normal = loop(background: false), slowed = loop(background: true)
        review.append(("cooler-priority-this-mac", normal == false && slowed == true,
                       "a busy loop: already background \(String(describing: normal)); started with taskpolicy -b: \(String(describing: slowed))"))
        return review
    }
}

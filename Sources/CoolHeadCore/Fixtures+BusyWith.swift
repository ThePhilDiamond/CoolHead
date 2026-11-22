import Foundation

/// Checks for BusyWith: playing sound or downloading holds something back from being paused or stopped; which
/// reading counts; and nettop's and pmset's text read into it.
extension Fixture {
    static func busyWithSamples(_ now: Date) -> [(String, Card)] { [] }

    static func busyWithChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let app: Set<pid_t> = [501, 502, 503]          // an app and two helpers

        // sound: CoreAudio's list when there is one, a helper counts for its app; open but silent doesn't count then;
        // without the list, sound open counts as playing
        let helperPlays = BusyWith.reason(group: app, playing: [502], soundOpen: [], samples: [], now: now)
        let silentOpen = BusyWith.reason(group: app, playing: [], soundOpen: [501], samples: [], now: now)
        let noListOpen = BusyWith.reason(group: app, playing: nil, soundOpen: [501], samples: [], now: now)
        let otherPlays = BusyWith.reason(group: app, playing: [900], soundOpen: [900], samples: [], now: now)
        review.append(("busy-with-sound", helperPlays == .sound && silentOpen == nil && noListOpen == .sound && otherPlays == nil,
                       "helper playing \(String(describing: helperPlays)); open but silent \(String(describing: silentOpen)); no list, open \(String(describing: noListOpen)); another app \(String(describing: otherPlays))"))

        // downloading: at least 100 KB a second in every reading over at least 10 seconds, the group added together
        func readings(_ perSecond: [Double], every: TimeInterval = 5, pid: pid_t = 501) -> [BusyWith.Sample] {
            perSecond.enumerated().map { i, b in
                BusyWith.Sample(at: now.addingTimeInterval(-every * Double(perSecond.count - 1 - i)), bytesIn: [pid: b])
            }
        }
        let steady = BusyWith.downloading(group: app, samples: readings([150_000, 150_000, 150_000]), now: now)
        let slow = BusyWith.downloading(group: app, samples: readings([20_000, 20_000, 20_000]), now: now)
        let burst = BusyWith.downloading(group: app, samples: readings([150_000, 150_000], every: 5), now: now)  // only 5 seconds
        let dip = BusyWith.downloading(group: app, samples: readings([150_000, 30_000, 150_000]), now: now)
        let split = [-10.0, -5, 0].map { BusyWith.Sample(at: now.addingTimeInterval($0), bytesIn: [502: 60_000, 503: 60_000]) }
        let helpers = BusyWith.downloading(group: app, samples: split, now: now)
        let stranger = BusyWith.downloading(group: app, samples: readings([500_000, 500_000, 500_000], pid: 900), now: now)
        let stale = BusyWith.downloading(group: app, samples: readings([150_000, 150_000, 150_000]).map {
            BusyWith.Sample(at: $0.at.addingTimeInterval(-60), bytesIn: $0.bytesIn) }, now: now)
        review.append(("busy-with-download", steady && !slow && !burst && !dip && helpers && !stranger && !stale,
                       "150 KB/s for 10 s \(steady); 20 KB/s \(slow); 5 s only \(burst); a dip \(dip); two helpers at 60 KB/s \(helpers); another app \(stranger); a minute old \(stale)"))

        // both at once: sound is said, as it's the one a person notices
        let both = BusyWith.reason(group: app, playing: [501], soundOpen: [], samples: readings([150_000, 150_000, 150_000]), now: now)
        let dl = BusyWith.reason(group: app, playing: [], soundOpen: [], samples: readings([150_000, 150_000, 150_000]), now: now)
        review.append(("busy-with-sound-first", both == .sound && dl == .download,
                       "both \(String(describing: both)); download only \(String(describing: dl))"))

        // readings older than 30 seconds are forgotten
        var kept: [BusyWith.Sample] = []
        for t in stride(from: -60.0, through: 0, by: 10) { kept = BusyWith.remember(BusyWith.Sample(at: now.addingTimeInterval(t), bytesIn: [:]), in: kept) }
        review.append(("busy-with-forgets", kept.count == 4, "\(kept.count) of 7 readings kept (30 seconds)"))

        // nettop: the second block is the second that was measured; a name with commas and dots is read from the right
        let nettop = """
        ,bytes_in,bytes_out,
        curl.85557,4735129,84,
        Python.85551,84,4735129,
        ,bytes_in,bytes_out,
        curl.85557,606156,0,
        Python.85551,0,606156,
        Huddle, Notes.app helper.4242,120000,10,
        """
        let read = BusyWith.bytesIn(nettop: nettop)
        review.append(("busy-with-nettop", read[85557] == 606_156 && read[85551] == nil && read[4242] == 120_000,
                       "curl \(read[85557] ?? -1); sender only \(String(describing: read[85551])); odd name \(read[4242] ?? -1)"))

        // pmset: macOS's sound service holding the Mac awake for a process means sound is open in it
        let pmset = """
        Listed by owning process:
           pid 411(coreaudiod): [0x0005a34a00019bb4] 00:00:01 PreventUserIdleSystemSleep named: "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep"
        \tCreated for PID: 85607.
           pid 642(Huddle): [0x0000002a00018180] 01:00:00 NoIdleSleepAssertion named: "call"
        No kernel assertions.
        """
        let open = BusyWith.soundOpen(PowerState.parseAssertions(pmset))
        review.append(("busy-with-sound-open", open == [85607], "sound open in \(open.sorted())"))

        // on a card: a job on battery is offered Pause until you plug in; while it plays sound, that's taken away and the
        // card says why; a card with no pause is left as it is
        let job = Evidence.sample(name: "python3", path: "/usr/bin/python3", args: ["python3", "export.py"], cwd: "/Users/x/Photos",
                                  start: now.addingTimeInterval(-2 * 3600), cores: 2)
        let offered = Card.make(job, now: now, busySince: now.addingTimeInterval(-900), battery: 80)
        let held = offered.busyWith(.sound)
        let plugged = Card.make(job, now: now, busySince: now.addingTimeInterval(-900))
        let offeredBefore = offered.fixes.contains { $0.kind == .pauseJob }
        let cardOK = offeredBefore && !held.fixes.contains { $0.kind == .pauseJob } && held.explanation.hasSuffix(BusyWith.sound.cardLine)
            && held.headline == offered.headline && held.fixes.count == offered.fixes.count - 1
            && plugged.busyWith(.download).explanation == plugged.explanation
        review.append(("busy-with-card", cardOK, "offered before \(offeredBefore); after: \(held.explanation)"))

        // at the click: sound read again then; a download from the latest reading alone
        let clickSound = BusyWith.atClick(group: app, playing: [503], soundOpen: [], downloadingNow: false)
        let clickDownload = BusyWith.atClick(group: app, playing: [], soundOpen: [501], downloadingNow: true)
        let clickNothing = BusyWith.atClick(group: app, playing: [], soundOpen: [501], downloadingNow: false)
        review.append(("busy-with-at-click", clickSound == .sound && clickDownload == .download && clickNothing == nil,
                       "sound \(String(describing: clickSound)); downloading now \(String(describing: clickDownload)); neither \(String(describing: clickNothing))"))

        // the words
        let words = BusyWith.sound.cardLine == "Not paused while it's playing sound."
            && BusyWith.download.cardLine == "Not paused while it's downloading."
            && BusyWith.sound.pinnedLine == "Full speed while it's playing sound."
            && BusyWith.download.pinnedLine == "Full speed while it's downloading."
        review.append(("busy-with-words", words, "\(BusyWith.sound.cardLine) / \(BusyWith.download.pinnedLine)"))
        return review
    }
}

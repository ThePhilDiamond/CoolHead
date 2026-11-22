import CoolHeadChromeLink
import Darwin
import Foundation

/// Checks for the link with Cool Head for Chrome (Extension/chrome/PROTOCOL.md): the framing on each side, the
/// messages, Chrome's manifest, and the host itself, run for real against a socket in a temporary folder (never Cool
/// Head's own) to check it relays both ways, says whether Cool Head is there, and refuses a socket that isn't this
/// user's. It has no cards.
extension Fixture {
    static func chromeLinkSamples(_ now: Date) -> [(String, Card)] { [] }

    static func chromeLinkChecks(_ now: Date) -> [(String, Bool, String)] {
        var review: [(String, Bool, String)] = []
        let bytes = { (s: String) in Array(s.utf8) }
        let limit = ChromeLink.maxMessageBytes

        // Chrome's framing: messages back out as they went in, however the reads split them, the length included
        let messages = [bytes(#"{"v":1,"type":"hello","extension":"0.1.0","browser":"chrome","level":"auto"}"#), [],
                        bytes(#"{"v":1,"type":"result","id":"r1","ok":true,"done":"Put 23 tabs to sleep. Café","count":23}"#),
                        [UInt8](repeating: 0x20, count: limit)]
        let stream = messages.compactMap(ChromeLink.frame).flatMap { $0 }
        func readAll(_ chunk: Int) -> [[UInt8]] {
            var r = ChromeLink.FrameReader(), out: [[UInt8]] = []
            var i = 0
            while i < stream.count {
                r.append(stream[i ..< min(i + chunk, stream.count)])
                i += chunk
                while let m = r.next() { out.append(m) }
            }
            return out
        }
        let whole = readAll(stream.count), oneByte = readAll(1), threes = readAll(3)
        let header = ChromeLink.frame(bytes("{}")) ?? []
        review.append(("chrome-link-framing", whole == messages && oneByte == messages && threes == messages
                       && header == [2, 0, 0, 0, 0x7B, 0x7D] && ChromeLink.frame([]) == [0, 0, 0, 0],
                       "4 messages (one empty, one exactly 1 MB) read back whole, a byte at a time, and 3 bytes at a time"))

        // over 1 MB: never sent, and passed over from Chrome without losing the message after it
        var big = ChromeLink.FrameReader()
        let n = limit + 1
        let oversized = [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24)] + [UInt8](repeating: 0x78, count: n)
        let after = bytes(#"{"v":1,"type":"report"}"#)
        let tooBig = oversized + (ChromeLink.frame(after) ?? [])
        var got: [[UInt8]] = []
        var j = 0
        while j < tooBig.count {
            big.append(tooBig[j ..< min(j + 4099, tooBig.count)])
            j += 4099
            while let m = big.next() { got.append(m) }
        }
        var partial = ChromeLink.FrameReader()
        partial.append([5, 0])
        let waits = partial.next() == nil
        partial.append([0, 0, 0x31, 0x32])
        let stillWaits = partial.next() == nil
        partial.append([0x33, 0x34, 0x35])
        review.append(("chrome-link-framing-limits", ChromeLink.frame([UInt8](repeating: 0, count: limit + 1)) == nil
                       && got == [after] && big.refused == 1 && waits && stillWaits && partial.next() == bytes("12345") && partial.next() == nil,
                       "a message over 1 MB isn't framed, one from Chrome is skipped (\(big.refused)) and the next still read; a part message waits"))

        // the socket's lines: split anywhere, carriage returns and empty lines dropped, an oversized line passed over
        var lines = ChromeLink.LineReader(), readLines: [[UInt8]] = []
        for part in ["{\"a\":1}\n{\"b\"", ":2}\r\n\n\n{\"c\":", "3}"] {
            lines.append(bytes(part))
            while let l = lines.next() { readLines.append(l) }
        }
        let beforeEnd = readLines
        lines.append([0x0A])
        while let l = lines.next() { readLines.append(l) }
        var longLines = ChromeLink.LineReader(), longOut: [[UInt8]] = []
        longLines.append([UInt8](repeating: 0x78, count: limit + 10))
        while let l = longLines.next() { longOut.append(l) }
        longLines.append(bytes("xx\n{\"d\":4}\n"))
        while let l = longLines.next() { longOut.append(l) }
        review.append(("chrome-link-lines", beforeEnd == [bytes("{\"a\":1}"), bytes("{\"b\":2}")]
                       && readLines == [bytes("{\"a\":1}"), bytes("{\"b\":2}"), bytes("{\"c\":3}")]
                       && longOut == [bytes("{\"d\":4}")] && longLines.refused == 1
                       && ChromeLink.line(bytes("{}")) == bytes("{}\n") && ChromeLink.line([]) == nil
                       && ChromeLink.line(bytes("{\n}")) == nil && ChromeLink.line([UInt8](repeating: 0x20, count: limit + 1)) == nil,
                       "lines read across splits; a line over 1 MB skipped; a message with a line break, empty, or over 1 MB isn't sent"))

        // messages: fields and words this side doesn't know are ignored; another version or type isn't read
        let newer = bytes(#"{"v":1,"type":"report","asleep":4,"held":{"sound":1,"pinned":2,"hologram":1},"session":{"active":true,"tabs":9,"name":"x"},"#
                          + #""duplicates":3,"extensionsResting":2,"level":"turbo","future":{"a":[1,2]}}"#)
        let report = ChromeLink.decode(ChromeLink.Report.self, from: newer)
        let request = ChromeLink.decode(ChromeLink.Request.self, from: bytes(#"{"v":1,"type":"request","id":"q7","action":"teleport","extra":true}"#))
        let v2 = bytes(#"{"v":2,"type":"link","app":"running"}"#)
        let link = ChromeLink.encode(ChromeLink.Link(app: .running))
        let state = ChromeLink.encode(ChromeLink.State(memory: .slowed, freeMB: 812, chromeMB: 4100, hiddenTabsMB: nil, extensionsMB: 300, auto: true))
        let stateText = String(decoding: state, as: UTF8.self)
        let roundTrips = ChromeLink.decode(ChromeLink.State.self, from: state)?.memory == .slowed
            && ChromeLink.decode(ChromeLink.ActionResult.self, from: ChromeLink.encode(ChromeLink.ActionResult(id: "r1", ok: true, done: "Put 23 tabs to sleep.", count: 23)))?.count == 23
            && ChromeLink.decode(ChromeLink.ExtensionHello.self, from: messages[0]) == ChromeLink.ExtensionHello(extension: "0.1.0", browser: "chrome", level: .auto)
            && ChromeLink.decode(ChromeLink.AppHello.self, from: ChromeLink.encode(ChromeLink.AppHello(app: "0.15.0")))?.app == "0.15.0"
        review.append(("chrome-link-messages", report?.asleep == 4 && report?.held["hologram"] == 1 && report?.session.tabs == 9 && report?.level == .unknown
                       && request?.action == .unknown && request?.id == "q7"
                       && ChromeLink.decode(ChromeLink.Link.self, from: v2) == nil && ChromeLink.type(of: v2) == nil
                       && ChromeLink.decode(ChromeLink.Link.self, from: newer) == nil && ChromeLink.type(of: bytes("[1]")) == nil
                       && link == bytes(#"{"app":"running","type":"link","v":1}"#)
                       && stateText.contains(#""hiddenTabsMB":null"#) && stateText.contains(#""extensionsMB":300"#) && roundTrips,
                       "unknown fields, a new held reason, a new level, and a new action read; version 2 ignored; " + String(decoding: link, as: UTF8.self)))

        // Chrome's manifest: its name, stdio, the host's absolute path, and only our extension
        let id = "abcdefghijklmnopabcdefghijklmnop"
        let hostPath = "/Applications/Cool Head.app/Contents/Helpers/coolhead-chrome-host"
        let manifest = ChromeLink.manifest(hostPath: hostPath, extensionID: id)
        let parsed = manifest.flatMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        review.append(("chrome-link-manifest", parsed?["name"] as? String == "io.github.thephildiamond.coolhead" && parsed?["type"] as? String == "stdio"
                       && parsed?["path"] as? String == hostPath && parsed?["allowed_origins"] as? [String] == ["chrome-extension://\(id)/"]
                       && !(parsed?["description"] as? String ?? "").isEmpty && parsed?.count == 5
                       && ChromeLink.manifest(hostPath: "Cool Head.app/Contents/Helpers/coolhead-chrome-host", extensionID: id) == nil
                       && ChromeLink.manifest(hostPath: hostPath, extensionID: "ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP") == nil
                       && ChromeLink.manifest(hostPath: hostPath, extensionID: "abcdefghijklmnopabcdefghijklmnoq") == nil,
                       manifest.map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "\n", with: " ") } ?? "no manifest"))

        // the socket: Cool Head's own folder, unless the selftest gives one; the quick retry only with the selftest's socket
        let home = "/Users/someone"
        review.append(("chrome-link-socket-path", ChromeLink.socketPath(home: home) == "/Users/someone/Library/Application Support/Cool Head/chrome-link.sock"
                       && ChromeLink.socketPath(environment: [ChromeLink.socketVariable: "/tmp/x.sock"], home: home) == "/tmp/x.sock"
                       && ChromeLink.socketPath(environment: [ChromeLink.socketVariable: "x.sock"], home: home) == ChromeLink.socketPath(home: home)
                       && ChromeLink.retryInterval(environment: [:]) == 10 && ChromeLink.retryInterval(environment: [ChromeLink.retryVariable: "0.2"]) == 10
                       && ChromeLink.retryInterval(environment: [ChromeLink.socketVariable: "/tmp/x.sock", ChromeLink.retryVariable: "0.2"]) == 0.2
                       && ChromeLink.retryInterval(environment: [ChromeLink.socketVariable: "/tmp/x.sock", ChromeLink.retryVariable: "0"]) == 10,
                       ChromeLink.socketPath(home: home)))

        review += chromeHostChecks()
        return review
    }

    // MARK: The host, run for real

    /// The built host: beside this program (in .build), or in the app's Helpers folder (beside Contents/MacOS).
    static func chromeHostPath() -> String? {
        let me = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        return [me.appendingPathComponent("coolhead-chrome-host"), me.appendingPathComponent("../Helpers/coolhead-chrome-host")]
            .map { $0.standardizedFileURL.path }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// One run of the host, with Chrome's side played by the selftest through pipes.
    final class HostRun {
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        var frames = ChromeLink.FrameReader()

        init?(_ host: String, socket: String) {
            process.executableURL = URL(fileURLWithPath: host)
            // only the test's socket and a quick retry: nothing of this Mac's own environment
            process.environment = [ChromeLink.socketVariable: socket, ChromeLink.retryVariable: "0.2"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            // a host that has gone makes a write fail, rather than end the selftest
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            guard (try? process.run()) != nil else { return nil }
        }

        func send(_ bytes: [UInt8]) -> Bool { ChromeLink.writeAll(input.fileHandleForWriting.fileDescriptor, bytes) }

        /// The next message the host sends Chrome, or nil if none comes within the time.
        func receive(within seconds: Double = 3) -> [UInt8]? {
            Fixture.pump(output.fileHandleForReading.fileDescriptor, within: seconds, next: { frames.next() }, feed: { frames.append($0) })
        }

        /// Closes Chrome's side, as Chrome does when the extension disconnects; true if the host then ends cleanly,
        /// having printed nothing.
        func finish() -> Bool {
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { usleep(20_000) }
            if process.isRunning { process.terminate(); return false }
            let printed = (try? errors.fileHandleForReading.readToEnd()) ?? nil
            return process.terminationStatus == 0 && (printed ?? Data()).isEmpty
        }
    }

    /// Reads from a descriptor into a reader until it gives a message, or the time runs out.
    static func pump(_ fd: Int32, within seconds: Double, next: () -> [UInt8]?, feed: ([UInt8]) -> Void) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let m = next() { return m }
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { return nil }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(left * 1000) + 1)
            if r < 0 && errno == EINTR { continue }
            guard r > 0 else { return nil }
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { return nil }
            feed(Array(buffer[0 ..< n]))
        }
    }

    /// A connection to the test socket, accepted within the time.
    static func acceptConnection(_ listener: Int32, within seconds: Double = 3) -> Int32? {
        var p = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, Int32(seconds * 1000)) > 0 else { return nil }
        return ChromeLink.accept(listener)
    }

    static func chromeHostChecks() -> [(String, Bool, String)] {
        guard let host = chromeHostPath() else {
            return [("chrome-link-host", false, "coolhead-chrome-host isn't beside coolhead; build it with swift build -c release")]
        }
        // a folder of the selftest's own, 700, in the temporary folder, so Cool Head's real socket is never touched
        var template = Array((NSTemporaryDirectory() as NSString).appendingPathComponent("coolhead-link-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else { return [("chrome-link-host", false, "no temporary folder")] }
        let folder = String(cString: made)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let socket = folder + "/link.sock"
        let bytes = { (s: String) in Array(s.utf8) }
        let running = ChromeLink.encode(ChromeLink.Link(app: .running)), notRunning = ChromeLink.encode(ChromeLink.Link(app: .notRunning))
        var out: [(String, Bool, String)] = []

        // Cool Head not running: the host says so first, and ends when Chrome closes its side
        if let run = HostRun(host, socket: socket) {
            let first = run.receive()
            out.append(("chrome-link-host-not-running", first == notRunning && run.finish(),
                        first.map { String(decoding: $0, as: UTF8.self) } ?? "nothing from the host"))
        } else { out.append(("chrome-link-host-not-running", false, "the host didn't start")) }

        guard let listener = ChromeLink.listen(at: socket) else { return out + [("chrome-link-host-relay", false, "couldn't listen at \(socket)")] }
        defer { close(listener) }

        // running: relays both ways, byte for byte, and drops what it can't relay
        if let run = HostRun(host, socket: socket), let conn = acceptConnection(listener) {
            var notes: [String] = []
            let first = run.receive()
            let hello = bytes(#"{"v":1,"type":"hello","extension":"0.1.0","browser":"chrome","level":"auto"}"#)
            let result = bytes(#"{"v":1,"type":"result","id":"r1","ok":true,"done":"Put 23 tabs to sleep. Café","count":23}"#)
            let framedHello = ChromeLink.frame(hello) ?? []
            let n = ChromeLink.maxMessageBytes + 1
            var sent = run.send(Array(framedHello[0 ..< 2]))
            usleep(50_000)
            sent = sent && run.send(Array(framedHello[2 ..< 6]))
            usleep(50_000)
            sent = sent && run.send(Array(framedHello[6...])) && run.send([0, 0, 0, 0])
                && run.send([UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24)] + [UInt8](repeating: 0x78, count: n))
                && run.send(ChromeLink.frame(bytes("{\"v\":1,\n\"type\":\"report\"}")) ?? []) && run.send(ChromeLink.frame(result) ?? [])
            var lines = ChromeLink.LineReader()
            let line1 = pump(conn, within: 3, next: { lines.next() }, feed: { lines.append($0) })
            let line2 = pump(conn, within: 3, next: { lines.next() }, feed: { lines.append($0) })
            let nothingMore = pump(conn, within: 0.3, next: { lines.next() }, feed: { lines.append($0) }) == nil
            let toApp = sent && line1 == hello && line2 == result && nothingMore
            if !toApp { notes.append("to Cool Head: \([line1, line2].map { $0.map { String(decoding: $0, as: UTF8.self) } ?? "nothing" })") }

            let appHello = bytes(#"{"v":1,"type":"hello","app":"0.15.0"}"#)
            let state = ChromeLink.encode(ChromeLink.State(memory: .tight, freeMB: 900, chromeMB: 3000, hiddenTabsMB: 700, extensionsMB: nil, auto: false))
            var written = ChromeLink.writeAll(conn, appHello + bytes("\r\n\n") + Array(state[0 ..< 10]))
            usleep(50_000)
            // built in steps: as one expression it was too slow for the build machine's type checker
            let lf: [UInt8] = [0x0A]
            let tooBig = [UInt8](repeating: 0x78, count: ChromeLink.maxMessageBytes + 1)
            var rest: [UInt8] = Array(state[10...])
            rest += lf; rest += tooBig; rest += lf; rest += appHello; rest += lf
            written = written && ChromeLink.writeAll(conn, rest)
            let m1 = run.receive(), m2 = run.receive(), m3 = run.receive()
            let toChrome = written && m1 == appHello && m2 == state && m3 == appHello
            if !toChrome { notes.append("to Chrome: \([m1, m2, m3].map { $0.map { String(decoding: $0, as: UTF8.self) } ?? "nothing" })") }
            out.append(("chrome-link-host-relay", first == running && toApp && toChrome,
                        notes.isEmpty ? "said running, then relayed 2 messages each way unchanged and dropped an empty one, a 1 MB one, and one with a line break"
                                      : notes.joined(separator: "; ")))

            // Cool Head quits: the host says so, tries again, and links again when it's back
            close(conn)
            let dropped = run.receive()
            let again = acceptConnection(listener)
            let relinked = again != nil ? run.receive() : nil
            var relayedAgain = false
            if let again {
                var l = ChromeLink.LineReader()
                relayedAgain = run.send(framedHello) && pump(again, within: 3, next: { l.next() }, feed: { l.append($0) }) == hello
            }
            let ended = run.finish()
            if let again { close(again) }
            out.append(("chrome-link-host-reconnect", dropped == notRunning && relinked == running && relayedAgain && ended,
                        "after the socket closed: \(dropped.map { String(decoding: $0, as: UTF8.self) } ?? "nothing"), then "
                        + "\(relinked.map { String(decoding: $0, as: UTF8.self) } ?? "no reconnect"); relays again: \(relayedAgain); ended cleanly: \(ended)"))
        } else { out.append(("chrome-link-host-relay", false, "the host didn't start or didn't connect")) }

        // a socket other users could reach, or a link to the socket, isn't Cool Head's: the host doesn't connect until
        // the socket is closed to others again
        chmod(socket, 0o666)
        let alias = folder + "/alias.sock"
        symlink(socket, alias)
        if let open = HostRun(host, socket: socket), let linked = HostRun(host, socket: alias) {
            let refusedOpen = open.receive(), refusedLink = linked.receive()
            var p = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let noneConnected = poll(&p, 1, 400) == 0
            chmod(socket, 0o600)
            let conn = acceptConnection(listener)
            let later = conn != nil ? open.receive() : nil
            let linkStill = linked.receive(within: 0.5) == nil
            let ended = open.finish() && linked.finish()
            if let conn { close(conn) }
            out.append(("chrome-link-host-this-user-only", refusedOpen == notRunning && refusedLink == notRunning && noneConnected
                        && later == running && linkStill && ended,
                        "a socket open to others and a link to the socket: refused, nothing connected (\(noneConnected)); "
                        + "once the socket is 600 again: \(later.map { String(decoding: $0, as: UTF8.self) } ?? "no link")"))
        } else { out.append(("chrome-link-host-this-user-only", false, "the host didn't start")) }
        return out
    }
}

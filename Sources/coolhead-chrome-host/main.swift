import CoolHeadChromeLink
import Darwin
import Foundation

// Cool Head for Chrome's native messaging host (Extension/chrome/PROTOCOL.md). Chrome starts a copy of this program
// for each connection the extension opens, and closes its input when the extension disconnects or Chrome quits.
//
// It relays each message unchanged between Chrome (its input and output, in Chrome's framing) and the running Cool
// Head (a Unix socket in Cool Head's own folder, a line per message), and adds only one message of its own: whether
// Cool Head is there. It reads and writes no files, uses no network, starts no programs, and prints nothing, so no
// log Chrome keeps can name a page; a message it can't relay is dropped without a word.
//
// One thread, waiting on both sides at once with poll(2), so there is nothing to share between threads.

struct Relay {
    let path: String
    let retryNanoseconds: UInt64
    var socket: Int32 = -1
    var fromChrome = ChromeLink.FrameReader()
    var fromApp = ChromeLink.LineReader()
    var said: ChromeLink.AppState?
    var nextTry: UInt64 = 0

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

    /// To Chrome. If Chrome has gone, there is no one left to relay for, so the host ends.
    func toChrome(_ message: [UInt8]) {
        guard let framed = ChromeLink.frame(message) else { return }
        if !ChromeLink.writeAll(STDOUT_FILENO, framed) { exit(0) }
    }

    /// Tells the extension whether Cool Head is there: first, and then only when it changes.
    mutating func say(_ state: ChromeLink.AppState) {
        guard state != said else { return }
        said = state
        toChrome(ChromeLink.encode(ChromeLink.Link(app: state)))
    }

    mutating func tryConnecting() {
        if let fd = ChromeLink.connect(to: path) {
            socket = fd
            fromApp = ChromeLink.LineReader()
            say(.running)
        } else {
            say(.notRunning)
            nextTry = Relay.now() + retryNanoseconds
        }
    }

    /// Cool Head quit, or stopped reading: say so, and try again after the usual wait.
    mutating func dropSocket() {
        close(socket)
        socket = -1
        say(.notRunning)
        nextTry = Relay.now() + retryNanoseconds
    }

    mutating func run() -> Never {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if socket < 0 && Relay.now() >= nextTry { tryConnecting() }
            // poll leaves out a negative descriptor, so the socket's slot is simply ignored while there is none
            var fds = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0), pollfd(fd: socket, events: Int16(POLLIN), revents: 0)]
            let wait: Int32
            if socket >= 0 { wait = -1 } else {
                let left = nextTry > Relay.now() ? nextTry - Relay.now() : 0
                wait = Int32(clamping: left / 1_000_000 + 1)
            }
            if poll(&fds, 2, wait) < 0 {
                if errno == EINTR { continue }
                exit(1)
            }

            if fds[0].revents != 0 {
                let n = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
                if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                // Chrome closed the connection: nothing more to relay
                if n <= 0 { exit(0) }
                fromChrome.append(buffer[0 ..< n])
                while let message = fromChrome.next() {
                    // without Cool Head there is no one to tell; the extension knows from the link message
                    guard socket >= 0, let line = ChromeLink.line(message) else { continue }
                    if !ChromeLink.writeAll(socket, line) { dropSocket() }
                }
            }

            if socket >= 0 && fds[1].revents != 0 {
                let n = buffer.withUnsafeMutableBytes { read(socket, $0.baseAddress, $0.count) }
                if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                if n <= 0 { dropSocket(); continue }
                fromApp.append(buffer[0 ..< n])
                while let line = fromApp.next() { toChrome(line) }
            }
        }
    }
}

// a write to a closed pipe or socket returns an error instead of ending the program, so each is handled above
signal(SIGPIPE, SIG_IGN)
let environment = ProcessInfo.processInfo.environment
var relay = Relay(path: ChromeLink.socketPath(environment: environment, home: NSHomeDirectory()),
                  retryNanoseconds: UInt64(ChromeLink.retryInterval(environment: environment) * 1_000_000_000))
relay.run()

import Foundation

/// The link between Cool Head and Cool Head for Chrome, version 1 (notes/chrome-link-protocol.md): how a message is
/// framed on each side, what each message holds, where Cool Head's socket is, and the file that tells Chrome where the
/// host is. Nothing here reads or writes anything; the host (Sources/coolhead-chrome-host) and the app do, and the
/// socket calls are in ChromeLinkSocket.swift.
///
/// The host relays each message unchanged. It only reframes it: Chrome's native messaging on one side, one JSON
/// object per line on the other, so the app can read the socket a line at a time.
public enum ChromeLink {
    public static let version = 1
    /// The native messaging host's name, which the extension passes to `chrome.runtime.connectNative`.
    public static let hostName = "io.github.thephildiamond.coolhead"
    /// Chrome refuses a message over 1 MB from a host, and we hold Chrome's side and the socket to the same: nothing
    /// either side sends comes near it, so a larger length means a broken stream, not a message to wait for.
    public static let maxMessageBytes = 1 << 20
    /// While Cool Head isn't running, the host tries its socket this often, so opening Cool Head later links them.
    public static let retrySeconds = 10.0

    /// For the selftest: a socket path that replaces Cool Head's own, so the test never touches the real one.
    public static let socketVariable = "COOLHEAD_CHROME_LINK_SOCKET"
    /// For the selftest, and honored only with `socketVariable`: seconds between tries, so a reconnect is tested quickly.
    public static let retryVariable = "COOLHEAD_CHROME_LINK_RETRY"

    /// Cool Head's socket, in its own folder (the folder is 700 and the socket 600, so no other user can reach it).
    public static func socketPath(home: String) -> String {
        home + "/Library/Application Support/Cool Head/chrome-link.sock"
    }

    /// The socket to use: the selftest's, when it sets an absolute path, otherwise Cool Head's own.
    public static func socketPath(environment: [String: String], home: String) -> String {
        if let p = environment[socketVariable], p.hasPrefix("/") { return p }
        return socketPath(home: home)
    }

    /// Seconds between tries: 10, unless the selftest asks for less (between 0.05 and 10) along with its own socket.
    public static func retryInterval(environment: [String: String]) -> Double {
        guard environment[socketVariable] != nil, let s = environment[retryVariable].flatMap(Double.init),
              s >= 0.05, s <= retrySeconds else { return retrySeconds }
        return s
    }

    // MARK: Chrome's framing

    /// A message as Chrome's native messaging carries it: its length in 4 bytes, least significant first, then the
    /// message. Nil when it's over the limit, since Chrome would refuse it and close the connection.
    public static func frame(_ message: [UInt8]) -> [UInt8]? {
        guard message.count <= maxMessageBytes else { return nil }
        let n = UInt32(message.count)
        return [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24)] + message
    }

    /// Reads Chrome's framed messages from bytes as they arrive, however a read splits them, the length included.
    /// A message over the limit is passed over: its bytes are dropped as they come and the next message is read as
    /// normal, so one bad message doesn't end the link.
    public struct FrameReader: Sendable {
        private var buffer: [UInt8] = []
        private var start = 0          // where the unread bytes begin, so reading doesn't copy the rest each time
        private var skipping = 0       // bytes still to drop from an oversized message
        /// How many oversized messages were passed over.
        public private(set) var refused = 0

        public init() {}

        public mutating func append<S: Sequence>(_ bytes: S) where S.Element == UInt8 { buffer.append(contentsOf: bytes) }

        /// The next whole message, or nil until more bytes arrive.
        public mutating func next() -> [UInt8]? {
            while true {
                if skipping > 0 {
                    let n = min(skipping, buffer.count - start)
                    start += n
                    skipping -= n
                    compact()
                    if skipping > 0 { return nil }
                }
                guard buffer.count - start >= 4 else { return nil }
                let b = buffer[start ..< start + 4].map(Int.init)
                let length = b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24
                if length > ChromeLink.maxMessageBytes {
                    start += 4
                    skipping = length
                    refused += 1
                    continue
                }
                guard buffer.count - start - 4 >= length else { return nil }
                let message = Array(buffer[start + 4 ..< start + 4 + length])
                start += 4 + length
                compact()
                return message
            }
        }

        private mutating func compact() {
            if start == buffer.count { buffer.removeAll(keepingCapacity: true); start = 0 }
            else if start > 65_536 && start * 2 > buffer.count { buffer.removeFirst(start); start = 0 }
        }
    }

    // MARK: The socket's lines

    /// A message as one line for the socket. Nil when it's empty, over the limit, or holds a line break: valid JSON
    /// never needs a raw line break (one inside a string is written `\n`), and relaying one would split the message in
    /// two for the app.
    public static func line(_ message: [UInt8]) -> [UInt8]? {
        guard !message.isEmpty, message.count <= maxMessageBytes, !message.contains(0x0A) else { return nil }
        return message + [0x0A]
    }

    /// Reads lines from the socket as bytes arrive. Skips empty lines and drops a carriage return before a line feed;
    /// a line over the limit is passed over up to its line feed, and the next line is read as normal.
    public struct LineReader: Sendable {
        private var buffer: [UInt8] = []
        private var start = 0
        private var scanned = 0        // where to look for the next line feed, so no byte is searched twice
        private var discarding = false // inside an oversized line, until its line feed
        /// How many oversized lines were passed over.
        public private(set) var refused = 0

        public init() {}

        public mutating func append<S: Sequence>(_ bytes: S) where S.Element == UInt8 { buffer.append(contentsOf: bytes) }

        /// The next line, without its line feed, or nil until more bytes arrive.
        public mutating func next() -> [UInt8]? {
            while true {
                guard let end = buffer[max(start, scanned)...].firstIndex(of: 0x0A) else {
                    scanned = buffer.count
                    if !discarding && buffer.count - start > ChromeLink.maxMessageBytes {
                        discarding = true
                        refused += 1
                    }
                    if discarding { start = buffer.count; compact() }
                    return nil
                }
                var line = buffer[start ..< end]
                start = end + 1
                scanned = start
                if line.last == 0x0D { line = line.dropLast() }
                let wasDiscarding = discarding
                discarding = false
                if wasDiscarding || line.isEmpty { compact(); continue }
                if line.count > ChromeLink.maxMessageBytes { refused += 1; compact(); continue }
                let out = Array(line)
                compact()
                return out
            }
        }

        private mutating func compact() {
            if start == buffer.count { buffer.removeAll(keepingCapacity: true); start = 0; scanned = 0 }
            else if start > 65_536 && start * 2 > buffer.count {
                buffer.removeFirst(start); scanned -= start; start = 0
            }
        }
    }

    // MARK: Messages

    /// A word from a fixed list that the other side may add to. One this side doesn't know reads as `unknown`, so a
    /// newer extension or app doesn't make a whole message unreadable.
    public protocol Word: RawRepresentable, Codable, Sendable, Equatable where RawValue == String {
        static var unknown: Self { get }
    }

    /// Every message has the link's version and its type; the rest is the type's own.
    public protocol Message: Codable, Sendable, Equatable {
        static var kind: String { get }
        var v: Int { get }
        var type: String { get }
    }

    /// Whether Cool Head's socket answered. Sent by the host first, and again whenever that changes.
    public enum AppState: String, Word { case running, notRunning, unknown }
    /// The extension's level: Auto follows Cool Head's reading of the Mac.
    public enum Level: String, Word { case auto, light, balanced, focus, unknown }
    /// Cool Head's reading of memory; `slowed` is its gate: macOS has said warning or critical for a minute and memory
    /// is moving to disk.
    public enum Memory: String, Word { case fine, tight, slowed, veryTight, unknown }
    /// What Cool Head's card buttons ask the extension to do.
    public enum Action: String, Word {
        case sleepHidden, closeDuplicates, hideUnusedGroups, restExtensions, openExtensionsList, openPopup, unknown
    }

    /// From the host itself.
    public struct Link: Message {
        public static let kind = "link"
        public var v = ChromeLink.version
        public var type = Link.kind
        public var app: AppState
        public init(app: AppState) { self.app = app }
    }

    /// Extension to Cool Head, when it connects.
    public struct ExtensionHello: Message {
        public static let kind = "hello"
        public var v = ChromeLink.version
        public var type = ExtensionHello.kind
        public var `extension`: String
        public var browser: String
        public var level: Level
        public init(extension e: String, browser: String, level: Level) { self.extension = e; self.browser = browser; self.level = level }
    }

    /// Extension to Cool Head, at most every 10 seconds and on change: counts only, never an address or a title.
    public struct Report: Message {
        public struct Session: Codable, Sendable, Equatable {
            public var active: Bool
            public var tabs: Int
            public init(active: Bool, tabs: Int) { self.active = active; self.tabs = tabs }
        }
        public static let kind = "report"
        public var v = ChromeLink.version
        public var type = Report.kind
        public var asleep: Int
        /// Tabs held in memory, by reason: sound, call, screen, typing, pinned, kept, session.
        public var held: [String: Int]
        public var session: Session
        public var duplicates: Int
        public var extensionsResting: Int
        public var level: Level
        public init(asleep: Int, held: [String: Int], session: Session, duplicates: Int, extensionsResting: Int, level: Level) {
            self.asleep = asleep; self.held = held; self.session = session; self.duplicates = duplicates
            self.extensionsResting = extensionsResting; self.level = level
        }
    }

    /// Extension to Cool Head: what a request did, in a short sentence in Cool Head's voice.
    public struct ActionResult: Message {
        public static let kind = "result"
        public var v = ChromeLink.version
        public var type = ActionResult.kind
        public var id: String
        public var ok: Bool
        public var done: String
        public var count: Int?
        public init(id: String, ok: Bool, done: String, count: Int?) { self.id = id; self.ok = ok; self.done = done; self.count = count }
    }

    /// Cool Head to the extension, when it connects.
    public struct AppHello: Message {
        public static let kind = "hello"
        public var v = ChromeLink.version
        public var type = AppHello.kind
        public var app: String
        public init(app: String) { self.app = app }
    }

    /// Cool Head to the extension, every 10 seconds and on change.
    public struct State: Message {
        public static let kind = "state"
        public var v = ChromeLink.version
        public var type = State.kind
        public var memory: Memory
        public var freeMB: Int
        public var chromeMB: Int
        public var hiddenTabsMB: Int?
        public var extensionsMB: Int?
        /// The person lets Auto follow Cool Head.
        public var auto: Bool
        public init(memory: Memory, freeMB: Int, chromeMB: Int, hiddenTabsMB: Int?, extensionsMB: Int?, auto: Bool) {
            self.memory = memory; self.freeMB = freeMB; self.chromeMB = chromeMB
            self.hiddenTabsMB = hiddenTabsMB; self.extensionsMB = extensionsMB; self.auto = auto
        }

        enum CodingKeys: String, CodingKey { case v, type, memory, freeMB, chromeMB, hiddenTabsMB, extensionsMB, auto }

        // the link writes null for a figure Cool Head doesn't have, rather than leaving it out
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(v, forKey: .v); try c.encode(type, forKey: .type); try c.encode(memory, forKey: .memory)
            try c.encode(freeMB, forKey: .freeMB); try c.encode(chromeMB, forKey: .chromeMB)
            try c.encode(hiddenTabsMB, forKey: .hiddenTabsMB); try c.encode(extensionsMB, forKey: .extensionsMB)
            try c.encode(auto, forKey: .auto)
        }
    }

    /// Cool Head to the extension, from a card's button; the extension answers with an `ActionResult` of the same id.
    public struct Request: Message {
        public static let kind = "request"
        public var v = ChromeLink.version
        public var type = Request.kind
        public var id: String
        public var action: Action
        public init(id: String, action: Action) { self.id = id; self.action = action }
    }

    struct Envelope: Decodable { let v: Int; let type: String }

    /// A message's type, if it's a JSON object of this version of the link; nil for anything else, which is ignored.
    public static func type(of message: [UInt8]) -> String? {
        guard let e = try? JSONDecoder().decode(Envelope.self, from: Data(message)), e.v == version else { return nil }
        return e.type
    }

    /// A message of this type and version, ignoring fields this side doesn't know; nil for anything else.
    public static func decode<M: Message>(_ kind: M.Type, from message: [UInt8]) -> M? {
        guard type(of: message) == M.kind else { return nil }
        return try? JSONDecoder().decode(M.self, from: Data(message))
    }

    public static func encode<M: Message>(_ message: M) -> [UInt8] {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // every field is a string, number, bool, or null, which always encode
        return Array((try? e.encode(message)) ?? Data())
    }

    // MARK: Chrome's manifest

    /// Whether this is an extension ID as Chrome writes one: 32 letters from a to p.
    public static func isExtensionID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (0x61 ... 0x70).contains($0) }
    }

    struct Manifest: Encodable {
        let name: String
        let description: String
        let path: String
        let type: String
        let allowedOrigins: [String]
        enum CodingKeys: String, CodingKey { case name, description, path, type, allowedOrigins = "allowed_origins" }
    }

    /// The file Chrome reads to find the host (`io.github.thephildiamond.coolhead.json` in its NativeMessagingHosts
    /// folder): the host's absolute path, and the one extension allowed to start it. Nil for a relative path or a
    /// malformed ID, since Chrome would refuse the file.
    public static func manifest(hostPath: String, extensionID: String) -> [UInt8]? {
        guard hostPath.hasPrefix("/"), isExtensionID(extensionID) else { return nil }
        let m = Manifest(name: hostName, description: "Links Cool Head for Chrome with the Cool Head app on this Mac.",
                         path: hostPath, type: "stdio", allowedOrigins: ["chrome-extension://\(extensionID)/"])
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(m)).map { Array($0) + [0x0A] }
    }
}

extension ChromeLink.Word {
    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: s) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

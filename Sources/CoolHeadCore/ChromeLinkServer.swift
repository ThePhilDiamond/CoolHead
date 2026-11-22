import Darwin
import Foundation
import CoolHeadChromeLink

/// Cool Head's end of the link with Cool Head for Chrome (notes/chrome-link-protocol.md; Phil, 21 November 2026: "The
/// goal is that the extension in Chrome can help optimize there, but can also talk to the app on the computer that
/// knows what resources the computer has free and can make decisions together based on user preferences", then "So
/// both the app and the Chrome extension should be able to work independently or together").
///
/// It listens on a socket only this user can open (ChromeLink.listen checks the socket's mode, accept checks the peer).
/// Chrome starts the helper (coolhead-chrome-host) for each Chrome profile that has the extension, and the helper
/// relays each message unchanged, so there may be several connections at once. Cool Head sends its reading of memory
/// every 10 seconds; the extension sends counts only (tabs asleep, held tabs by reason), never an address or a title.
/// If Cool Head quits, the extension carries on alone; when it opens again, the helper links them within 10 seconds.
public final class ChromeLinkServer: @unchecked Sendable {
    public static let shared = ChromeLinkServer()

    /// What the extension last said, for the card and Settings.
    public struct Summary: Equatable, Sendable {
        public var connected = false
        public var report: ChromeLink.Report?
        public init(connected: Bool = false, report: ChromeLink.Report? = nil) { self.connected = connected; self.report = report }
    }

    private let queue = DispatchQueue(label: "coolhead.chrome-link")
    private var listener: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private final class Connection {
        let fd: Int32
        var reader = ChromeLink.LineReader()
        var source: DispatchSourceRead?
        var hello: ChromeLink.ExtensionHello?
        var report: ChromeLink.Report?
        init(fd: Int32) { self.fd = fd }
    }
    private var connections: [Int32: Connection] = [:]
    private var lastState: ChromeLink.State?
    private var results: [String: (ChromeLink.ActionResult) -> Void] = [:]
    private let lock = NSLock()
    private var _summary = Summary()

    public init() {}

    /// Whether an extension is linked, and its last report. Safe from any thread.
    public var summary: Summary {
        lock.withLock { _summary }
    }

    /// Starts listening at the socket's path (COOLHEAD_CHROME_LINK_SOCKET in tests), making Cool Head's folder private
    /// first: the folder may already exist, open to others, from older versions' selftests.
    @discardableResult
    public func start(path: String = ChromeLink.socketPath(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())) -> Bool {
        queue.sync {
            guard listener < 0 else { return true }
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            chmod(dir, 0o700)
            guard let fd = ChromeLink.listen(at: path) else { return false }
            listener = fd
            let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            s.setEventHandler { [weak self] in self?.acceptOne() }
            s.resume()
            listenSource = s
            return true
        }
    }

    /// Stops listening and closes every connection (the selftest; Cool Head itself just quits).
    public func stop() {
        queue.sync {
            listenSource?.cancel(); listenSource = nil
            if listener >= 0 { close(listener); listener = -1 }
            for c in connections.values { c.source?.cancel(); close(c.fd) }
            connections = [:]
            update()
        }
    }

    private func acceptOne() {
        guard let fd = ChromeLink.accept(listener) else { return }
        let c = Connection(fd: fd)
        connections[fd] = c
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        s.setEventHandler { [weak self] in self?.read(c) }
        s.resume()
        c.source = s
        send(ChromeLink.AppHello(app: CoolHead.version), to: c)
        if let st = lastState { send(st, to: c) }
    }

    private func read(_ c: Connection) {
        var buf = [UInt8](repeating: 0, count: 65_536)
        let n = Darwin.read(c.fd, &buf, buf.count)
        guard n > 0 else { drop(c); return }
        c.reader.append(buf[0 ..< n])
        while let line = c.reader.next() {
            switch ChromeLink.type(of: line) {
            case ChromeLink.ExtensionHello.kind: c.hello = ChromeLink.decode(ChromeLink.ExtensionHello.self, from: line)
            case ChromeLink.Report.kind: c.report = ChromeLink.decode(ChromeLink.Report.self, from: line)
            case ChromeLink.ActionResult.kind:
                if let r = ChromeLink.decode(ChromeLink.ActionResult.self, from: line), let done = results.removeValue(forKey: r.id) { done(r) }
            default: break     // unknown types are ignored, so either side can be newer
            }
        }
        update()
    }

    private func drop(_ c: Connection) {
        c.source?.cancel()
        close(c.fd)
        connections[c.fd] = nil
        update()
    }

    private func send<M: ChromeLink.Message>(_ m: M, to c: Connection) {
        guard let line = ChromeLink.line(ChromeLink.encode(m)), ChromeLink.writeAll(c.fd, line) else { drop(c); return }
    }

    private func update() {
        let linked = connections.values.filter { $0.hello != nil }
        let s = Summary(connected: !linked.isEmpty, report: linked.compactMap(\.report).first)
        lock.withLock { _summary = s }
    }

    /// Cool Head's reading, sent to every linked extension when it changes, and every 10 seconds as the watcher ticks.
    public func publish(_ state: ChromeLink.State) {
        queue.async { [self] in
            lastState = state
            for c in connections.values { send(state, to: c) }
        }
    }

    /// A card's button: asks the linked extensions to do it; `done` gets the first answer, or nil after 10 seconds.
    public func request(_ action: ChromeLink.Action, done: @escaping @Sendable (ChromeLink.ActionResult?) -> Void) {
        queue.async { [self] in
            guard !connections.isEmpty else { done(nil); return }
            let id = UUID().uuidString
            results[id] = { done($0) }
            for c in connections.values { send(ChromeLink.Request(id: id, action: action), to: c) }
            queue.asyncAfter(deadline: .now() + 10) { [self] in if results.removeValue(forKey: id) != nil { done(nil) } }
        }
    }

    // MARK: - What Cool Head tells the extension

    /// Memory the Mac can hand out now: free, inactive, and purgeable pages.
    public static func freeMB() -> Int {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let pages = UInt64(vm.free_count) + UInt64(vm.inactive_count) + UInt64(vm.purgeable_count)
        return Int(pages * UInt64(getpagesize()) / 1_048_576)
    }

    /// The link's word for the Mac's memory: Cool Head's gate decides "slowed" (see MemoryGate).
    public static func memory(_ s: MacState, slowed: Bool) -> ChromeLink.Memory {
        guard s.memoryLevel != nil else { return .fine }
        if s.memoryPressure == "critical" { return .veryTight }
        return slowed ? .slowed : .tight
    }

    /// Whether the person lets the extension's Auto follow Cool Head (on unless they turn it off in Settings).
    public static let autoKey = "chromeAuto"
    public static var auto: Bool { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
}

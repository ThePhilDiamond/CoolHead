import AppKit
import Foundation
import SQLite3

/// What used the most energy, what woke the chip most often, and why the Mac woke from sleep, over the past week or so.
///
/// It comes from macOS's own power log, `/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL` and its
/// daily archives beside it (gzipped copies, one a day, about a week of them). macOS writes them; they are SQLite, and
/// readable by every user without a password (tested on macOS 26.6.2; research node N-018). Cool Head keeps no copy:
/// it reads them when the history is shown and keeps only the totals, in memory.
///
/// Privacy (Phil's rule for this feature): the same database records which app was in front and when (app usage). Cool
/// Head never reads that. It reads the three tables in `tables`, by name, and nothing else: every connection carries a
/// SQLite authorizer that refuses to read any other table, so a mistake in a query fails instead of reading more. The
/// selftest check `power-history-reads-only-its-tables` runs every query against a database with a decoy app-usage table.
///
/// The format is Apple's and undocumented (reverse-engineered by forensic researchers). If a table or column is missing
/// or renamed, that part is left out and nothing is shown for it: no error, no guess.
public struct PowerHistory: Equatable {
    /// An app, or a part of macOS or a background program, with what it used over the whole period.
    public struct User: Equatable {
        public let id: String                  // the bundle identifier, or launchd's name for it
        public let name: Naming.Named
        public let energy: Double              // nanojoules (inferred; Apple doesn't document the unit), chip + graphics + Neural Engine
    }

    /// Why the Mac woke from sleep, in plain words.
    public enum Cause: String, CaseIterable {
        case lid, button, input, plug, bluetooth, wireless, network, schedule, other
    }

    public struct Wake: Equatable {
        public let at: Date
        public let reason: String              // as macOS records it, e.g. "NUB.SPMI0.SW3 nub-spmi0.0x02 rtc"
        public var cause: Cause { PowerHistory.cause(reason) }
    }

    public let from: Date
    public let to: Date
    public let users: [User]
    public let wakes: [Wake]

    public init(from: Date, to: Date, users: [User], wakes: [Wake]) {
        self.from = from; self.to = to; self.users = users; self.wakes = wakes
    }

    // MARK: what to show

    public var totalEnergy: Double { users.reduce(0) { $0 + $1.energy } }


    /// What used the most energy, as Trends shows it (Phil, 17 November 2026: "The goal is useful data that a lay
    /// person can act on. If it's just data for data's sake because we can access it, we should drop it."): apps and
    /// programs one by one, since something can be done about them, and macOS's own parts together as one line, since
    /// there's nothing to change there. Each says, when clicked, what its share means and whether to do anything. "What woke the
    /// chip most often" was dropped for the same reason: a wakeup's cost is already in the energy, and the count gave
    /// nothing to act on.
    public struct EnergyRow: Equatable {
        public let name: String
        public let what: String?
        public let share: Double
        public let detail: String
        /// The app or program, for its icon; nil for macOS itself.
        public let user: User?
    }
    public static let macOSItself = "macOS itself"
    public func energyRows(_ n: Int = 5) -> [EnergyRow] {
        let total = totalEnergy
        guard total > 0 else { return [] }
        let used = users.filter { $0.energy > 0 }
        let mac = used.filter { $0.name.what == .macOS }.reduce(0) { $0 + $1.energy } / total
        let others = Array(used.filter { $0.name.what != .macOS }.sorted { $0.energy > $1.energy }.prefix(n))
        var rows = zip(others, PowerHistory.names(others)).map { u, named in
            EnergyRow(name: named.name, what: named.what, share: u.energy / total,
                      detail: PowerHistory.detail(named.name, app: u.name.what == .app, share: u.energy / total), user: u)
        }
        if mac > 0 { rows.append(EnergyRow(name: PowerHistory.macOSItself, what: nil, share: mac, detail: PowerHistory.macOSDetail, user: nil)) }
        return Array(rows.sorted { $0.share > $1.share }.prefix(n))
    }

    /// What a share means and whether to do anything. The 25% and 10% marks are Cool Head's own, not from a source.
    public static func detail(_ name: String, app: Bool, share: Double) -> String {
        let what = app ? "" : "A program that runs in the background, started by you or by an app. "
        let stop = app ? "quit it" : "stop it, or quit the app that started it,"
        if share >= 0.25 {
            return what + "A large share. If you don't use \(name) most of the day, it may be working in the background: \(stop) when you're done with it, or look in its settings for background activity."
        }
        if share >= 0.10 { return what + "A fair share, as for anything you use a lot. If you rarely use it, \(stop) when you're done with it." }
        return what + "A small share: nothing to do."
    }
    public static let macOSDetail = "Drawing the screen, Spotlight, backups, updates and the rest of macOS's own work, together. There's nothing to change here; when one part stays busy, Cool Head shows a card saying which and why."

    /// Wakes from sleep by cause, most first.
    public var wakesByCause: [(Cause, [Wake])] {
        Dictionary(grouping: wakes, by: \.cause).sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count
                                                          : Cause.allCases.firstIndex(of: $0.key)! < Cause.allCases.firstIndex(of: $1.key)! }
            .map { ($0.key, $0.value) }
    }

    /// Whole days covered, rounded up: "the past 9 days".
    public var days: Int { max(1, Int((to.timeIntervalSince(from) / 86400).rounded(.up))) }

    // MARK: the tables it may read, and the only queries it runs

    /// One row per app or program per interval (about 2 minutes): energy, graphics energy and more. Only the energy is read:
    /// its wakeup counts were dropped with the list that showed them, since nothing diagnosed with them (Phil, 17 November
    /// 2026: "Do we use the wake up data for any of our diagnosing efforts? Otherwise stop reading it.").
    static let coalition = "PLCoalitionAgent_EventInterval_CoalitionInterval"
    /// One row per sleep or wake event.
    static let powerState = "PLSleepWakeAgent_EventForward_PowerState"
    /// The reason macOS gives for each wake, joined to `powerState` by FK_ID.
    static let wakeReason = "PLSleepWakeAgent_EventForward_PowerState_Array_Reason"

    /// The only tables Cool Head reads. Never add the app-usage (FrontmostApp), app lifecycle, network or device tables.
    public static let tables: Set<String> = [coalition, powerState, wakeReason]

    /// The columns each query needs; if any is missing, that part is left out.
    static let columns: [String: Set<String>] = [
        coalition: ["timestamp", "BundleId", "LaunchdName", "energy", "gpu_energy_nj", "ane_energy_nj"],
        powerState: ["ID", "timestamp"],
        wakeReason: ["FK_ID", "value"],
    ]

    static func columnsQuery(_ table: String) -> String { "SELECT name FROM pragma_table_info('\(table)')" }
    /// Per app or program: energy (chip, graphics, Neural Engine), and the period its rows cover. The second
    /// query is the same for the first moment only, which a daily archive repeats from the end of the one before.
    static let energyQuery = """
        SELECT BundleId, LaunchdName, total(energy) + total(gpu_energy_nj) + total(ane_energy_nj),
               min(timestamp), max(timestamp)
        FROM \(coalition) GROUP BY BundleId, LaunchdName
        """
    static let firstMomentQuery = """
        SELECT BundleId, LaunchdName, total(energy) + total(gpu_energy_nj) + total(ane_energy_nj),
               min(timestamp), max(timestamp)
        FROM \(coalition) WHERE timestamp <= (SELECT min(timestamp) FROM \(coalition)) + 1 GROUP BY BundleId, LaunchdName
        """
    static let wakeQuery = """
        SELECT p.timestamp, r.value FROM \(powerState) p JOIN \(wakeReason) r ON r.FK_ID = p.ID ORDER BY p.timestamp
        """

    /// Every statement Cool Head can run on the power log, so the selftest can check each one.
    public static var statements: [String] {
        tables.sorted().map(columnsQuery) + [energyQuery, firstMomentQuery, wakeQuery]
    }

    // MARK: reading

    public static let folder = "/private/var/db/powerlog/Library/BatteryLife"

    /// Whether this Mac has a power log Cool Head can read.
    public static var available: Bool { FileManager.default.isReadableFile(atPath: folder + "/CurrentPowerlog.PLSQL") }

    /// The history from this Mac's power log, or nil when there is nothing to show. Takes a fraction of a second the
    /// first time (each archive is decompressed in memory, never to disk) and less after (archives don't change, so
    /// their totals are kept in memory). Call it off the main thread.
    public static func read(now: Date = Date(), appName: (String) -> String? = PowerHistory.appName) -> PowerHistory? {
        var slices: [Slice] = []
        let archives = (try? FileManager.default.contentsOfDirectory(atPath: folder + "/Archives")) ?? []
        for name in archives where name.hasSuffix(".PLSQL.gz") {
            let path = folder + "/Archives/" + name
            if let s = cache.slice(for: path, read: { Data.gunzip(path: path).flatMap(Database.init(bytes:)).map(Slice.init) }) { slices.append(s) }
        }
        if let db = Database(path: folder + "/CurrentPowerlog.PLSQL") { slices.append(Slice(db)) }
        return make(slices, appName: appName)
    }

    /// Opens a database from its bytes (as a test or an archive does) and reads it.
    static func read(bytes: [Data], appName: (String) -> String?) -> PowerHistory? {
        make(bytes.compactMap(Database.init(bytes:)).map(Slice.init), appName: appName)
    }

    /// An app's name from its bundle identifier, if it is installed.
    public static func appName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// What one database (the current one, or one archive) holds.
    struct Slice {
        struct Use { var energy = 0.0 }
        var uses: [Key: Use] = [:]
        var first: Double?, last: Double?
        var firstMoment: [Key: Use] = [:]          // the rows at its first moment, which may repeat the previous archive's last
        var wakes: [(Double, String)] = []

        struct Key: Hashable { let bundle: String, launchd: String }

        init(uses: [Key: Use] = [:], first: Double? = nil, last: Double? = nil, firstMoment: [Key: Use] = [:], wakes: [(Double, String)] = []) {
            self.uses = uses; self.first = first; self.last = last; self.firstMoment = firstMoment; self.wakes = wakes
        }

        init(_ db: Database) {
            if db.has(coalition) {
                func read(_ sql: String, into out: inout [Key: Use], span: Bool) {
                    db.rows(sql) { r in
                        let key = Key(bundle: r.text(0) ?? "", launchd: r.text(1) ?? "")
                        out[key, default: Use()].energy += max(0, r.double(2))
                        guard span else { return }
                        let a = r.double(3), b = r.double(4)
                        if a > 0 { first = min(first ?? a, a) }
                        if b > 0 { last = max(last ?? b, b) }
                    }
                }
                read(energyQuery, into: &uses, span: true)
                read(firstMomentQuery, into: &firstMoment, span: false)
            }
            if db.has(powerState) && db.has(wakeReason) {
                db.rows(wakeQuery) { r in if let reason = r.text(1), !reason.isEmpty { wakes.append((r.double(0), reason)) } }
            }
        }
    }

    /// Joins the slices in time order, without counting twice the moment an archive repeats from the one before, and
    /// groups each app's helpers and each program's instances under one name.
    static func make(_ slices: [Slice], appName: (String) -> String?) -> PowerHistory? {
        let ordered = slices.filter { $0.first != nil || !$0.wakes.isEmpty }.sorted { ($0.first ?? .infinity) < ($1.first ?? .infinity) }
        var uses: [String: (bundle: Bool, id: String, energy: Double)] = [:]
        var previousLast: Double?
        var first: Double?, last: Double?
        for s in ordered {
            let repeats = s.first != nil && previousLast != nil && s.first! <= previousLast! + 1
            for (key, use) in s.uses {
                let id = identity(key)
                let again = repeats ? s.firstMoment[key] : nil
                let e = max(0, use.energy - (again?.energy ?? 0))
                uses[id.lowercased(), default: (!key.bundle.isEmpty, id, 0)].energy += e
            }
            if let a = s.first { first = min(first ?? a, a) }
            if let b = s.last { last = max(last ?? b, b); previousLast = max(previousLast ?? b, b) }
        }
        // a wake is often recorded twice, as the chip wakes and again as the screen comes on: one wake per reason a minute
        var wakes: [Wake] = []
        for (t, reason) in ordered.flatMap(\.wakes).sorted(by: { $0.0 < $1.0 }) {
            if let f = first, t < f { continue }                     // before the energy history starts
            if let prev = wakes.last, prev.reason == reason, t - prev.at.timeIntervalSince1970 < 60 { continue }
            wakes.append(Wake(at: Date(timeIntervalSince1970: t), reason: reason))
        }
        let start = first ?? wakes.first.map { $0.at.timeIntervalSince1970 }
        let end = last ?? wakes.last.map { $0.at.timeIntervalSince1970 }
        guard let start, let end, end > start else { return nil }
        let users = uses.values.map { u in User(id: u.id, name: named(u.id, isBundle: u.bundle, appName: appName), energy: u.energy) }
        guard !users.isEmpty || !wakes.isEmpty else { return nil }
        return PowerHistory(from: Date(timeIntervalSince1970: start), to: Date(timeIntervalSince1970: end), users: users, wakes: wakes)
    }

    /// One name for an app and its helpers, or a program and its numbered instances: the bundle identifier if there is
    /// one, otherwise launchd's name without "application." and without trailing numbers and identifiers.
    static func identity(_ key: Slice.Key) -> String {
        if !key.bundle.isEmpty { return key.bundle }
        var parts = key.launchd.split(separator: ".").map(String.init)
        if parts.count > 1, parts.first == "application" { parts.removeFirst() }
        func noise(_ s: String) -> Bool {
            s.allSatisfy(\.isNumber) || (s.count >= 8 && s.contains(where: \.isNumber) && s.allSatisfy { $0.isHexDigit || $0 == "-" })
        }
        while parts.count > 1, let tail = parts.last, noise(tail) { parts.removeLast() }
        return parts.isEmpty ? key.launchd : parts.joined(separator: ".")
    }

    /// How a person would name it: an app's own name, or the last part of the identifier for programs.
    static func named(_ id: String, isBundle: Bool, appName: (String) -> String?) -> Naming.Named {
        let macOS = id.lowercased().hasPrefix("com.apple.")
        if isBundle, let n = appName(id) { return .init(n, macOS ? .macOS : .app) }
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return .init(last, macOS ? .macOS : isBundle ? .app : .background)
    }

    /// What a wake reason means. macOS records the hardware path ("smc.sysState.Wake(0x70070000) lid
    /// SMC.OutboxNotEmpty RTP.multi-touch", "NUB.SPMI0.SW3 nub-spmi0.0x02 rtc"); the same strings `pmset -g log` prints.
    static func cause(_ reason: String) -> Cause {
        let r = reason.lowercased()
        let words = Set(r.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if words.contains("lid") { return .lid }                                     // the lid wake also names the trackpad
        if words.contains("pwrbtn") || r.contains("power button") || r.contains("powerbutton") { return .button }
        if words.contains("hid") || words.contains("keyboard") || words.contains("trackpad") || words.contains("mouse")
            || r.contains("multi-touch") { return .input }
        if r.contains("usb") || r.contains("plug") || words.contains("ac") || r.contains("charger") { return .plug }
        if r.contains("bluetooth") || words.contains("bt") { return .bluetooth }                 // e.g. "wifibt … bluetooth-pcie"
        if words.contains("wifibt") { return .wireless }                                         // the Wi-Fi and Bluetooth chip, no more said
        if words.contains("wlan") || words.contains("arpt") || words.contains("wifi") || r.contains("ethernet")
            || words.contains("en0") || r.contains("network") { return .network }
        if words.contains("rtc") || r.contains("maintenance") { return .schedule }
        return .other
    }

    // MARK: archives don't change, so each is read once

    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var slices: [String: Slice] = [:]           // by path, size and modification time
        func slice(for path: String, read: () -> Slice?) -> Slice? {
            let a = try? FileManager.default.attributesOfItem(atPath: path)
            let key = "\(path)|\(a?[.size] ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            lock.lock(); let known = slices[key]; lock.unlock()
            if let known { return known }
            guard let s = read() else { return nil }
            lock.lock(); slices[key] = s; lock.unlock()
            return s
        }
    }
    static let cache = Cache()
}

// MARK: - SQLite, read only, limited to the allowed tables

/// A read-only connection to the power log (or a copy in memory) that can read only `PowerHistory.tables`.
final class Database {
    private var db: OpaquePointer?
    /// Every table a statement asked to read, allowed or not; the selftest checks it.
    let reads = Reads()

    final class Reads {
        var allowed: [String] = []
        var refused: [String] = []
    }

    /// The live database, opened read only: macOS keeps writing it, and Cool Head never does.
    init?(path: String) {
        guard FileManager.default.isReadableFile(atPath: path),
              let uri = URL(fileURLWithPath: path).absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        guard sqlite3_open_v2(uri + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close_v2(db); return nil
        }
        sqlite3_busy_timeout(db, 250)               // macOS may be writing; don't wait long, try again next time
        guard limit() else { return nil }
    }

    /// A database from its bytes, in memory and read only: how an archive is read, so no copy is written to disk.
    init?(bytes: Data) {
        guard bytes.count > 100, bytes.prefix(16).elementsEqual("SQLite format 3\0".utf8),
              sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let buffer = sqlite3_malloc64(UInt64(bytes.count)) else { sqlite3_close_v2(db); return nil }
        let p = buffer.assumingMemoryBound(to: UInt8.self)
        bytes.copyBytes(to: p, count: bytes.count)
        // the archives are saved in WAL mode (bytes 18 and 19 are 2), which an in-memory copy can't open; 1 is the plain mode
        if p[18] == 2 && p[19] == 2 { p[18] = 1; p[19] = 1 }
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_READONLY)
        guard sqlite3_deserialize(db, "main", p, Int64(bytes.count), Int64(bytes.count), flags) == SQLITE_OK, limit() else {
            sqlite3_close_v2(db); db = nil; return nil
        }
    }

    deinit { sqlite3_close_v2(db) }

    /// Installs the authorizer: reading any table outside `PowerHistory.tables` is refused, as is anything but reading.
    private func limit() -> Bool {
        let check: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                   UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = { context, action, a, b, _, _ in
            let reads = Unmanaged<Database.Reads>.fromOpaque(context!).takeUnretainedValue()
            let first = a.map { String(cString: $0) } ?? "", second = b.map { String(cString: $0) } ?? ""
            switch action {
            case SQLITE_SELECT, SQLITE_FUNCTION:
                return SQLITE_OK
            case SQLITE_READ:
                // pragma_table_info reads a virtual table of that name; what it describes is checked under SQLITE_PRAGMA
                if PowerHistory.tables.contains(first) || first == "pragma_table_info" { reads.allowed.append(first); return SQLITE_OK }
                reads.refused.append(first); return SQLITE_DENY
            case SQLITE_PRAGMA:
                if first == "table_info" && PowerHistory.tables.contains(second) { reads.allowed.append(second); return SQLITE_OK }
                reads.refused.append("pragma \(first) \(second)"); return SQLITE_DENY
            default:
                reads.refused.append("action \(action) \(first)"); return SQLITE_DENY
            }
        }
        return sqlite3_set_authorizer(db, check, Unmanaged.passUnretained(reads).toOpaque()) == SQLITE_OK
    }

    /// Whether a table is there with every column the queries need.
    func has(_ table: String) -> Bool {
        guard let need = PowerHistory.columns[table] else { return false }
        var found = Set<String>()
        rows(PowerHistory.columnsQuery(table)) { if let n = $0.text(0) { found.insert(n) } }
        return need.isSubset(of: found)
    }

    struct Row {
        let s: OpaquePointer
        func text(_ i: Int32) -> String? { sqlite3_column_text(s, i).map { String(cString: $0) } }
        func double(_ i: Int32) -> Double { sqlite3_column_double(s, i) }
    }

    /// Runs one statement; false if it couldn't (including when the authorizer refused it).
    @discardableResult
    func rows(_ sql: String, _ each: (Row) -> Void) -> Bool {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { sqlite3_finalize(s); return false }
        defer { sqlite3_finalize(s) }
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { each(Row(s: s)); continue }
            return rc == SQLITE_DONE
        }
    }
}

extension Data {
    /// A gzip file's contents, decompressed in memory; nil if it isn't one or is too big to be a power log.
    static func gunzip(path: String) -> Data? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size < 64_000_000,
              let d = FileManager.default.contents(atPath: path) else { return nil }
        return gunzip(d)
    }

    static func gunzip(_ d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 { guard i + 2 <= b.count else { return nil }; i += 2 + Int(b[i]) | Int(b[i + 1]) << 8 }   // extra field
        for bit: UInt8 in [8, 16] where flags & bit != 0 {                                                          // name, comment
            while i < b.count && b[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 2 != 0 { i += 2 }                                                                                // header CRC
        guard i < b.count - 8 else { return nil }
        // the body is raw DEFLATE, which is what Foundation calls .zlib; the last 4 bytes are the size, to check
        guard let out = try? (Data(b[i ..< b.count - 8]) as NSData).decompressed(using: .zlib) as Data, out.count < 1_000_000_000 else { return nil }
        let isize = UInt32(b[b.count - 4]) | UInt32(b[b.count - 3]) << 8 | UInt32(b[b.count - 2]) << 16 | UInt32(b[b.count - 1]) << 24
        return isize == UInt32(truncatingIfNeeded: out.count) ? out : nil
    }
}

// MARK: - the words, written by hand, shared by the panel and `coolhead history`

extension PowerHistory {
    /// "The past 9 days".
    public var title: String { days == 1 ? "The past day" : "The past \(days) days" }

    /// Where the figures come from, under the title.
    public static let source = "From macOS's own power log, which keeps about a week. Cool Head keeps no copy."

    public static let energyHeading = "Used the most energy"
    public static let energyNote = "Each one's share of the energy the chip, graphics and Neural Engine used while the Mac was awake. Click one for what it means."
    public static let wakesHeading = "Why it woke from sleep"

    /// Names for a list of users, told apart where two are alike, and what each is when it isn't an app.
    public static func names(_ users: [User]) -> [(name: String, what: String?)] {
        let shown = Naming.distinct(users.map(\.name))
        return zip(users, shown).map { u, n in
            switch u.name.what {
            case .macOS: return (n, "Part of macOS")
            case .background, .commandLine: return (n, "A background program")
            default: return (n, nil)
            }
        }
    }

    /// A share: "31%", or "under 1%".
    public static func share(_ f: Double) -> String { f < 0.01 ? "under 1%" : "\(Int((f * 100).rounded()))%" }

    /// "It woke from sleep 58 times."
    public var wakesSummary: String {
        wakes.isEmpty ? "It didn't wake from sleep." : "It woke from sleep \(PowerHistory.times(wakes.count))."
    }

    /// One line per cause: "51 times on a timer, which macOS sets to do its own work while asleep. This is normal."
    public static func sentence(_ cause: Cause, _ wakes: [Wake]) -> String {
        let n = times(wakes.count)
        switch cause {
        case .lid: return "\(n) when the lid was opened."
        case .button: return "\(n) when the power button was pressed."
        case .input: return "\(n) when a keyboard, mouse or trackpad was used."
        case .plug: return "\(n) when something was plugged in, often the charger."
        case .network: return "\(n) for network activity, such as another device reaching this Mac."
        case .bluetooth: return "\(n) by a Bluetooth device."
        case .wireless: return "\(n) by the Wi-Fi and Bluetooth chip, for network activity or a Bluetooth device."
        case .schedule: return "\(n) on a timer, which macOS sets to do its own work while asleep. This is normal."
        case .other:
            let reasons = Array(Set(wakes.map(\.reason))).sorted().prefix(2).map { "“\($0)”" }
            return "\(n) for \(reasons.count == 1 ? "a reason" : "reasons") macOS records as \(reasons.joined(separator: " and "))."
        }
    }

    static func times(_ n: Int) -> String { n == 1 ? "Once" : n == 2 ? "Twice" : "\(n) times" }

    /// The whole history as text, for `coolhead history`.
    public var text: String {
        var out = [title, PowerHistory.source, ""]
        let energy = energyRows()
        if !energy.isEmpty {
            out.append(PowerHistory.energyHeading)
            for r in energy {
                out.append("  \(PowerHistory.share(r.share).padding(toLength: 9, withPad: " ", startingAt: 0)) \(r.name)" + (r.what.map { " (\($0.lowercased()))" } ?? ""))
                out.append("            \(r.detail)")
            }
            out.append("")
        }
        out.append(PowerHistory.wakesHeading)
        out.append("  " + wakesSummary)
        for (cause, w) in wakesByCause { out.append("  · " + PowerHistory.sentence(cause, w)) }
        return out.joined(separator: "\n")
    }
}

// MARK: - made-up history, for screenshots (COOLHEAD_SNAPSHOT_HISTORY), so no one's own apps appear

extension PowerHistory {
    public static func sample(now: Date = Date()) -> PowerHistory {
        let hours = 8.0 * 24
        func user(_ id: String, _ name: String, _ what: Naming.What, share: Double) -> User {
            User(id: id, name: .init(name, what), energy: share * 1_000_000_000_000)
        }
        let users = [
            user("com.google.Chrome", "Google Chrome", .app, share: 0.34),
            user("com.apple.WindowServer", "WindowServer", .macOS, share: 0.18),
            user("com.docker.docker", "Docker", .app, share: 0.12),
            user("com.apple.Spotlight", "Spotlight", .macOS, share: 0.07),
            user("com.google.drivefs", "Google Drive", .app, share: 0.05),
            user("com.apple.audio.coreaudiod", "coreaudiod", .macOS, share: 0.02),
            user("com.example.updaterd", "updaterd", .background, share: 0.01),
            user("com.apple.kernel_task", "kernel_task", .macOS, share: 0.06),
        ] + (1...10).map { user("com.example.app\($0)", "App \($0)", .app, share: 0.015) }      // the long tail
        var wakes: [Wake] = []
        let reasons: [(String, Int)] = [("NUB.SPMI0.SW3 nub-spmi0.0x02 rtc", 140), ("smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch", 18),
                                        ("smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty", 12),
                                        ("smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty", 6), ("MTP.DOCK.CHANNELS.AP0.IRQ RTP.keyboard", 1)]
        for (reason, n) in reasons {
            for i in 0..<n { wakes.append(Wake(at: now.addingTimeInterval(-Double(i + 1) * hours * 3600 / Double(n + 1)), reason: reason)) }
        }
        return PowerHistory(from: now.addingTimeInterval(-hours * 3600), to: now, users: users, wakes: wakes.sorted { $0.at < $1.at })
    }
}

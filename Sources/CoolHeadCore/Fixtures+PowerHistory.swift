import Foundation
import SQLite3

/// Checks for the history read from macOS's power log (see PowerHistory.swift). Each builds a small power log in memory,
/// shaped like the real one (tables and columns as on macOS 26.6.2), with a decoy app-usage table it must never read.
extension Fixture {
    static func powerHistoryChecks(_ now: Date) -> [(String, Bool, String)] {
        var out: [(String, Bool, String)] = []
        let t0 = now.addingTimeInterval(-3 * 86400).timeIntervalSince1970.rounded()
        let apps = ["com.example.Browser": "Browser", "com.example.Chat": "Chat", "com.apple.finder": "Finder"]
        let name: (String) -> String? = { apps[$0] }

        // 1. Privacy: only the allowed tables, by name, ever. Every statement names only them; at run time the authorizer
        // refuses anything else, so a query that strays fails instead of reading app usage.
        let named = PowerHistory.statements.map { s in
            s.matches(of: #/\bPL[A-Za-z_]+/#).map { String($0.output) }
        }
        let strays = Set(named.flatMap { $0 }).subtracting(PowerHistory.tables)
        let forbidden = PowerHistory.tables.filter { t in ["Frontmost", "ApplicationAgent", "NetworkAgent", "Device", "Usage"].contains { t.contains($0) } }
        let log = powerLog(start: t0)
        var reads: [String] = [], refused: [String] = [], decoyRead = true, masterRead = true, decoyPragma = true
        if let db = Database(bytes: log) {
            _ = PowerHistory.Slice(db)
            reads = db.reads.allowed; refused = db.reads.refused
            var got: [String] = []
            decoyRead = db.rows("SELECT app FROM PLApplicationAgent_EventForward_FrontmostApp") { got.append($0.text(0) ?? "") } || !got.isEmpty
            masterRead = db.rows("SELECT name FROM sqlite_master") { _ in }
            decoyPragma = db.has("PLApplicationAgent_EventForward_FrontmostApp")
                || db.rows("SELECT name FROM pragma_table_info('PLApplicationAgent_EventForward_FrontmostApp')") { _ in }
        }
        let onlyAllowed = Set(reads).isSubset(of: PowerHistory.tables.union(["pragma_table_info"])) && refused.isEmpty && !reads.isEmpty
        out.append(("power-history-reads-only-its-tables",
                    strays.isEmpty && forbidden.isEmpty && named.allSatisfy { !$0.isEmpty } && onlyAllowed && !decoyRead && !masterRead && !decoyPragma
                        && !PowerHistory.statements.contains { $0.contains("wakeups") },          // not read since 17 November 2026: nothing used it
                    "\(PowerHistory.statements.count) statements name only \(PowerHistory.tables.count) tables\(strays.isEmpty ? "" : ", strays \(strays)"); "
                    + "reading them asked for \(Set(reads).sorted()) and nothing else (\(refused.isEmpty ? "none refused" : "refused \(refused)")); "
                    + "the app-usage table \(decoyRead ? "WAS READ" : "was refused"), the table list \(masterRead ? "WAS READ" : "was refused"), its columns \(decoyPragma ? "WERE READ" : "were refused")"))

        // 2. Adding up: an archive (gzipped, saved in WAL mode, as macOS keeps them) and the current file, the second
        // repeating the archive's last moment; an app's helpers count as the app; numbered instances as one program;
        // a wake recorded twice counts once.
        let archive = gzip(powerLog(start: t0, wal: true))
        let current = powerLog(start: t0 + 86400, repeatFrom: t0)
        let unzipped = archive.flatMap(Data.gunzip)
        let h = unzipped.flatMap { PowerHistory.read(bytes: [current, $0], appName: name) }
        let rows = h?.energyRows() ?? []
        let energy = rows.map { "\($0.name) \(PowerHistory.share($0.share))" }.joined(separator: ", ")
        let browser = h?.users.first { $0.id == "com.example.Browser" }
        let causes = h?.wakesByCause.map { "\($0.0.rawValue) \($0.1.count)" }.joined(separator: " ") ?? ""
        let shownNames = rows.map { r in r.what.map { "\(r.name) (\($0))" } ?? r.name }
        let addsUp = browser?.energy == 2 * 3_000_000_000       // two days, helpers included, boundary once
            // macOS's own parts together; each row says what its share means
            && energy == "Browser 56%, macOS itself 36%, Chat 4%, syncd 4%"
            && rows.first?.detail.hasPrefix("A large share. If you don't use Browser most of the day") == true
            && rows.first { $0.name == "macOS itself" }?.detail == PowerHistory.macOSDetail && rows.first { $0.name == "macOS itself" }?.user == nil
            && rows.last?.detail == "A program that runs in the background, started by you or by an app. A small share: nothing to do."
            && PowerHistory.detail("X", app: true, share: 0.12).hasPrefix("A fair share")
            && causes == "schedule 4 lid 2 wireless 2"
            && !shownNames.contains("WindowServer (Part of macOS)") && shownNames.contains("syncd (A background program)")
            && h?.days == 2 && h?.title == "The past 2 days"
        // the Power page's list: three without a click, the others at 5% or more behind one line, every one in Nerdy stuff
        let few = h?.energySplit()
        let sample = PowerHistory.sample().energySplit()
        out.append(("power-page-top-three",
                    few?.top.map(\.name) == ["Browser", "macOS itself", "Chat"] && few?.more.isEmpty == true && few?.all.count == 4
                        && sample.top.map(\.name) == ["Google Chrome", "macOS itself", "Docker"] && sample.more.map(\.name) == ["Google Drive"]
                        && sample.all.count == 15 && sample.all.map(\.share) == sample.all.map(\.share).sorted(by: >),
                    "few: \(few?.top.map(\.name) ?? []) + \(few?.more.map(\.name) ?? []) of \(few?.all.count ?? 0); "
                    + "sample: \(sample.top.map(\.name)) + \(sample.more.map(\.name)) of \(sample.all.count)"))
        out.append(("power-history-adds-up", addsUp,
                    "energy: \(energy); wakes: \(causes); names: \(shownNames); \(h?.title ?? "no history")"))

        // 3. When the format changes (a column renamed, a table gone), that part shows nothing, quietly
        let renamed = PowerHistory.read(bytes: [powerLog(start: t0, renameEnergy: true)], appName: name)
        let noWakes = PowerHistory.read(bytes: [powerLog(start: t0, dropWakes: true)], appName: name)
        let notADatabase = PowerHistory.read(bytes: [Data("not a database".utf8)], appName: name)
        let quiet = renamed?.users.isEmpty == true && renamed?.wakes.count == 4
            && noWakes?.wakes.isEmpty == true && noWakes?.users.isEmpty == false && notADatabase == nil
            && Data.gunzip(Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3] + Array(repeating: 0, count: 16) + [5, 0, 0, 0])) == nil
        out.append(("power-history-quiet-when-format-changes", quiet,
                    "renamed column: \(renamed?.users.count ?? -1) users, \(renamed?.wakes.count ?? -1) wakes; no wake table: "
                    + "\(noWakes?.users.count ?? -1) users, \(noWakes?.wakes.count ?? -1) wakes; not a database: \(notADatabase == nil ? "nothing" : "something")"))

        // 4. Wake reasons as macOS 26.6.2 records them (research node N-018, N-007), in plain words
        let reasons: [(String, PowerHistory.Cause)] = [
            ("NUB.SPMI0.SW3 nub-spmi0.0x02 rtc", .schedule),
            ("smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch", .lid),
            ("lid", .lid),
            ("smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty", .plug),
            ("smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty", .wireless),
            ("smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty bluetooth-pcie", .bluetooth),
            ("MTP.DOCK.CHANNELS.AP0.IRQ RTP.keyboard", .input),
            ("USB2_wake", .plug),
            ("something new", .other),
        ]
        let wrong = reasons.filter { PowerHistory.cause($0.0) != $0.1 }.map { "\($0.0) → \(PowerHistory.cause($0.0).rawValue)" }
        let sentences = PowerHistory.Cause.allCases.map { PowerHistory.sentence($0, [.init(at: now, reason: "X"), .init(at: now, reason: "X")]) }
        // the app's rows: a short name with no full stop, and an explanation that is a whole sentence
        let wakeRows = PowerHistory.Cause.allCases.flatMap { c in [PowerHistory.label(c), PowerHistory.detail(c, [.init(at: now, reason: "X")])] }
        let badRows = PowerHistory.Cause.allCases.filter { c in
            let l = PowerHistory.label(c), d = PowerHistory.detail(c, [.init(at: now, reason: "X")])
            return l.isEmpty || l.hasSuffix(".") || l.count > 30 || !d.hasSuffix(".") || d.contains("times")
        }
        let style = (sentences + wakeRows).filter { $0.contains("—") || $0.contains("!") }
            + sentences.filter { !$0.hasSuffix(".") || !$0.hasPrefix("Twice") } + badRows.map(\.rawValue)
        out.append(("power-history-wake-reasons", wrong.isEmpty && style.isEmpty,
                    wrong.isEmpty && style.isEmpty ? "\(reasons.count) recorded reasons read right; \(sentences.count) sentences, \(wakeRows.count / 2) rows" : "wrong: \(wrong); style: \(style)"))

        // 5. This Mac's own power log, if it has one: read without error, quickly. Says only how much, never what.
        if PowerHistory.available {
            let start = Date()
            let mine = PowerHistory.read()
            let took = Date().timeIntervalSince(start)
            out.append(("power-history-this-mac", took < 10,
                        mine.map { "\($0.users.count) apps and programs, \($0.wakes.count) wakes over \($0.days) days, read in \(String(format: "%.1f", took)) s" }
                        ?? "nothing to show (read in \(String(format: "%.1f", took)) s)"))
        } else {
            out.append(("power-history-this-mac", true, "this Mac has no power log Cool Head can read"))
        }
        return out
    }

    /// A small power log: two days of energy rows from `start` (one row per program per hour), four timer wakes (each
    /// recorded twice, a second apart), and a decoy app-usage table. Optionally saved in WAL mode, or with the wakeup
    /// column renamed, or without the wake tables.
    static func powerLog(start: Double, wal: Bool = false, repeatFrom: Double? = nil, renameEnergy: Bool = false, dropWakes: Bool = false) -> Data {
        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK else { return Data() }
        defer { sqlite3_close(db) }
        // the real table has a wakeups column, which Cool Head no longer reads; renaming a column it does read is a format change
        let wakeupColumn = "platform_idle_wakeups"
        let aneColumn = renameEnergy ? "ane_energy_nj_v2" : "ane_energy_nj"
        var sql = """
            CREATE TABLE PLCoalitionAgent_EventInterval_CoalitionInterval (ID INTEGER PRIMARY KEY, timestamp REAL, BundleId TEXT,
              LaunchdCoalitionId INTEGER, LaunchdName TEXT, energy INTEGER, gpu_energy_nj INTEGER, \(aneColumn) INTEGER,
              cpu_time REAL, interrupt_wakeups REAL, \(wakeupColumn) REAL, timestampEnd REAL);
            CREATE TABLE PLApplicationAgent_EventForward_FrontmostApp (ID INTEGER PRIMARY KEY, timestamp REAL, app TEXT);
            INSERT INTO PLApplicationAgent_EventForward_FrontmostApp (timestamp, app) VALUES (\(start), 'Secret Diary');
            """
        if !dropWakes {
            sql += """
                CREATE TABLE PLSleepWakeAgent_EventForward_PowerState (ID INTEGER PRIMARY KEY, timestamp REAL, Event INTEGER, State INTEGER,
                  Reason INTEGER, WakeType INTEGER);
                CREATE TABLE PLSleepWakeAgent_EventForward_PowerState_Array_Reason (ID INTEGER PRIMARY KEY, FK_ID INTEGER, value TEXT);
                """
            let reasons = ["NUB.SPMI0.SW3 nub-spmi0.0x02 rtc", "NUB.SPMI0.SW3 nub-spmi0.0x02 rtc",
                           "smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch",
                           "smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty"]
            var id = 0
            for (i, r) in reasons.enumerated() {
                for again in [0.0, 1.0] {                     // as the chip wakes, and again a second later
                    id += 1
                    let t = start + 3600 * Double(i) + 600 + again
                    sql += "INSERT INTO PLSleepWakeAgent_EventForward_PowerState VALUES (\(id), \(t), 0, 5, 1, 1);"
                    sql += "INSERT INTO PLSleepWakeAgent_EventForward_PowerState_Array_Reason (FK_ID, value) VALUES (\(id), '\(r)');"
                }
            }
        }
        // per hour: (bundle, launchd name, energy nJ, graphics nJ, wakeups)
        let programs: [(String, String, Int, Int, Int)] = [
            ("com.example.Browser", "application.com.example.Browser.1234.5678", 100_000_000, 0, 20),
            ("com.example.Browser", "application.com.example.Browser.helper.1234.9999", 25_000_000, 0, 5),    // its helper
            ("", "com.apple.WindowServer", 30_000_000, 30_000_000, 0),
            ("", "com.apple.kernel_task", 20_000_000, 0, 1000),
            ("com.example.Chat", "application.com.example.Chat.11.22", 10_000_000, 0, 4),
            ("", "com.example.syncd.3F2504E0-4F89-11D3-9A0C-0305E82C3301", 4_000_000, 0, 1),
            ("", "com.example.syncd.4A2504E0-4F89-11D3-9A0C-0305E82C3302", 4_000_000, 0, 1),               // the same program again
        ]
        var hours = (0..<24).map { start + 3600 * Double($0) }
        if let r = repeatFrom { hours.insert(r + 3600 * 23, at: 0) }        // the previous file's last moment, repeated
        for (i, t) in hours.enumerated() {
            for (n, p) in programs.enumerated() {
                sql += "INSERT INTO PLCoalitionAgent_EventInterval_CoalitionInterval (timestamp, BundleId, LaunchdCoalitionId, LaunchdName, energy, gpu_energy_nj, \(aneColumn), cpu_time, interrupt_wakeups, \(wakeupColumn), timestampEnd) VALUES (\(t), '\(p.0)', \(n), '\(p.1)', \(p.2), \(p.3), 0, 1, 1, \(p.4), \(t + 3600));"
            }
            _ = i
        }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { return Data() }
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(db, "main", &size, 0) else { return Data() }
        defer { sqlite3_free(bytes) }
        var d = Data(bytes: bytes, count: Int(size))
        if wal { d[18] = 2; d[19] = 2 }
        return d
    }

    /// Gzip, as macOS saves the daily archives: header, raw DEFLATE, then CRC (not checked, so left 0) and size.
    static func gzip(_ d: Data) -> Data? {
        guard let body = try? (d as NSData).compressed(using: .zlib) as Data else { return nil }
        let n = UInt32(truncatingIfNeeded: d.count)
        return Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3]) + body + Data([0, 0, 0, 0])
            + Data([UInt8(n & 0xff), UInt8(n >> 8 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 24 & 0xff)])
    }

    /// No sample cards of its own for `coolhead wording`.
    static func powerHistorySamples(_ now: Date) -> [(String, Card)] { [] }
}

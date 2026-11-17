import Foundation

/// What developer and AI tools leave holding memory or disk after you're done with them, and the one-click way to let
/// it go (research rules 5, 11 and 23; nodes N-006 and N-013).
///
/// - **A local AI model kept in memory.** Ollama keeps a model loaded for 5 minutes after its last request (or longer,
///   if set to), holding its memory (Ollama FAQ). Its own API lists loaded models (`/api/ps`) and unloads one when asked
///   to keep it for zero seconds (`keep_alive: 0`), which needs no password and works wherever Ollama is installed.
///   Tested on this Mac, 16 November 2026, with Ollama 0.40.16: the runner process exits and the memory is freed.
///   LM Studio isn't covered: it wasn't on hand to test.
/// - **Xcode's build data.** `~/Library/Developer/Xcode/DerivedData` holds every project's intermediate build files;
///   Xcode rebuilds what it needs on the next build, so deleting it loses nothing but time (Apple storage advice;
///   thoughtbot; Kodeco). Offered only when the startup disk is nearly full.
public enum Leftovers {
    // MARK: local AI models (Ollama)

    public struct Model: Equatable {
        public let name: String
        public let bytes: UInt64
        public init(name: String, bytes: UInt64) { self.name = name; self.bytes = bytes }
    }

    /// Where Ollama listens unless it was told otherwise.
    public static var ollama = URL(string: "http://127.0.0.1:11434")!

    /// A process that is Ollama or its model runner, by its program's path.
    public static func isOllama(_ path: String?) -> Bool {
        guard let p = path?.lowercased() else { return false }
        return p.contains("ollama.app/contents/") || p.contains("/cellar/ollama/") || p.hasSuffix("/bin/ollama") || p.contains("/lib/ollama/")
    }

    /// The models in Ollama's answer to /api/ps.
    public static func parseLoaded(_ data: Data) -> [Model]? {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = d["models"] as? [[String: Any]] else { return nil }
        return list.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            return Model(name: name, bytes: UInt64((m["size"] as? NSNumber)?.int64Value ?? 0))
        }
    }

    /// The models Ollama has loaded now; nil when it isn't answering (not running, or on another address).
    public static func loaded(timeout: TimeInterval = 1) -> [Model]? {
        request(ollama.appendingPathComponent("api/ps"), body: nil, timeout: timeout).flatMap(parseLoaded)
    }

    /// The same, asked at most every 30 seconds (the watcher's memory card).
    public static func loadedRecently(now: Date = Date()) -> [Model]? {
        if let c = loadedCache.value, now.timeIntervalSince(c.at) < 30 { return c.models }
        let m = loaded()
        loadedCache.value = (now, m)
        return m
    }
    static let loadedCache = Locked<(at: Date, models: [Model]?)?>(nil)

    /// Asks Ollama to unload each model now. True when none of them is still loaded afterwards.
    public static func unload(_ names: [String], timeout: TimeInterval = 10) -> Bool {
        for n in names {
            let body = try? JSONSerialization.data(withJSONObject: ["model": n, "keep_alive": 0])
            _ = request(ollama.appendingPathComponent("api/generate"), body: body, timeout: timeout)
        }
        loadedCache.value = nil
        guard let still = loaded() else { return false }
        return !still.contains { names.contains($0.name) }
    }

    /// One request to Ollama on this Mac, waited for; nil on any failure.
    static func request(_ url: URL, body: Data?, timeout: TimeInterval) -> Data? {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        if let body { r.httpMethod = "POST"; r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let done = DispatchSemaphore(value: 0)
        let out = Locked<Data?>(nil)
        URLSession.shared.dataTask(with: r) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { out.value = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return out.value
    }

    /// The one-click option for loaded models: frees their memory; the next question loads a model again.
    public static func unloadFix(_ models: [Model], recommended: Bool) -> Fix? {
        guard !models.isEmpty else { return nil }
        let names = models.map(\.name)
        let size = Fmt.bytes(models.reduce(0) { $0 + $1.bytes })
        let what = models.count == 1 ? names[0] : "\(models.count) models"
        return Fix(id: "unload", title: "Unload \(what)", consequence: "Frees \(size). Ollama loads it again the next time it's asked something, which takes a few seconds.",
                   kind: .unloadModels(names), recommended: recommended)
    }

    // MARK: Xcode's build data

    public static var derivedData: String { NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData" }

    /// Space a folder takes on disk; nil when it isn't there. Can take a while for a big folder: read off the main thread.
    public static func size(of folder: String) -> UInt64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys) else { return 0 }
        var total: UInt64 = 0
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += UInt64(v.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// Worth offering: at least 1 GB.
    public static let worthDeleting: UInt64 = 1_000_000_000

    /// The one-click option to delete Xcode's build data, when it's big enough to matter.
    public static func buildDataFix(bytes: UInt64?, folder: String = derivedData) -> Fix? {
        guard let b = bytes, b >= worthDeleting else { return nil }
        return Fix(id: "builddata", title: "Delete Xcode's build data",
                   consequence: "Frees \(MemoryAdvice.diskGB(b)). Xcode rebuilds what it needs, so the next build of each project takes longer.",
                   kind: .deleteBuildData(folder), recommended: true)
    }

    /// Deletes the folder's contents (the folder stays, as Xcode expects). Only Xcode's own DerivedData folder, or the
    /// selftest's stand-in.
    public static func deleteBuildData(_ folder: String) -> Bool {
        guard folder == derivedData || folder.hasSuffix("/coolhead-selftest-DerivedData") else { return false }
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] { try? fm.removeItem(atPath: folder + "/" + item) }
        return ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).isEmpty
    }

    /// The size, read again at most every 10 minutes, in the background; nil until first read.
    public static func buildDataSize(now: Date = Date()) -> UInt64? {
        let c = sizeCache.value
        if (c.read.map { now.timeIntervalSince($0) >= 600 } ?? true), !c.reading {
            sizeCache.with { $0.reading = true }
            DispatchQueue.global(qos: .utility).async {
                let s = size(of: derivedData)
                sizeCache.with { $0 = (Date(), s, false) }
            }
        }
        return c.bytes
    }
    static let sizeCache = Locked<(read: Date?, bytes: UInt64?, reading: Bool)>((nil, nil, false))
}

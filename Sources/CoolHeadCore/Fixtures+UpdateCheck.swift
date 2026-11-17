import Foundation

/// Checks for the update's macOS check (see UpdateCheck.swift): an update is installed only on a Mac at or above its
/// minimum macOS, and the message says why when it isn't.
extension Fixture {
    static func updateCheckChecks(_ now: Date) -> [(String, Bool, String)] {
        func os(_ a: Int, _ b: Int, _ c: Int = 0) -> OperatingSystemVersion { OperatingSystemVersion(majorVersion: a, minorVersion: b, patchVersion: c) }
        let cases: [(String?, OperatingSystemVersion, Bool)] = [
            ("14.0", os(14, 7, 1), true), ("15.0", os(14, 7, 1), false), ("15", os(15, 0), true), ("15.2", os(15, 1, 9), false),
            ("15.2", os(26, 6, 2), true), ("26.4", os(26, 6, 2), true), ("27.0", os(26, 6, 2), false), (nil, os(14, 0), true),
        ]
        let results = cases.map { UpdateCheck.runs(minimum: $0.0, on: $0.1) }
        let ok = results == cases.map(\.2)
            && UpdateCheck.tooOld(version: "0.9.0", minimum: "15.0") == "Cool Head 0.9.0 needs macOS 15.0 or later. This copy stays as it is."
            && UpdateCheck.runs(minimum: "14.0")          // this Mac, as built
        return [("update-checks-macos", ok, zip(cases, results).map { "\($0.0.0 ?? "none") on \($0.0.1.majorVersion).\($0.0.1.minorVersion): \($0.1 ? "installs" : "kept")" }.joined(separator: ", "))]
    }
}

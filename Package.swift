// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CoolHead",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "coolhead", targets: ["coolhead"]),
        .executable(name: "CoolHeadApp", targets: ["CoolHeadApp"]),
        .executable(name: "coolhead-chrome-host", targets: ["coolhead-chrome-host"]),
        .library(name: "CoolHeadCore", targets: ["CoolHeadCore"]),
    ],
    targets: [
        .target(name: "CoolHeadCore", dependencies: ["CoolHeadChromeLink"], linkerSettings: [.linkedFramework("IOKit")], plugins: ["Lists"]),
        // the host is listed so building coolhead builds it too, for the selftest to run (it isn't linked in)
        .executableTarget(name: "coolhead", dependencies: ["CoolHeadCore", "coolhead-chrome-host"]),
        .executableTarget(name: "CoolHeadApp", dependencies: ["CoolHeadCore"],
                          linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications")],
                          plugins: ["Lists"]),
        // the link with Cool Head for Chrome (notes/chrome-link-protocol.md), a target of its own so the host below
        // stays small: it loads none of CoolHeadCore's frameworks (AppKit, IOKit, Network), only Foundation's
        .target(name: "CoolHeadChromeLink"),
        // Cool Head for Chrome's native messaging host, which build-app.sh puts in Contents/Helpers
        .executableTarget(name: "coolhead-chrome-host", dependencies: ["CoolHeadChromeLink"]),
        // writes the selftest's and the app's lists from the file names, while building (Plugins/Lists/Lists.swift)
        .plugin(name: "Lists", capability: .buildTool()),
    ]
)

// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CoolHead",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "coolhead", targets: ["coolhead"]),
        .library(name: "CoolHeadCore", targets: ["CoolHeadCore"]),
    ],
    targets: [
        .target(name: "CoolHeadCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "coolhead", dependencies: ["CoolHeadCore"]),
    ]
)

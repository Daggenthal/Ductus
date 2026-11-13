// swift-tools-version: 6.0
import PackageDescription

// The engine and logger import Foundation only (no AppKit / SwiftUI),
// so they stay portable and testable with `swift test`.
let package = Package(
    name: "DuctusEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DuctusEngine", targets: ["DuctusEngine"]),
        .library(name: "DuctusLog", targets: ["DuctusLog"]),
    ],
    targets: [
        .target(name: "DuctusEngine", resources: [.copy("Resources/english-words.tsv")]),
        .target(name: "DuctusLog"),
        .executableTarget(name: "ductus-demo", dependencies: ["DuctusEngine", "DuctusLog"]),
        .testTarget(name: "DuctusEngineTests", dependencies: ["DuctusEngine"]),
        .testTarget(name: "DuctusLogTests", dependencies: ["DuctusLog"]),
    ]
)

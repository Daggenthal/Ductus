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
        .target(name: "DuctusEngine", resources: [
            .copy("Resources/english-words.tsv"),
            .copy("Resources/english-sentences.txt"),
            .copy("Resources/french-words.tsv"),
            .copy("Resources/french-sentences.txt"),
            .copy("Resources/spanish-words.tsv"),
            .copy("Resources/spanish-sentences.txt"),
            .copy("Resources/german-words.tsv"),
            .copy("Resources/german-sentences.txt"),
            .copy("Resources/italian-words.tsv"),
            .copy("Resources/italian-sentences.txt"),
            .copy("Resources/portuguese-words.tsv"),
            .copy("Resources/portuguese-sentences.txt"),
            .copy("Resources/dutch-words.tsv"),
            .copy("Resources/dutch-sentences.txt"),
            .copy("Resources/japanese-words.tsv"),
            .copy("Resources/japanese-sentences.txt"),
            .copy("Resources/japanese-credits.tsv"),
            .copy("Resources/chinese-words.tsv"),
            .copy("Resources/chinese-sentences.txt"),
            .copy("Resources/chinese-credits.tsv"),
            .copy("Resources/korean-words.tsv"),
            .copy("Resources/korean-sentences.txt"),
            .copy("Resources/korean-credits.tsv"),
        ]),
        .target(name: "DuctusLog"),
        .executableTarget(name: "ductus-demo", dependencies: ["DuctusEngine", "DuctusLog"]),
        .testTarget(name: "DuctusEngineTests", dependencies: ["DuctusEngine"]),
        .testTarget(name: "DuctusLogTests", dependencies: ["DuctusLog"]),
    ]
)

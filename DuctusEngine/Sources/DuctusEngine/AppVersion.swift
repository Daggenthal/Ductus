import Foundation

/// A version like 0.1.0 or v1.2, for comparing the running app with a GitHub release.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Parses "0.1.0", "v0.1.0" or "1.2". Anything after a "-" (pre-release) is ignored.
    /// `nil` if there is no leading number.
    public init?(_ text: String) {
        var core = Substring(text.trimmingCharacters(in: .whitespaces))
        if core.first == "v" || core.first == "V" { core = core.dropFirst() }
        core = core.split(separator: "-", maxSplits: 1).first ?? core
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// Missing parts count as 0, so 1.2 == 1.2.0.
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// Reads `SHA256SUMS.txt` lines ("<hex>  <file name>") into file name → checksum.
public enum Checksums {
    public static func parse(_ text: String) -> [String: String] {
        var sums: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) else { continue }
            sums[String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))] = parts[0].lowercased()
        }
        return sums
    }
}

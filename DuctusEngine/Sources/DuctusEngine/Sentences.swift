import Foundation

/// Real sentences from public-domain books (see CORPUS.md), for sentence drills
/// and races.
public struct SentenceList: Sendable {
    public struct Entry: Sendable, Equatable {
        public let text: String
        /// Lowercase letters used, for filtering by unlocked letters.
        public let letters: Set<Character>
    }

    public let entries: [Entry]

    /// One sentence per line. Blank lines are ignored.
    public init(text: String) {
        entries = text.split(separator: "\n").compactMap { line in
            let sentence = line.trimmingCharacters(in: .whitespaces)
            guard !sentence.isEmpty else { return nil }
            let letters = Set(sentence.lowercased().filter(\.isASCIILowercaseLetter))
            return Entry(text: sentence, letters: letters)
        }
    }

    public static func bundledEnglish() throws -> SentenceList {
        guard let url = Bundle.module.url(forResource: "english-sentences", withExtension: "txt") else {
            throw EngineError.missingResource("english-sentences.txt")
        }
        return SentenceList(text: try String(contentsOf: url, encoding: .utf8))
    }

    /// Sentences whose letters are all in `allowed` (capitals and punctuation are fine).
    public func sentences(using allowed: Set<Character>) -> [Entry] {
        entries.filter { $0.letters.isSubset(of: allowed) }
    }

    /// Picks sentences until at least `minCharacters` long, joined by spaces.
    /// With `weakness`, sentences full of weak letters are picked more often.
    public static func pick<G: RandomNumberGenerator>(
        from pool: [Entry],
        minCharacters: Int,
        weakness: [Character: Double] = [:],
        using rng: inout G
    ) -> String? {
        guard !pool.isEmpty else { return nil }
        var picked: [String] = []
        var length = 0
        while length < minCharacters {
            let entry = pool.weightedRandomElement(using: &rng) { entry in
                let letters = entry.text.lowercased().filter(\.isASCIILowercaseLetter)
                guard !letters.isEmpty else { return 1 }
                let total = letters.reduce(0) { $0 + (weakness[$1] ?? 0) }
                return 1 + total / Double(letters.count) * 3
            }!
            if picked.last == entry.text, pool.count > 1 { continue }
            length += (picked.isEmpty ? 0 : 1) + entry.text.count  // joined length, spaces included
            picked.append(entry.text)
        }
        return picked.joined(separator: " ")
    }
}

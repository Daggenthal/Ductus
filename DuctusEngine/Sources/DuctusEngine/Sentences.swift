import Foundation

/// Real sentences from public-domain books (see CORPUS.md), for sentence drills
/// and races.
public struct SentenceList: Sendable {
    public struct Entry: Sendable, Equatable {
        /// What you type.
        public let text: String
        /// Lowercase letters used, for filtering by unlocked letters.
        public let letters: Set<Character>
        /// For romanized languages: the native text of each space-separated
        /// chunk of `text`, in order ("私は", "眠らなければ", ...).
        public let native: [String]?
    }

    public let entries: [Entry]

    /// One sentence per line. Blank lines are ignored. Romanized sentences are
    /// `typed<TAB>native chunks joined by "|"`, one chunk per typed word.
    public init(text: String) {
        entries = text.split(separator: "\n").compactMap { line in
            let columns = line.split(separator: "\t", maxSplits: 1)
            let sentence = columns[0].trimmingCharacters(in: .whitespaces)
            guard !sentence.isEmpty else { return nil }
            let letters = Set(sentence.lowercased().typingUnits.filter(\.isTypingLetter))
            var native: [String]?
            if columns.count == 2 {
                let chunks = columns[1].split(separator: "|").map(String.init)
                // Only trust the chunks if they line up with the typed words.
                if chunks.count == sentence.split(separator: " ").count { native = chunks }
            }
            return Entry(text: sentence, letters: letters, native: native)
        }
    }

    public static func bundled(_ language: PracticeLanguage) throws -> SentenceList {
        guard let url = Bundle.module.url(forResource: language.sentencesResource, withExtension: "txt") else {
            throw EngineError.missingResource("\(language.sentencesResource).txt")
        }
        return SentenceList(text: try String(contentsOf: url, encoding: .utf8))
    }

    public static func bundledEnglish() throws -> SentenceList { try bundled(.english) }

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
        pickEntries(from: pool, minCharacters: minCharacters, weakness: weakness, using: &rng)?
            .map(\.text).joined(separator: " ")
    }

    /// Like `pick`, but returns the sentences, so their native text can be shown.
    public static func pickEntries<G: RandomNumberGenerator>(
        from pool: [Entry],
        minCharacters: Int,
        weakness: [Character: Double] = [:],
        using rng: inout G
    ) -> [Entry]? {
        guard !pool.isEmpty else { return nil }
        var picked: [Entry] = []
        var length = 0
        while length < minCharacters {
            let entry = pool.weightedRandomElement(using: &rng) { entry in
                let letters = entry.text.lowercased().typingUnits.filter(\.isTypingLetter)
                guard !letters.isEmpty else { return 1 }
                let total = letters.reduce(0) { $0 + (weakness[$1] ?? 0) }
                return 1 + total / Double(letters.count) * 3
            }!
            if picked.last?.text == entry.text, pool.count > 1 { continue }
            length += (picked.isEmpty ? 0 : 1) + entry.text.count  // joined length, spaces included
            picked.append(entry)
        }
        return picked
    }
}

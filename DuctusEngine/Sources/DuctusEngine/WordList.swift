import Foundation

public enum EngineError: Error, Equatable {
    case missingResource(String)
    case malformedLine(number: Int, line: String)
}

/// Words with frequency counts, for one language.
public struct WordList: Sendable {
    public struct Entry: Sendable, Equatable {
        /// As typed: lowercase, except German nouns ("Haus").
        public let word: String
        public let count: Int
        /// Lowercase letters, for matching against unlocked keys (case-folded like stats).
        public let letters: Set<Character>

        init(word: String, count: Int) {
            self.word = word
            self.count = count
            self.letters = Set(word.lowercased())
        }
    }

    /// Sorted by count, most common first.
    public let entries: [Entry]

    /// Words are lowercased unless `keepCase` (German nouns). Anything that is
    /// not made only of letters (accents are fine) is dropped.
    public init(_ words: [(word: String, count: Int)], keepCase: Bool = false) {
        var kept: [Entry] = []
        for (word, count) in words {
            let word = keepCase ? word : word.lowercased()
            guard !word.isEmpty, count > 0, word.allSatisfy(\.isLetter) else { continue }
            kept.append(Entry(word: word, count: count))
        }
        kept.sort { a, b in a.count != b.count ? a.count > b.count : a.word < b.word }
        entries = kept
    }

    /// Parses `word<TAB>count` lines. Blank lines are ignored.
    public init(tsv: String, keepCase: Bool = false) throws {
        var words: [(word: String, count: Int)] = []
        for (index, line) in tsv.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let count = Int(parts[1]) else {
                throw EngineError.malformedLine(number: index + 1, line: String(line))
            }
            words.append((String(parts[0]), count))
        }
        self.init(words, keepCase: keepCase)
    }

    /// The bundled list for `language`, built from public-domain books (see CORPUS.md).
    public static func bundled(_ language: PracticeLanguage) throws -> WordList {
        guard let url = Bundle.module.url(forResource: language.wordsResource, withExtension: "tsv") else {
            throw EngineError.missingResource("\(language.wordsResource).tsv")
        }
        return try WordList(tsv: String(contentsOf: url, encoding: .utf8), keepCase: language.keepsCase)
    }

    public static func bundledEnglish() throws -> WordList { try bundled(.english) }

    /// Letters ordered by how often they appear in running text (word counts included).
    public func letterFrequencyOrder() -> [Character] {
        var counts: [Character: Int] = [:]
        for entry in entries {
            for letter in entry.word.lowercased() { counts[letter, default: 0] += entry.count }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Words made only of `allowed` letters.
    public func words(using allowed: Set<Character>) -> [Entry] {
        entries.filter { $0.letters.isSubset(of: allowed) }
    }
}

extension Character {
    var isASCIILowercaseLetter: Bool { ("a"..."z").contains(self) }
}

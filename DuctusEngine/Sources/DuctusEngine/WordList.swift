import Foundation

public enum EngineError: Error, Equatable {
    case missingResource(String)
    case malformedLine(number: Int, line: String)
}

/// Lowercase English words with frequency counts.
public struct WordList: Sendable {
    public struct Entry: Sendable, Equatable {
        public let word: String
        public let count: Int
        public let letters: Set<Character>

        init(word: String, count: Int) {
            self.word = word
            self.count = count
            self.letters = Set(word)
        }
    }

    /// Sorted by count, most common first.
    public let entries: [Entry]

    /// Words are lowercased. Anything that is not a plain `a`-`z` word is dropped.
    public init(_ words: [(word: String, count: Int)]) {
        var kept: [Entry] = []
        for (word, count) in words {
            let lower = word.lowercased()
            guard !lower.isEmpty, count > 0, lower.allSatisfy(\.isASCIILowercaseLetter) else { continue }
            kept.append(Entry(word: lower, count: count))
        }
        kept.sort { a, b in a.count != b.count ? a.count > b.count : a.word < b.word }
        entries = kept
    }

    /// Parses `word<TAB>count` lines. Blank lines are ignored.
    public init(tsv: String) throws {
        var words: [(word: String, count: Int)] = []
        for (index, line) in tsv.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let count = Int(parts[1]) else {
                throw EngineError.malformedLine(number: index + 1, line: String(line))
            }
            words.append((String(parts[0]), count))
        }
        self.init(words)
    }

    /// The bundled list built from public-domain books (see CORPUS.md).
    public static func bundledEnglish() throws -> WordList {
        guard let url = Bundle.module.url(forResource: "english-words", withExtension: "tsv") else {
            throw EngineError.missingResource("english-words.tsv")
        }
        return try WordList(tsv: String(contentsOf: url, encoding: .utf8))
    }

    /// Letters ordered by how often they appear in running text (word counts included).
    public func letterFrequencyOrder() -> [Character] {
        var counts: [Character: Int] = [:]
        for entry in entries {
            for letter in entry.word { counts[letter, default: 0] += entry.count }
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

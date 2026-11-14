import Foundation

/// The numbered choices a pinyin input method shows after you type a word's
/// pinyin ("ni" -> 1 你 2 呢 3 泥 ...), built from the HSK word lists so Study can
/// ask you to pick the right characters, the way you would when typing Chinese.
public struct PinyinCandidates: Sendable {
    /// Typed pinyin -> words that are typed the same, most common first.
    private let words: [String: [String]]
    /// A syllable without tones -> single characters with that reading, most common first.
    private let characters: [String: [String]]

    /// From word sets in order (HSK 1 first), each most common first, so earlier
    /// words come first in the list, much like an input method ranks them.
    public init(sets: [StudySet]) {
        var words: [String: [String]] = [:]
        var characters: [String: [String]] = [:]
        for set in sets {
            for word in set.words {
                if !(words[word.typed]?.contains(word.native) ?? false) {
                    words[word.typed, default: []].append(word.native)
                }
                if word.native.count == 1, !(characters[word.typed]?.contains(word.native) ?? false) {
                    characters[word.typed, default: []].append(word.native)
                }
            }
        }
        self.words = words
        self.characters = characters
    }

    /// All bundled HSK sets.
    public static func bundled() -> PinyinCandidates {
        PinyinCandidates(sets: StudySet.catalog.compactMap { try? StudySet.bundled($0.id) })
    }

    /// Up to `limit` choices for a word, always including the word itself:
    /// words typed the same way, then single characters for its first syllable.
    public func candidates(for word: StudyWord, limit: Int = 6) -> [String] {
        var list = words[word.typed] ?? []
        if !list.contains(word.native) { list.insert(word.native, at: 0) }
        if list.count < 4, let first = Self.syllables(word.reading).first {
            for character in characters[first] ?? [] where !list.contains(character) && list.count < limit {
                list.append(character)
            }
        }
        if list.count > limit {
            let kept = Array(list.prefix(limit))
            list = kept.contains(word.native) ? kept : Array(kept.prefix(limit - 1)) + [word.native]
        }
        return list
    }

    /// "nǐ hǎo" -> ["ni", "hao"]; ü is typed as v.
    static func syllables(_ reading: String) -> [String] {
        reading.lowercased().split(separator: " ").map { syllable in
            let plain = String(syllable).replacingOccurrences(of: "ü", with: "v")
                .replacingOccurrences(of: "ǖ", with: "v").replacingOccurrences(of: "ǘ", with: "v")
                .replacingOccurrences(of: "ǚ", with: "v").replacingOccurrences(of: "ǜ", with: "v")
            return String(plain.decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { $0.isASCII && CharacterSet.letters.contains($0) }.map(Character.init))
        }
    }
}

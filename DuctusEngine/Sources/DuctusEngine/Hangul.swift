/// Hangul on the 2-Set (Dubeolsik) keyboard: which keys make a syllable, and
/// what a half-typed syllable looks like, the way a Korean input method shows it.
///
/// Drills store Korean as the jamo keys pressed ("ㅇㅏㄴㄴㅕㅇ"), so stats work per
/// key. These helpers turn that back into syllable blocks (안녕) for display.
public enum Hangul {
    static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { $0 }
    /// Compound vowels and final pairs are typed as two keys.
    static let twoKeys: [Character: [Character]] = [
        "ㅘ": ["ㅗ", "ㅏ"], "ㅙ": ["ㅗ", "ㅐ"], "ㅚ": ["ㅗ", "ㅣ"], "ㅝ": ["ㅜ", "ㅓ"], "ㅞ": ["ㅜ", "ㅔ"],
        "ㅟ": ["ㅜ", "ㅣ"], "ㅢ": ["ㅡ", "ㅣ"],
        "ㄳ": ["ㄱ", "ㅅ"], "ㄵ": ["ㄴ", "ㅈ"], "ㄶ": ["ㄴ", "ㅎ"], "ㄺ": ["ㄹ", "ㄱ"], "ㄻ": ["ㄹ", "ㅁ"],
        "ㄼ": ["ㄹ", "ㅂ"], "ㄽ": ["ㄹ", "ㅅ"], "ㄾ": ["ㄹ", "ㅌ"], "ㄿ": ["ㄹ", "ㅍ"], "ㅀ": ["ㄹ", "ㅎ"],
        "ㅄ": ["ㅂ", "ㅅ"],
    ]

    struct Parts {
        let initial: Int
        let vowel: Int
        let final: Int
    }

    static func parts(of syllable: Character) -> Parts? {
        guard let scalar = syllable.unicodeScalars.first, syllable.unicodeScalars.count == 1 else { return nil }
        let index = Int(scalar.value) - 0xAC00
        guard (0..<11172).contains(index) else { return nil }
        return Parts(initial: index / (21 * 28), vowel: (index % (21 * 28)) / 28, final: index % 28)
    }

    static func syllable(initial: Int, vowel: Int, final: Int) -> Character {
        Character(Unicode.Scalar(UInt32(0xAC00 + (initial * 21 + vowel) * 28 + final))!)
    }

    public static func isSyllable(_ character: Character) -> Bool { parts(of: character) != nil }

    /// The 2-Set keys for a syllable, in order: 와 → ㅇ ㅗ ㅏ, 닭 → ㄷ ㅏ ㄹ ㄱ.
    /// Anything that is not a syllable is its own single key.
    public static func keys(of character: Character) -> [Character] {
        guard let parts = parts(of: character) else { return [character] }
        var keys: [Character] = [initials[parts.initial]]
        let vowel = vowels[parts.vowel]
        keys += twoKeys[vowel] ?? [vowel]
        if let final = finals[parts.final] { keys += twoKeys[final] ?? [final] }
        return keys
    }

    /// What `syllable` looks like after its first `count` keys, like an input
    /// method composes it: 한 after 1 key is ㅎ, after 2 is 하, after 3 is 한.
    public static func composed(_ syllable: Character, afterKeys count: Int) -> String {
        let keys = keys(of: syllable)
        guard let parts = parts(of: syllable), count > 0 else { return count > 0 ? String(syllable) : "" }
        if count >= keys.count { return String(syllable) }
        if count == 1 { return String(keys[0]) }

        let vowelKeys = (twoKeys[vowels[parts.vowel]] ?? [vowels[parts.vowel]]).count
        let typedVowelKeys = min(count - 1, vowelKeys)
        // A compound vowel with only its first key typed shows that first vowel (와 → 오).
        let vowel = typedVowelKeys == vowelKeys
            ? parts.vowel
            : vowels.firstIndex(of: twoKeys[vowels[parts.vowel]]![0])!
        let typedFinalKeys = count - 1 - vowelKeys
        guard typedFinalKeys > 0, let final = finals[parts.final] else {
            return String(Self.syllable(initial: parts.initial, vowel: vowel, final: 0))
        }
        // A final pair with only its first key typed shows that first consonant (닭 → 달).
        let partialFinal = twoKeys[final].map { $0[0] } ?? final
        let finalIndex = finals.firstIndex(of: partialFinal)!
        return String(Self.syllable(initial: parts.initial, vowel: vowel, final: finalIndex))
    }

    /// One block on screen and the keys it covers in the typing text.
    public struct Block: Sendable, Equatable {
        /// Character offsets of its keys in the typing text.
        public let range: Range<Int>
        /// The syllable, or the space or punctuation mark, shown for it.
        public let character: Character
    }

    /// Groups the jamo keys of a Korean typing text into syllable blocks, using
    /// the Hangul in `gloss`. Text the gloss does not cover (spaces) and any word
    /// whose keys do not line up are shown one character per block.
    public static func blocks(text: [Character], gloss: Gloss) -> [Block] {
        var blocks: [Block] = []
        var position = 0
        func single(upTo end: Int) {
            while position < end {
                blocks.append(Block(range: position..<(position + 1), character: text[position]))
                position += 1
            }
        }
        for segment in gloss.segments where segment.range.lowerBound >= position {
            single(upTo: segment.range.lowerBound)
            let keyCounts = segment.native.map { keys(of: $0).count }
            let matches = keyCounts.reduce(0, +) == segment.range.count
                && zip(segment.native, segmentKeys(segment, text)).allSatisfy { $0.1 == keys(of: $0.0) }
            if matches {
                for (character, count) in zip(segment.native, keyCounts) {
                    blocks.append(Block(range: position..<(position + count), character: character))
                    position += count
                }
            } else {
                single(upTo: segment.range.upperBound)
            }
        }
        single(upTo: text.count)
        return blocks
    }

    /// The typed keys of a segment, split the way its native syllables expect.
    private static func segmentKeys(_ segment: Gloss.Segment, _ text: [Character]) -> [[Character]] {
        var result: [[Character]] = []
        var index = segment.range.lowerBound
        for character in segment.native {
            let count = keys(of: character).count
            let end = min(index + count, segment.range.upperBound)
            result.append(Array(text[index..<end]))
            index = end
        }
        return result
    }
}

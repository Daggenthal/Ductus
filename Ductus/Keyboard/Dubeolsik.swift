/// The Korean 2-Set (Dubeolsik, KS X 5002) layout: which jamo each physical key types.
///
/// This is the one hardcoded layout in Ductus. macOS Korean input methods do
/// not publish key layout data (no `uchr`), and 2-Set is a national standard
/// tied to physical key positions, the same on every Mac keyboard. Keys are
/// listed by keycode, so the Q-position key is ㅂ whatever layout it types through.
enum Dubeolsik {
    /// keycode → (plain, with Shift). Shift only changes five keys to tense
    /// consonants and two vowels; on the rest it types the same jamo.
    static let keys: [UInt16: (plain: Character, shifted: Character)] = [
        12: ("ㅂ", "ㅃ"), 13: ("ㅈ", "ㅉ"), 14: ("ㄷ", "ㄸ"), 15: ("ㄱ", "ㄲ"), 17: ("ㅅ", "ㅆ"),
        16: ("ㅛ", "ㅛ"), 32: ("ㅕ", "ㅕ"), 34: ("ㅑ", "ㅑ"), 31: ("ㅐ", "ㅒ"), 35: ("ㅔ", "ㅖ"),
        0: ("ㅁ", "ㅁ"), 1: ("ㄴ", "ㄴ"), 2: ("ㅇ", "ㅇ"), 3: ("ㄹ", "ㄹ"), 5: ("ㅎ", "ㅎ"),
        4: ("ㅗ", "ㅗ"), 38: ("ㅓ", "ㅓ"), 40: ("ㅏ", "ㅏ"), 37: ("ㅣ", "ㅣ"),
        6: ("ㅋ", "ㅋ"), 7: ("ㅌ", "ㅌ"), 8: ("ㅊ", "ㅊ"), 9: ("ㅍ", "ㅍ"), 11: ("ㅠ", "ㅠ"),
        45: ("ㅜ", "ㅜ"), 46: ("ㅡ", "ㅡ"),
    ]

    /// Home-row jamo, left to right: where Korean practice starts.
    static let homeRow: [Character] = ["ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "ㅗ", "ㅓ", "ㅏ", "ㅣ"]

    /// The jamo typed by a key, or `nil` for keys outside the 2-Set letters.
    static func jamo(code: UInt16, shift: Bool) -> Character? {
        keys[code].map { shift ? $0.shifted : $0.plain }
    }

    /// How to type each jamo. Unshifted wins when Shift makes no difference.
    static let strokes: [Character: KeyboardLayout.Stroke] = {
        var map: [Character: KeyboardLayout.Stroke] = [:]
        for (code, pair) in keys {
            map[pair.plain] = KeyboardLayout.Stroke(code: code)
        }
        for (code, pair) in keys where map[pair.shifted] == nil {
            map[pair.shifted] = KeyboardLayout.Stroke(code: code, shift: true)
        }
        return map
    }()

    static let allJamo: Set<Character> = Set(strokes.keys)
}

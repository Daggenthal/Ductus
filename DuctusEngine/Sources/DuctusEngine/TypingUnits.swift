/// What counts as one key press in drill text.
///
/// Swift treats a Devanagari syllable like कि as one character, but it is typed
/// as two keys (क, then the vowel sign ि), one Unicode code point per key on the
/// macOS Devanagari layouts. Drills, stats and unlocking work per key, so those
/// syllables are split into their code points. Everything else stays as is.
extension StringProtocol {
    public var typingUnits: [Character] {
        var units: [Character] = []
        for character in self {
            if character.isDevanagari, character.unicodeScalars.count > 1 {
                units += character.unicodeScalars.map(Character.init)
            } else {
                units.append(character)
            }
        }
        return units
    }
}

extension Character {
    var isDevanagari: Bool {
        unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }

    /// A letter for drills and unlocking. Devanagari vowel signs, the virama (्)
    /// and the nukta (़) have their own keys, so they count too.
    public var isTypingLetter: Bool {
        if isLetter { return true }
        guard isDevanagari, let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark: return true
        default: return false
        }
    }
}

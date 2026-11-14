import AppKit

/// Widths of drill text in the system monospaced font, including characters
/// drawn by a fallback font (Hangul jamo, kanji) that are wider than Latin
/// letters. Measuring "M" alone would misplace the cursor for those.
@MainActor
enum TextMeasure {
    private static var cache: [CGFloat: [Character: CGFloat]] = [:]

    static func font(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Advance of one character, cached per font size.
    static func advance(_ character: Character, size: CGFloat) -> CGFloat {
        if let width = cache[size]?[character] { return width }
        let width = (String(character) as NSString).size(withAttributes: [.font: font(size)]).width
        cache[size, default: [:]][character] = width
        return width
    }

    static func width<S: Sequence>(of characters: S, size: CGFloat) -> CGFloat where S.Element == Character {
        characters.reduce(0) { $0 + advance($1, size: size) }
    }
}

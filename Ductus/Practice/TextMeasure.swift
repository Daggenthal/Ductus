import AppKit
import SwiftUI

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

    /// Width of text as drawn, with letters joined. Arabic letters change shape
    /// (and width) with their neighbors, so adding up single letters is off.
    static func shapedWidth<S: Sequence>(of characters: S, size: CGFloat) -> CGFloat where S.Element == Character {
        (String(characters) as NSString).size(withAttributes: [.font: font(size)]).width
    }

    /// True when the text is written right to left (Arabic), judged by its first letter.
    static func isRightToLeft<C: Collection>(_ text: C) -> Bool where C.Element == Character {
        guard let letter = text.first(where: \.isLetter)?.unicodeScalars.first else { return false }
        // Hebrew, Arabic, Syriac, Thaana, NKo and the Arabic presentation forms.
        return (0x0590...0x08FF).contains(letter.value) || (0xFB1D...0xFDFF).contains(letter.value)
            || (0xFE70...0xFEFF).contains(letter.value)
    }
}

extension View {
    /// Lays text out right to left or left to right, whatever the app's own language is.
    func textDirection(rightToLeft: Bool) -> some View {
        environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    }
}

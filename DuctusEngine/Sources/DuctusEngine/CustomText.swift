import Foundation

/// Preparing text the user pastes in (an article, a chapter, some code) for typing.
public enum CustomText {
    public struct Cleaned: Sendable, Equatable {
        public let text: String
        /// Characters left out because the layout cannot type them (emoji, "€" without a key, ...).
        public let dropped: Int
    }

    /// Typographic characters replaced with ones a keyboard types.
    static let replacements: [Character: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
        "\u{2014}": "-", "\u{2013}": "-", "\u{2012}": "-", "\u{2212}": "-", "\u{2010}": "-", "\u{2011}": "-",
        "\u{2026}": "...", "\u{00A0}": " ", "\u{202F}": " ", "\u{2009}": " ", "\u{200A}": " ",
        "\u{2002}": " ", "\u{2003}": " ", "\u{00AD}": "", "\u{200B}": "", "\u{FEFF}": "",
    ]

    /// Cleans pasted text.
    /// - `keepLineBreaks`: For code and poems. Each line end is typed with Return
    ///   and leading indentation is removed (typing it is busywork). Otherwise
    ///   all whitespace becomes single spaces.
    /// - `canType`: Characters for which this returns `false` are left out.
    public static func clean(
        _ raw: String,
        keepLineBreaks: Bool = false,
        canType: (Character) -> Bool = { _ in true }
    ) -> Cleaned {
        var dropped = 0
        var normalized = ""
        for character in raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") {
            if let replacement = replacements[character] {
                normalized += replacement
            } else if character == "\t" {
                normalized += " "
            } else if character == "\n" || character == " " {
                normalized.append(character)
            } else if character.isWhitespace || character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                normalized += " "
            } else if canType(character) {
                normalized.append(character)
            } else {
                dropped += 1
            }
        }

        let text: String
        if keepLineBreaks {
            var lines: [String] = []
            var blank = false
            for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let squeezed = trimmed.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
                if squeezed.isEmpty {
                    // At most one blank line in a row, none at the start.
                    if !blank, !lines.isEmpty { lines.append("") }
                    blank = true
                } else {
                    lines.append(squeezed)
                    blank = false
                }
            }
            while lines.last == "" { lines.removeLast() }
            text = lines.joined(separator: "\n")
        } else {
            text = normalized.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
        }
        return Cleaned(text: text, dropped: dropped)
    }

    /// Splits text into parts of about `target` characters, breaking at a
    /// paragraph or line end, then a sentence end, then a space. Parts are
    /// never cut mid-word unless a single word is longer than `target`.
    public static func parts(of text: String, target: Int = 300) -> [String] {
        let characters = Array(text)
        var parts: [String] = []
        var start = 0
        while start < characters.count {
            let hardEnd = min(characters.count, start + target)
            var end = hardEnd
            if hardEnd < characters.count {
                let window = start..<hardEnd
                // Do not make parts shorter than half the target when avoidable.
                let minimum = start + target / 2
                if let newline = window.reversed().first(where: { characters[$0] == "\n" && $0 >= minimum }) {
                    end = newline + 1
                } else if let sentence = window.reversed().first(where: {
                    $0 >= minimum && ".!?".contains(characters[$0])
                        && $0 + 1 < characters.count && characters[$0 + 1] == " "
                }) {
                    end = sentence + 2  // include the space after it
                } else if let space = window.reversed().first(where: { characters[$0] == " " }), space > start {
                    end = space + 1
                }
            }
            let part = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { parts.append(part) }
            start = end
        }
        return parts
    }

    /// A short title from the first words, for the text list.
    public static func title(for text: String, maxLength: Int = 40) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        guard firstLine.count > maxLength else { return firstLine }
        let cut = firstLine.prefix(maxLength)
        if let space = cut.lastIndex(of: " ") { return cut[..<space] + "…" }
        return cut + "…"
    }
}

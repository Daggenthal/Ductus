/// Optional capitals and punctuation on top of plain drill words.
public struct TextStyle: Sendable, Equatable, Codable {
    public var capitals: Bool
    public var punctuation: Bool

    public init(capitals: Bool = false, punctuation: Bool = false) {
        self.capitals = capitals
        self.punctuation = punctuation
    }

    public var isPlain: Bool { !capitals && !punctuation }
}

public enum TextDecorator {
    /// Groups words into short sentences. With `capitals`, each sentence starts
    /// with a capital and some other words are capitalized too (not in German,
    /// where capitals mark nouns). With `punctuation`, sentences end in . ? or !
    /// (Spanish opens them with ¿ or ¡) and some words get a comma, semicolon
    /// or colon. The words themselves never change.
    public static func decorate<G: RandomNumberGenerator>(
        _ text: String,
        style: TextStyle,
        language: PracticeLanguage = .english,
        using rng: inout G
    ) -> String {
        // Romanized Japanese and Chinese have no capitals, and their punctuation
        // comes with real sentences.
        guard !style.isPlain, !language.hasTypedForm else { return text }
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }
        let randomCapitals = !language.keepsCase
        // French puts a space before ? ! : and ;.
        let spaced = { (mark: String) in
            language == .french && "?!:;".contains(mark) ? " " + mark : mark
        }

        var output: [String] = []
        var index = 0
        while index < words.count {
            let length = min(Int.random(in: 4...10, using: &rng), words.count - index)
            let ending = style.punctuation
                ? [language.fullStop, language.fullStop, language.fullStop, language.fullStop, language.questionMark, "!"].randomElement(using: &rng)! : ""
            for offset in 0..<length {
                var word = words[index + offset]
                let isFirst = offset == 0
                let isLast = offset == length - 1

                if style.capitals,
                   isFirst || (randomCapitals && Double.random(in: 0..<1, using: &rng) < 0.08) {
                    word = word.prefix(1).uppercased(with: language.locale) + word.dropFirst()
                }
                if style.punctuation {
                    if isFirst, language.usesInvertedMarks {
                        if ending == language.questionMark { word = "¿" + word } else if ending == "!" { word = "¡" + word }
                    }
                    if isLast {
                        word += spaced(ending)
                    } else {
                        let roll = Double.random(in: 0..<1, using: &rng)
                        if roll < 0.12 { word += language.comma }
                        else if roll < 0.14 { word += spaced(language.semicolon) }
                        else if roll < 0.15 { word += spaced(":") }
                    }
                }
                output.append(word)
            }
            index += length
        }
        return output.joined(separator: " ")
    }
}

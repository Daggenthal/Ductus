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
    /// with a capital and some other words are capitalized too. With
    /// `punctuation`, sentences end in . ? or ! and some words get a comma,
    /// semicolon or colon. The words themselves never change.
    public static func decorate<G: RandomNumberGenerator>(
        _ text: String,
        style: TextStyle,
        using rng: inout G
    ) -> String {
        guard !style.isPlain else { return text }
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        var output: [String] = []
        var index = 0
        while index < words.count {
            let length = min(Int.random(in: 4...10, using: &rng), words.count - index)
            for offset in 0..<length {
                var word = words[index + offset]
                let isFirst = offset == 0
                let isLast = offset == length - 1

                if style.capitals, isFirst || Double.random(in: 0..<1, using: &rng) < 0.08 {
                    word = word.prefix(1).uppercased() + word.dropFirst()
                }
                if style.punctuation {
                    if isLast {
                        word += ["." , ".", ".", ".", "?", "!"].randomElement(using: &rng)!
                    } else {
                        let roll = Double.random(in: 0..<1, using: &rng)
                        if roll < 0.12 { word += "," }
                        else if roll < 0.14 { word += ";" }
                        else if roll < 0.15 { word += ":" }
                    }
                }
                output.append(word)
            }
            index += length
        }
        return output.joined(separator: " ")
    }
}

import Foundation

/// Languages with a bundled word list and sentence sample (see CORPUS.md).
public enum PracticeLanguage: String, CaseIterable, Sendable, Codable, Identifiable {
    case english, french, spanish, german, italian, portuguese, dutch

    public var id: String { rawValue }

    /// ISO 639-1 code, as macOS reports for input sources.
    public var code: String {
        switch self {
        case .english: "en"
        case .french: "fr"
        case .spanish: "es"
        case .german: "de"
        case .italian: "it"
        case .portuguese: "pt"
        case .dutch: "nl"
        }
    }

    /// The language's own name for itself.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        }
    }

    /// From a language code like "fr" or "pt-BR". `nil` if not bundled.
    public init?(code: String) {
        let base = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        guard let match = Self.allCases.first(where: { $0.code == base }) else { return nil }
        self = match
    }

    /// German capitalizes nouns, so word lists keep their case.
    public var keepsCase: Bool { self == .german }

    /// Spanish opens questions and exclamations with ¿ and ¡.
    public var usesInvertedMarks: Bool { self == .spanish }

    var wordsResource: String { "\(rawValue)-words" }
    var sentencesResource: String { "\(rawValue)-sentences" }
}

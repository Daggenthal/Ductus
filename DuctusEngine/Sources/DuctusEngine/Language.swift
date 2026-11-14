import Foundation

/// Languages with a bundled word list and sentence sample (see CORPUS.md).
public enum PracticeLanguage: String, CaseIterable, Sendable, Codable, Identifiable {
    case english, french, spanish, german, italian, portuguese, dutch, russian, ukrainian, arabic, japanese, chinese, korean

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
        case .russian: "ru"
        case .ukrainian: "uk"
        case .arabic: "ar"
        case .japanese: "ja"
        case .chinese: "zh"
        case .korean: "ko"
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
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .arabic: "العربية"
        case .japanese: "日本語"
        case .chinese: "中文"
        case .korean: "한국어"
        }
    }

    /// Typed in a different form than it is shown, with the native text shown
    /// alongside: Japanese as romaji ("nihongo"), Chinese as toneless pinyin
    /// ("zhongwen"), Korean as the 2-Set jamo keys pressed ("ㅇㅏㄴㄴㅕㅇ" for 안녕).
    public var hasTypedForm: Bool { self == .japanese || self == .chinese || self == .korean }

    /// What you type, for the UI: "romaji", "pinyin", "jamo" or nil.
    public var typedFormName: String? {
        switch self {
        case .japanese: "romaji"
        case .chinese: "pinyin"
        case .korean: "jamo"
        default: nil
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

    /// Written and typed right to left.
    public var isRightToLeft: Bool { self == .arabic }

    /// Punctuation drills add: Arabic has its own comma, semicolon and question mark.
    public var comma: String { self == .arabic ? "،" : "," }
    public var semicolon: String { self == .arabic ? "؛" : ";" }
    public var questionMark: String { self == .arabic ? "؟" : "?" }

    /// Spanish opens questions and exclamations with ¿ and ¡.
    public var usesInvertedMarks: Bool { self == .spanish }

    /// Authors of the bundled sentences, for languages whose sentences need
    /// credit (Tatoeba, CC BY 2.0 FR): (author, number of sentences), most first.
    public func sentenceAuthors() -> [(author: String, sentences: Int)] {
        guard let url = Bundle.module.url(forResource: "\(rawValue)-credits", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            if columns.count == 2 { counts[String(columns[1]), default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.sentences != $1.sentences ? $0.sentences > $1.sentences : $0.author < $1.author }
    }

    var wordsResource: String { "\(rawValue)-words" }
    var sentencesResource: String { "\(rawValue)-sentences" }
}

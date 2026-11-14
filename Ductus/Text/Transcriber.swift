import DuctusEngine
import Foundation

/// Turns pasted Japanese, Chinese or Korean text into what you type for it
/// (romaji, toneless pinyin, 2-Set jamo keys), paired with the original words
/// so they can be shown while you type.
///
/// Japanese and Chinese readings come from the macOS word tokenizer
/// (`CFStringTokenizer` Latin transcription), so nothing extra is downloaded.
enum Transcriber {
    struct Result {
        /// Typing text: words separated by spaces.
        let typed: String
        /// The original text for each typed word, in order.
        let chunks: [String]
        /// Characters left out (symbols, emoji, unreadable words).
        let dropped: Int
    }

    /// The language of `text` by its script, or `nil` for Latin text.
    static func language(of text: String) -> PracticeLanguage? {
        var hangul = 0, kana = 0, han = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7A3: hangul += 1
            case 0x3041...0x30FF: kana += 1
            case 0x4E00...0x9FFF: han += 1
            default: break
            }
        }
        if hangul > 0, hangul >= kana + han { return .korean }
        if kana > 0 { return .japanese }
        if han > 0 { return .chinese }
        return nil
    }

    static func transcribe(_ text: String, as language: PracticeLanguage) -> Result? {
        switch language {
        case .korean: korean(text)
        case .japanese: tokenized(text, locale: "ja", japanese: true)
        case .chinese: tokenized(text, locale: "zh", japanese: false)
        default: nil
        }
    }

    /// Full-width punctuation to the key you type for it. Quote brackets are dropped.
    private static let punctuation: [Character: String] = [
        "。": ".", "、": ",", "，": ",", "？": "?", "！": "!", "：": ":", "；": ";", "．": ".",
        ".": ".", ",": ",", "?": "?", "!": "!", ":": ":", ";": ";",
        "「": "", "」": "", "『": "", "』": "", "“": "", "”": "", "\"": "", "（": "", "）": "", "(": "", ")": "",
        "・": "", "…": "...", "～": "", "〜": "",
    ]
    /// UniDic-style formal readings macOS also gives; everyday Japanese says watashi.
    private static let readingOverrides = ["私": "わたし", "私達": "わたしたち", "私たち": "わたしたち"]

    // MARK: - Korean

    private static func korean(_ text: String) -> Result? {
        var typed: [String] = []
        var chunks: [String] = []
        var dropped = 0
        for word in text.split(whereSeparator: \.isWhitespace) {
            var keys = ""
            var shown = ""
            for character in word {
                if Hangul.isSyllable(character) {
                    keys += String(Hangul.keys(of: character))
                    shown.append(character)
                } else if let mark = punctuation[character] {
                    keys += mark
                    if !mark.isEmpty { shown.append(character) }
                } else if character.isASCII, character.isLetter || character.isNumber {
                    keys.append(character)
                    shown.append(character)
                } else {
                    dropped += 1
                }
            }
            guard !keys.isEmpty else { continue }
            typed.append(keys)
            chunks.append(shown)
        }
        return typed.isEmpty ? nil : Result(typed: typed.joined(separator: " "), chunks: chunks, dropped: dropped)
    }

    // MARK: - Japanese and Chinese

    private struct Chunk {
        var reading: String  // kana for Japanese, pinyin for Chinese
        var shown: String
        var trailing = ""    // typed punctuation after it
    }

    private static func tokenized(_ text: String, locale: String, japanese: Bool) -> Result? {
        let string = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRangeMake(0, string.length), kCFStringTokenizerUnitWord,
            Locale(identifier: locale) as CFLocale
        )
        var chunks: [Chunk] = []
        var dropped = 0
        var cursor = 0

        func gap(upTo end: Int) {
            guard end > cursor else { return }
            for character in string.substring(with: NSRange(location: cursor, length: end - cursor)) {
                if character.isWhitespace { continue }
                if let mark = punctuation[character] {
                    if !chunks.isEmpty, !mark.isEmpty {
                        chunks[chunks.count - 1].trailing += mark
                        chunks[chunks.count - 1].shown.append(character)
                    }
                } else {
                    dropped += 1
                }
            }
        }

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            gap(upTo: range.location)
            cursor = range.location + range.length
            let surface = string.substring(with: NSRange(location: range.location, length: range.length))
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription)
                as? String ?? ""

            if japanese {
                guard let kana = kanaReading(surface, latin: latin) else {
                    dropped += surface.count
                    continue
                }
                // Particles and endings written in hiragana join the word before them (私は).
                let joins = surface.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
                if joins, !chunks.isEmpty, chunks[chunks.count - 1].trailing.isEmpty {
                    chunks[chunks.count - 1].reading += kana
                    chunks[chunks.count - 1].shown += surface
                } else {
                    chunks.append(Chunk(reading: kana, shown: surface))
                }
            } else {
                guard let pinyin = pinyin(surface, latin: latin) else {
                    dropped += surface.count
                    continue
                }
                chunks.append(Chunk(reading: pinyin, shown: surface))
            }
        }
        gap(upTo: string.length)

        var typed: [String] = []
        var shown: [String] = []
        for chunk in chunks {
            let reading = japanese ? (Romaji.from(kana: chunk.reading) ?? (chunk.reading.allSatisfy(\.isASCII) ? chunk.reading : nil)) : chunk.reading
            guard let reading, !reading.isEmpty else {
                dropped += chunk.shown.count
                continue
            }
            typed.append(reading + chunk.trailing)
            shown.append(chunk.shown)
        }
        return typed.isEmpty ? nil : Result(typed: typed.joined(separator: " "), chunks: shown, dropped: dropped)
    }

    /// Kana for a Japanese word: the word itself if it is kana, otherwise its
    /// reading turned back into kana. Latin words and numbers stay as they are.
    private static func kanaReading(_ surface: String, latin: String) -> String? {
        if let override = readingOverrides[surface] { return override }
        if surface.allSatisfy(Romaji.isKana) { return surface }
        if surface.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return surface.lowercased() }
        let cleaned = latin.lowercased().replacingOccurrences(of: "'", with: "")
        guard !cleaned.isEmpty,
              let kana = (cleaned as NSString).applyingTransform(.latinToHiragana, reverse: false),
              kana.allSatisfy(Romaji.isKana) else { return nil }
        return kana
    }

    /// Toneless pinyin with v for ü, syllables joined (zhongwen, lv).
    private static func pinyin(_ surface: String, latin: String) -> String? {
        if surface.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return surface.lowercased() }
        // Work on base letters and accent marks separately, so only u with an
        // umlaut (ü, ǜ, ...) becomes v and tone marks are simply dropped.
        var letters = ""
        var previousWasU = false
        for scalar in latin.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value == 0x308, previousWasU {  // combining diaeresis on u
                letters.removeLast()
                letters += "v"
                previousWasU = false
            } else if scalar.properties.generalCategory == .nonspacingMark {
                continue
            } else {
                letters.unicodeScalars.append(scalar)
                previousWasU = scalar == "u"
            }
        }
        let joined = letters.filter { $0.isLetter }
        return !joined.isEmpty && joined.allSatisfy({ $0.isASCII }) ? joined : nil
    }
}

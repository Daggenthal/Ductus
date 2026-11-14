import Carbon.HIToolbox
import DuctusEngine
import Foundation

/// Every keyboard layout installed with macOS, enabled or not, so Ductus can
/// type and show one inside its own windows without the user switching input
/// sources (Settings › Keyboard in Ductus).
@MainActor
enum LayoutCatalog {
    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        /// The layout's language, if Ductus has it.
        let language: PracticeLanguage?
        /// The language code macOS gives the layout ("fr", "ru"), for grouping.
        let languageCode: String?

        /// Dvorak, Colemak, Workman and their variants: layouts people learn to type faster.
        var isAlternative: Bool {
            let lower = name.lowercased() + " " + id.lowercased()
            return ["dvorak", "colemak", "workman"].contains { lower.contains($0) }
        }
    }

    static let all: [Entry] = {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        var seen = Set<String>()
        return sources.compactMap { source -> Entry? in
            guard let id = string(source, kTISPropertyInputSourceID), seen.insert(id).inserted,
                  let name = string(source, kTISPropertyLocalizedName) else { return nil }
            let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
                .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] } ?? []
            return Entry(id: id, name: name, language: languages.first.flatMap(PracticeLanguage.init(code:)),
                         languageCode: languages.first)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    /// Layouts the user added in System Settings › Keyboard › Input Sources
    /// (read each time, since they can change while Ductus runs).
    static var enabled: [Entry] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        let ids = Set(sources.compactMap { string($0, kTISPropertyInputSourceID) })
        return all.filter { ids.contains($0.id) }
    }

    /// Dvorak, Colemak and Workman layouts installed with macOS.
    static var alternatives: [Entry] { all.filter(\.isAlternative) }

    /// Every layout grouped by its language's name in `locale`, groups sorted by
    /// name; layouts without a language go last under "Other".
    static func groupedByLanguage(locale: Locale) -> [(name: String, layouts: [Entry])] {
        let other = String(localized: "Other", bundle: .ui)
        let groups = Dictionary(grouping: all) { entry -> String in
            guard let code = entry.languageCode, let name = locale.localizedString(forLanguageCode: code) else { return other }
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return groups.map { ($0.key, $0.value) }.sorted { a, b in
            if (a.name == other) != (b.name == other) { return b.name == other }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Layouts written for `language`.
    static func layouts(for language: PracticeLanguage) -> [Entry] {
        all.filter { $0.language == language }
    }

    /// The layout Ductus picks when the Mac's own layout cannot type `language`:
    /// one that matches the keys printed on most keyboards sold for it, or that
    /// keeps a QWERTY feel (Devanagari QWERTY for Hindi learners).
    static func preferred(for language: PracticeLanguage) -> Entry? {
        let ids: [PracticeLanguage: String] = [
            .hindi: "com.apple.keylayout.Devanagari-QWERTY",
            .arabic: "com.apple.keylayout.ArabicPC",
            .persian: "com.apple.keylayout.Persian-ISIRI2901",
            .hebrew: "com.apple.keylayout.Hebrew",
            .russian: "com.apple.keylayout.RussianWin",
            .ukrainian: "com.apple.keylayout.Ukrainian-PC",
            .greek: "com.apple.keylayout.Greek",
            .turkish: "com.apple.keylayout.Turkish-QWERTY-PC",
            .polish: "com.apple.keylayout.PolishPro",
            .czech: "com.apple.keylayout.Czech-QWERTY",
            .hungarian: "com.apple.keylayout.Hungarian-QWERTY",
        ]
        if let id = ids[language], let entry = all.first(where: { $0.id == id }) { return entry }
        return layouts(for: language).first
    }

    private static var commonLetters: [PracticeLanguage: [Character]] = [:]

    /// Whether `layout` can type the language's 20 most common letters (accents
    /// through dead keys count). Korean is typed on Ductus's own 2-Set map, so any layout works.
    static func canType(_ language: PracticeLanguage, on layout: KeyboardLayout?) -> Bool {
        guard language != .korean, let layout else { return true }
        if commonLetters[language] == nil {
            commonLetters[language] = (try? WordList.bundled(language)).map { Array($0.letterFrequencyOrder().prefix(20)) } ?? []
        }
        return commonLetters[language]!.allSatisfy(layout.typeableLetters.contains)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }
}

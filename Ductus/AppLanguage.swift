import AppKit
import Foundation
import Observation
import SwiftUI

/// The language of Ductus's own windows (not the practice language).
///
/// It switches live: every window reads `LanguageState` through `LocalizedRoot`,
/// and text made in code uses `Bundle.ui`. The choice is also saved as the app's
/// `AppleLanguages`, which macOS reads at launch for the menu bar, so the menus
/// follow on the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en", french = "fr", spanish = "es", german = "de", italian = "it"
    case portuguese = "pt-BR", dutch = "nl", turkish = "tr", polish = "pl", czech = "cs", hungarian = "hu"
    case greek = "el", russian = "ru", ukrainian = "uk", hebrew = "he", arabic = "ar", persian = "fa", hindi = "hi"
    case japanese = "ja", chinese = "zh-Hans", korean = "ko"

    var id: String { rawValue }

    /// Each language's name in itself, so people can find their own.
    var nativeName: String {
        switch self {
        case .system: String(localized: "System", bundle: .ui)
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português (Brasil)"
        case .dutch: "Nederlands"
        case .turkish: "Türkçe"
        case .polish: "Polski"
        case .czech: "Čeština"
        case .hungarian: "Magyar"
        case .greek: "Ελληνικά"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .hebrew: "עברית"
        case .arabic: "العربية"
        case .persian: "فارسی"
        case .hindi: "हिन्दी"
        case .japanese: "日本語"
        case .chinese: "简体中文"
        case .korean: "한국어"
        }
    }

    /// The language code actually used: the choice, or for System the best match
    /// between macOS's preferred languages and the ones Ductus has.
    var resolvedCode: String {
        if self != .system { return rawValue }
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferred).first ?? "en"  // not UI
    }
}

@MainActor
@Observable
final class LanguageState {
    static let shared = LanguageState()
    private static let key = "appLanguage"

    private(set) var language: AppLanguage
    /// The locale every window uses for its text, dates and numbers.
    private(set) var locale: Locale
    /// Changed since launch: the menu bar still shows the language Ductus opened with.
    private(set) var changedThisSession = false

    private init() {
        let saved = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
        language = saved
        locale = Locale(identifier: saved.resolvedCode)
        Bundle.setUI(code: saved.resolvedCode)
    }

    func set(_ language: AppLanguage) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.key)
        // For the menu bar, which macOS builds once at launch.
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        let code = language.resolvedCode
        Bundle.setUI(code: code)
        locale = Locale(identifier: code)
        changedThisSession = true
    }
}

extension Bundle {
    nonisolated(unsafe) private static var uiBundle: Bundle = .main

    /// The strings for the chosen app language. Text made in code looks up here,
    /// so it follows a language change without a relaunch.
    static var ui: Bundle { uiBundle }

    static func setUI(code: String) {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            uiBundle = bundle
        } else {
            uiBundle = .main
        }
    }
}

/// Wraps a window's content so it redraws in the chosen language as soon as it changes.
/// Views that build text in code (`String(localized:bundle: .ui)`) also read
/// `LanguageState.shared.locale` in their body, so they redraw too.
struct LocalizedRoot<Content: View>: View {
    @ViewBuilder let content: Content
    private let language = LanguageState.shared

    var body: some View {
        content
            .environment(\.locale, language.locale)
            // Arabic mirrors the whole window, as macOS apps do.
            .environment(\.layoutDirection, Locale.Language(identifier: language.locale.identifier).characterDirection == .rightToLeft
                ? .rightToLeft : .leftToRight)
    }
}

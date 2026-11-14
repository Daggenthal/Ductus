import AppKit
import Foundation

/// The language of Ductus's own menus and settings (not the practice language).
/// By default Ductus follows macOS; a choice here sets the app's `AppleLanguages`,
/// which macOS reads at launch, so it takes effect after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en", french = "fr", spanish = "es", german = "de", italian = "it"
    case portuguese = "pt-BR", dutch = "nl", japanese = "ja", chinese = "zh-Hans", korean = "ko"

    var id: String { rawValue }

    /// Each language's name in itself, so people can find their own.
    var nativeName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português (Brasil)"
        case .dutch: "Nederlands"
        case .japanese: "日本語"
        case .chinese: "简体中文"
        case .korean: "한국어"
        }
    }

    /// The choice saved for this app, or `.system` when Ductus follows macOS.
    static var current: AppLanguage {
        guard let languages = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: first) ?? .system
    }

    static func set(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Opens a fresh copy of Ductus and quits this one, so the new language shows.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

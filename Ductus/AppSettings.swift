import DuctusEngine
import DuctusLog
import Foundation

extension SettingsKey {
    static let targetWPM = "targetWPM"
    /// Percent, e.g. 95.
    static let targetAccuracy = "targetAccuracy"
    static let mistakeMode = "mistakeMode"
    static let textScale = "textScale"
    static let fadeMastered = "fadeMasteredKeys"
    static let capitals = "textCapitals"
    static let punctuation = "textPunctuation"
    static let sentenceDrills = "sentenceDrills"
    static let systemWideHighlighting = "systemWideHighlighting"
    /// Minutes per day, 0 = off.
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let keySounds = "keySounds"
    static let mistakeSound = "mistakeSound"
    static let soundVolume = "soundVolume"
    static let warmUp = "warmUpDrill"
    /// Letters whose Command shortcuts glow, e.g. "zxcv".
    static let shortcutKeys = "shortcutGlowKeys"
    static let defaultShortcutKeys = "zxcv"
    /// "auto", or a `KeyboardGeometry.Shape` raw value.
    static let keyboardShape = "keyboardShape"
    /// "auto" (from the layout), or a `PracticeLanguage` raw value.
    static let practiceLanguage = "practiceLanguage"
    /// Hidden debug mode (Settings, hold Option): full logging plus a log file.
    static let debugMode = "debugMode"
    /// Tint on-screen keys by the finger that presses them.
    static let fingerZones = "fingerZones"

    static func registerPracticeDefaults() {
        UserDefaults.standard.register(defaults: [
            targetWPM: 35.0,
            targetAccuracy: 95.0,
            mistakeMode: MistakeMode.stop.rawValue,
            textScale: 1.0,
            fadeMastered: true,
            capitals: false,
            punctuation: false,
            sentenceDrills: false,
            systemWideHighlighting: false,
            dailyGoalMinutes: 0,
            keySounds: false,
            mistakeSound: false,
            soundVolume: 0.5,
            warmUp: true,
            shortcutKeys: defaultShortcutKeys,
            keyboardShape: "auto",
            practiceLanguage: "auto",
            debugMode: false,
            fingerZones: false,
        ])
    }
}

/// Typed read access to practice-related settings.
enum PracticeSettings {
    private static var defaults: UserDefaults { .standard }

    static var progression: ProgressionConfig {
        ProgressionConfig(
            targetWPM: defaults.double(forKey: SettingsKey.targetWPM),
            targetAccuracy: defaults.double(forKey: SettingsKey.targetAccuracy) / 100
        )
    }

    static var mistakeMode: MistakeMode {
        MistakeMode(rawValue: defaults.string(forKey: SettingsKey.mistakeMode) ?? "") ?? .stop
    }

    static var textStyle: TextStyle {
        TextStyle(
            capitals: defaults.bool(forKey: SettingsKey.capitals),
            punctuation: defaults.bool(forKey: SettingsKey.punctuation)
        )
    }

    /// The setting's language, or the layout's own language when on Automatic.
    /// Layouts in a language without a word list (and unknown ones) use English.
    @MainActor
    static func language(for layout: KeyboardLayout?) -> PracticeLanguage {
        if let chosen = PracticeLanguage(rawValue: defaults.string(forKey: SettingsKey.practiceLanguage) ?? "") {
            return chosen
        }
        return detectedLanguage(for: layout)
    }

    static func detectedLanguage(for layout: KeyboardLayout?) -> PracticeLanguage {
        guard let layout else { return .english }
        // An active input method (Japanese, Chinese) wins over its layout's language.
        return layout.inputMethodLanguages.lazy.compactMap(PracticeLanguage.init(code:)).first
            ?? layout.languages.lazy.compactMap(PracticeLanguage.init(code:)).first
            ?? .english
    }

    static var warmUp: Bool { defaults.bool(forKey: SettingsKey.warmUp) }

    static var sentenceDrills: Bool { defaults.bool(forKey: SettingsKey.sentenceDrills) }

    static var dailyGoalMinutes: Int { defaults.integer(forKey: SettingsKey.dailyGoalMinutes) }
}

/// Debug mode: `DUCTUS_DEBUG=1` or the hidden Settings toggle. Logs everything
/// (never keystrokes) to the terminal and to a plain-text file in the app's
/// Library/Logs folder.
enum DebugMode {
    static var logFileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Ductus.log")
    }

    static func apply() {
        let on = Log.debugFromEnvironment || UserDefaults.standard.bool(forKey: SettingsKey.debugMode)
        guard on != Log.isDebug || (on && Log.logFile == nil) || (!on && Log.logFile != nil) else { return }
        Log.isDebug = on
        Log.logFile = on ? logFileURL : nil
        Log.info(on ? "Debug mode on, logging to \(logFileURL.path)" : "Debug mode off")
    }
}

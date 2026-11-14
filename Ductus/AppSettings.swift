import DuctusEngine
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

    static var sentenceDrills: Bool { defaults.bool(forKey: SettingsKey.sentenceDrills) }

    static var dailyGoalMinutes: Int { defaults.integer(forKey: SettingsKey.dailyGoalMinutes) }
}

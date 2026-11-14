import DuctusEngine
import Foundation
import SwiftData

/// Saved progress for one keyboard layout. Progress is kept per layout so
/// learning Dvorak and trying Colemak never mix.
@Model
final class LayoutProfile {
    @Attribute(.unique) var layoutID: String
    var layoutName: String
    var createdAt: Date
    var updatedAt: Date

    /// The engine's per-key and per-bigram stats (`StatsTracker`, JSON). Stored as
    /// one value because its internals (smoothed averages) are never queried.
    /// Everything the history page queries has its own model below.
    var statsData: Data
    /// Full unlock order as a string, e.g. "aoeuidhtnsrlwm...".
    var unlockOrder: String
    var unlockedCount: Int

    @Relationship(deleteRule: .cascade, inverse: \DrillEntry.profile)
    var drills: [DrillEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \KeyDayEntry.profile)
    var keyDays: [KeyDayEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \UnlockEntry.profile)
    var unlocks: [UnlockEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \RaceEntry.profile)
    var races: [RaceEntry] = []

    init(layoutID: String, layoutName: String, statsData: Data, unlockOrder: String, unlockedCount: Int) {
        self.layoutID = layoutID
        self.layoutName = layoutName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.statsData = statsData
        self.unlockOrder = unlockOrder
        self.unlockedCount = unlockedCount
    }
}

/// One finished drill.
@Model
final class DrillEntry {
    var date: Date
    var characters: Int
    var duration: TimeInterval
    var activeTime: TimeInterval
    var wpm: Double?
    var accuracy: Double
    var focusKey: String?
    var unlockedCount: Int
    var profile: LayoutProfile?
    /// Empty for a practice drill, "text" for a finished part of a Text-tab text.
    var source: String = ""

    static let textSource = "text"

    init(_ record: DrillRecord) {
        date = record.date
        characters = record.characters
        duration = record.duration
        activeTime = record.activeTime
        wpm = record.wpm
        accuracy = record.accuracy
        focusKey = record.focusKey
        unlockedCount = record.unlockedCount
    }

    var record: DrillRecord {
        DrillRecord(date: date, characters: characters, duration: duration, activeTime: activeTime,
                    wpm: wpm, accuracy: accuracy, focusKey: focusKey, unlockedCount: unlockedCount)
    }
}

/// A key's speed and accuracy at the end of a day. Powers the per-key trend chart.
@Model
final class KeyDayEntry {
    /// Start of the day.
    var day: Date
    var letter: String
    var wpm: Double?
    var accuracy: Double?
    var attempts: Int
    var profile: LayoutProfile?

    init(day: Date, letter: String, wpm: Double?, accuracy: Double?, attempts: Int) {
        self.day = day
        self.letter = letter
        self.wpm = wpm
        self.accuracy = accuracy
        self.attempts = attempts
    }
}

/// When a letter unlocked.
@Model
final class UnlockEntry {
    var letter: String
    var date: Date
    var profile: LayoutProfile?

    init(letter: String, date: Date) {
        self.letter = letter
        self.date = date
    }
}

/// One finished race.
@Model
final class RaceEntry {
    var date: Date
    var wordCount: Int
    var characters: Int
    var duration: TimeInterval
    var wpm: Double
    var accuracy: Double
    /// `false` if the race used only unlocked letters.
    var allLetters: Bool
    /// The keys that cost the most, worst first, e.g. "rlc".
    var worstKeys: String
    /// Race length in seconds. 0 for older word-count races.
    var timeLimit: Int = 0
    /// `RaceTextMode` raw value. Empty for older races (use `allLetters`).
    var textMode: String = ""
    var profile: LayoutProfile?

    var mode: RaceTextMode {
        RaceTextMode(rawValue: textMode) ?? (allLetters ? .allLetters : .unlocked)
    }

    init(date: Date, wordCount: Int, characters: Int, duration: TimeInterval, wpm: Double,
         accuracy: Double, allLetters: Bool, worstKeys: String, timeLimit: Int, textMode: String) {
        self.date = date
        self.wordCount = wordCount
        self.characters = characters
        self.duration = duration
        self.wpm = wpm
        self.accuracy = accuracy
        self.allLetters = allLetters
        self.worstKeys = worstKeys
        self.timeLimit = timeLimit
        self.textMode = textMode
    }
}

/// Text the user pasted in to practice on (an article, a chapter, some code).
/// Not tied to a layout. Stored only on this Mac.
@Model
final class SavedText {
    var title: String
    /// Already cleaned for typing (see `CustomText.clean`).
    var body: String
    /// Typed with Return at line ends (code, poems).
    var keepLineBreaks: Bool
    /// Index of the part to type next.
    var part: Int = 0
    var created: Date
    var lastOpened: Date
    /// "japanese", "chinese" or "korean" for text typed as romaji, pinyin or
    /// 2-Set jamo; empty for Latin text.
    var language: String = ""
    /// For those: the original text of each typed word, joined by `SavedText.separator`.
    var native: String = ""

    static let separator = "\u{1F}"

    var practiceLanguage: PracticeLanguage? { PracticeLanguage(rawValue: language) }
    var nativeChunks: [String] { native.isEmpty ? [] : native.components(separatedBy: Self.separator) }

    init(title: String, body: String, keepLineBreaks: Bool) {
        self.title = title
        self.body = body
        self.keepLineBreaks = keepLineBreaks
        created = Date()
        lastOpened = Date()
    }
}

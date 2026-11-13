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

import Foundation

/// One finished drill, as stored in history.
public struct DrillRecord: Sendable, Equatable, Codable {
    public var date: Date
    public var characters: Int
    /// First key to last key, in seconds.
    public var duration: TimeInterval
    /// Typing time with long pauses capped. Used for "practice time".
    public var activeTime: TimeInterval
    public var wpm: Double?
    public var accuracy: Double
    public var focusKey: String?
    public var unlockedCount: Int

    public init(
        date: Date, characters: Int, duration: TimeInterval, activeTime: TimeInterval,
        wpm: Double?, accuracy: Double, focusKey: String?, unlockedCount: Int
    ) {
        self.date = date
        self.characters = characters
        self.duration = duration
        self.activeTime = activeTime
        self.wpm = wpm
        self.accuracy = accuracy
        self.focusKey = focusKey
        self.unlockedCount = unlockedCount
    }
}

public struct HistoryTotals: Sendable, Equatable {
    public var drills = 0
    public var characters = 0
    public var practiceTime: TimeInterval = 0
    public var daysPracticed = 0
    /// Consecutive days with practice, ending today (or yesterday if not yet today).
    public var currentStreak = 0
    public var bestWPM: Double?

    public init() {}
}

/// Averages for one calendar day.
public struct DailySummary: Sendable, Equatable {
    /// Start of the day.
    public var day: Date
    public var drills: Int
    public var practiceTime: TimeInterval
    /// Weighted by characters, so long drills count more than short ones.
    public var wpm: Double?
    public var accuracy: Double
}

/// History math. Pure functions over drill records so they are easy to test.
public enum HistoryMath {
    public static func totals(_ drills: [DrillRecord], now: Date = Date(), calendar: Calendar = .current) -> HistoryTotals {
        var totals = HistoryTotals()
        totals.drills = drills.count
        totals.characters = drills.reduce(0) { $0 + $1.characters }
        totals.practiceTime = drills.reduce(0) { $0 + $1.activeTime }
        totals.bestWPM = drills.compactMap(\.wpm).max()

        let days = Set(drills.map { calendar.startOfDay(for: $0.date) })
        totals.daysPracticed = days.count

        var day = calendar.startOfDay(for: now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        while days.contains(day) {
            totals.currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return totals
    }

    /// One entry per day with practice, oldest first.
    public static func daily(_ drills: [DrillRecord], calendar: Calendar = .current) -> [DailySummary] {
        let grouped = Dictionary(grouping: drills) { calendar.startOfDay(for: $0.date) }
        return grouped.map { day, drills in
            let timed = drills.filter { $0.wpm != nil }
            let timedChars = timed.reduce(0) { $0 + $1.characters }
            let wpm = timedChars > 0
                ? timed.reduce(0) { $0 + $1.wpm! * Double($1.characters) } / Double(timedChars)
                : nil
            let chars = drills.reduce(0) { $0 + $1.characters }
            let accuracy = chars > 0
                ? drills.reduce(0) { $0 + $1.accuracy * Double($1.characters) } / Double(chars)
                : 0
            return DailySummary(
                day: day, drills: drills.count,
                practiceTime: drills.reduce(0) { $0 + $1.activeTime },
                wpm: wpm, accuracy: accuracy
            )
        }
        .sorted { $0.day < $1.day }
    }
}

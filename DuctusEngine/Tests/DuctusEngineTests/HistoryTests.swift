import Foundation
import Testing
@testable import DuctusEngine

@Suite struct PersistenceTests {
    @Test func statsRoundTrip() throws {
        var session = TypingSession(text: "the then")
        for (i, c) in "thx".enumerated() { session.type(c, at: Double(i) * 0.2) }
        for (i, c) in "e then".enumerated() { session.type(c, at: 1 + Double(i) * 0.2) }
        var stats = StatsTracker()
        stats.record(session.keystrokes)

        let data = try JSONEncoder().encode(stats)
        let restored = try JSONDecoder().decode(StatsTracker.self, from: data)
        #expect(restored == stats)
        #expect(restored.stats(for: Bigram("t", "h"))?.hits == 2)
    }

    @Test func restoredStatsKeepLearning() throws {
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.4))
        var restored = try JSONDecoder().decode(StatsTracker.self, from: JSONEncoder().encode(stats))
        restored.record(Keystroke(expected: "a", typed: "a", timestamp: 1, latency: 0.2))
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 1, latency: 0.2))
        #expect(restored == stats)
    }

    @Test func curriculumRestoresExactly() {
        let curriculum = Curriculum(order: Array("aoeuidhtns"), unlockedCount: 7)
        #expect(String(curriculum.unlocked) == "aoeuidh")
        #expect(Curriculum(order: Array("abc"), unlockedCount: 99).unlockedCount == 3)
    }

    @Test func trainerRestoreKeepsState() throws {
        let words = try WordList.bundledEnglish()
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.3))
        let curriculum = Curriculum(order: Array("aoeuidhtnsrl"), unlockedCount: 11)
        let trainer = Trainer(wordList: words, stats: stats, curriculum: curriculum)
        #expect(trainer.curriculum.unlockedCount == 11)
        #expect(trainer.stats == stats)
    }
}

@Suite struct HistoryMathTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func drill(_ day: Int, wpm: Double?, accuracy: Double = 1, chars: Int = 50, active: TimeInterval = 30) -> DrillRecord {
        DrillRecord(date: date(day), characters: chars, duration: active, activeTime: active,
                    wpm: wpm, accuracy: accuracy, focusKey: "a", unlockedCount: 10)
    }

    @Test func emptyHistory() {
        let totals = HistoryMath.totals([], now: date(13), calendar: calendar)
        #expect(totals == HistoryTotals())
        #expect(HistoryMath.daily([], calendar: calendar).isEmpty)
    }

    @Test func totalsAddUp() {
        let drills = [drill(10, wpm: 20), drill(12, wpm: 30, chars: 70), drill(13, wpm: 25)]
        let totals = HistoryMath.totals(drills, now: date(13), calendar: calendar)
        #expect(totals.drills == 3)
        #expect(totals.characters == 170)
        #expect(totals.practiceTime == 90)
        #expect(totals.daysPracticed == 3)
        #expect(totals.bestWPM == 30)
    }

    @Test func streakEndsTodayOrYesterday() {
        let drills = [drill(9, wpm: 20), drill(11, wpm: 20), drill(12, wpm: 20)]
        // Practiced the 11th and 12th, not yet on the 13th: streak still counts.
        #expect(HistoryMath.totals(drills, now: date(13), calendar: calendar).currentStreak == 2)
        #expect(HistoryMath.totals(drills, now: date(12), calendar: calendar).currentStreak == 2)
        // Missed a full day: streak is broken.
        #expect(HistoryMath.totals(drills, now: date(14), calendar: calendar).currentStreak == 0)
    }

    @Test func dailyAveragesWeightByCharacters() throws {
        let drills = [
            drill(12, wpm: 20, accuracy: 0.9, chars: 100),
            drill(12, wpm: 40, accuracy: 1.0, chars: 300),
            drill(12, wpm: nil, accuracy: 0.5, chars: 1),
            drill(13, wpm: 50),
        ]
        let daily = HistoryMath.daily(drills, calendar: calendar)
        #expect(daily.count == 2)
        #expect(daily[0].day == calendar.startOfDay(for: date(12)))
        #expect(daily[0].drills == 3)
        #expect(abs(try #require(daily[0].wpm) - 35) < 1e-9)  // (20*100 + 40*300) / 400
        #expect(abs(daily[0].accuracy - (90 + 300 + 0.5) / 401) < 1e-9)
        #expect(daily[1].wpm == 50)
    }
}

@Suite struct RankingTests {
    @Test func activeDurationCapsPauses() {
        var session = TypingSession(text: "abc")
        session.type("a", at: 0)
        session.type("b", at: 0.5)
        session.type("c", at: 60.5)  // walked away for a minute
        #expect(session.activeDuration(pauseThreshold: 2) == 2.5)
    }

    @Test func rankedKeysWeakestFirst() throws {
        let words = WordList([("tea", 10), ("eat", 5)])
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "t", typed: "t", timestamp: 0, latency: 0.1))
        stats.record(Keystroke(expected: "e", typed: "e", timestamp: 0, latency: 0.9))
        let trainer = Trainer(wordList: words, stats: stats, curriculum: Curriculum(order: Array("tea"), unlockedCount: 3))
        let ranked = trainer.rankedKeys()
        #expect(ranked.map(\.key) == ["e", "t"])  // "a" has no attempts, so it is left out
    }

    @Test func rankedBigramsNeedEnoughAttempts() {
        let words = WordList([("tea", 10)])
        var stats = StatsTracker()
        for i in 0..<10 {
            stats.record(Keystroke(expected: "e", typed: "e", previousExpected: "t", timestamp: Double(i), latency: 0.8))
        }
        stats.record(Keystroke(expected: "a", typed: "a", previousExpected: "e", timestamp: 20, latency: 0.9))
        let trainer = Trainer(wordList: words, stats: stats, curriculum: Curriculum(order: Array("tea"), unlockedCount: 3))
        #expect(trainer.rankedBigrams(minAttempts: 10).map(\.bigram) == [Bigram("t", "e")])
    }
}

import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// A race against your own best: type a passage of common words as fast and
/// accurately as you can.
@MainActor
@Observable
final class RaceModel {
    struct Result {
        let wpm: Double
        let accuracy: Double
        let duration: TimeInterval
        let characters: Int
        let errors: Int
        let worstKeys: [RaceKeyResult]
        let isNewBest: Bool
    }

    static let wordCountOptions = [15, 30, 60]

    private(set) var session: TypingSession?
    private(set) var lastKeyWrong = false
    private(set) var result: Result?
    /// Wall-clock time of the first key, for the live clock and the ghost.
    private(set) var startedAt: Date?
    private(set) var raceID = 0

    var wordCount: Int {
        didSet {
            UserDefaults.standard.set(wordCount, forKey: "raceWordCount")
            newRace()
        }
    }
    /// `false`: only letters unlocked in practice.
    var allLetters: Bool {
        didSet {
            UserDefaults.standard.set(allLetters, forKey: "raceAllLetters")
            newRace()
        }
    }

    @ObservationIgnored private let practice: PracticeModel
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    init(practice: PracticeModel) {
        self.practice = practice
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["raceWordCount": 30, "raceAllLetters": true])
        wordCount = defaults.integer(forKey: "raceWordCount")
        allLetters = defaults.bool(forKey: "raceAllLetters")
    }

    var isRunning: Bool { startedAt != nil && result == nil }

    /// Best WPM for races with the current letter setting, before this race.
    var bestWPM: Double? {
        practice.raceHistory.filter { $0.allLetters == allLetters }.map(\.wpm).max()
    }

    func newRace() {
        guard let words = practice.words else { return }
        let allowed = allLetters ? nil : practice.unlockedLetters
        guard let text = Race.text(from: words, wordCount: wordCount, allowed: allowed, using: &rng) else {
            Log.error("No words available for a race")
            return
        }
        session = TypingSession(text: text)
        lastKeyWrong = false
        result = nil
        startedAt = nil
        raceID += 1
    }

    /// Feeds one typed character. Returns `true` if the race consumed it.
    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        if session == nil { newRace() }
        guard result == nil else { return true }  // finished: wait for a new race
        guard let keystroke = session?.type(character, keyCode: keyCode, at: time) else { return true }

        if startedAt == nil { startedAt = Date() }
        lastKeyWrong = !keystroke.isCorrect
        practice.recordExternal(keystroke)

        if let session, session.isComplete { finish(session) }
        return true
    }

    private func finish(_ session: TypingSession) {
        guard let summary = session.summary else { return }
        let previousBest = bestWPM
        let wpm = summary.wpm ?? 0
        let worst = Race.worstKeys(Race.keyResults(session.keystrokes))
        let errors = session.keystrokes.filter { !$0.isCorrect }.count

        result = Result(
            wpm: wpm, accuracy: summary.accuracy, duration: summary.duration,
            characters: summary.characters, errors: errors, worstKeys: worst,
            isNewBest: previousBest.map { wpm > $0 } ?? true
        )
        practice.saveRace(RaceEntry(
            date: Date(), wordCount: wordCount, characters: summary.characters, duration: summary.duration,
            wpm: wpm, accuracy: summary.accuracy, allLetters: allLetters,
            worstKeys: String(worst.map(\.key))
        ))
        Log.success(String(format: "Race done: %.0f WPM, %.0f%%", wpm, summary.accuracy * 100))
    }
}

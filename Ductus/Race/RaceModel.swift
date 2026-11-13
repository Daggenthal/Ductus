import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// A timed race against your own best: type common words for 1, 2 or 5
/// minutes as fast and accurately as you can.
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

    /// Race lengths in seconds.
    static let timeLimitOptions = [60, 120, 300]

    private(set) var session: TypingSession?
    private(set) var lastKeyWrong = false
    private(set) var result: Result?
    /// Wall-clock time of the first key. The countdown starts here.
    private(set) var startedAt: Date?
    private(set) var raceID = 0

    /// Seconds.
    var timeLimit: Int {
        didSet {
            UserDefaults.standard.set(timeLimit, forKey: "raceTimeLimit")
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
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// Words added at a time. More are appended before the text runs out.
    private static let chunkWords = 40

    init(practice: PracticeModel) {
        self.practice = practice
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["raceTimeLimit": 60, "raceAllLetters": true])
        let saved = defaults.integer(forKey: "raceTimeLimit")
        timeLimit = Self.timeLimitOptions.contains(saved) ? saved : 60
        allLetters = defaults.bool(forKey: "raceAllLetters")
    }

    var isRunning: Bool { startedAt != nil && result == nil }

    /// Best WPM for this length and letter setting.
    var bestWPM: Double? {
        practice.raceHistory
            .filter { $0.timeLimit == timeLimit && $0.allLetters == allLetters }
            .map(\.wpm).max()
    }

    func newRace() {
        timer?.cancel()
        timer = nil
        guard let text = moreWords() else {
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

        if startedAt == nil { start() }
        lastKeyWrong = !keystroke.isCorrect
        practice.recordExternal(keystroke)

        // Keep a comfortable amount of text ahead of the cursor.
        if let session, session.text.count - session.position < 120, let more = moreWords() {
            self.session?.extend(with: " " + more)
        }
        return true
    }

    private func start() {
        startedAt = Date()
        let id = raceID
        let limit = timeLimit
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, self.raceID == id else { return }
            self.finish()
        }
    }

    private func moreWords() -> String? {
        guard let words = practice.words else { return nil }
        let allowed = allLetters ? nil : practice.unlockedLetters
        return Race.text(from: words, wordCount: Self.chunkWords, allowed: allowed, using: &rng)
    }

    private func finish() {
        guard let session, result == nil else { return }
        let previousBest = bestWPM
        let minutes = Double(timeLimit) / 60
        let characters = session.position
        let wpm = Double(characters) / 5 / minutes
        let accuracy = session.liveAccuracy ?? 0
        let worst = Race.worstKeys(Race.keyResults(session.keystrokes))
        let errors = session.keystrokes.filter { !$0.isCorrect }.count

        result = Result(
            wpm: wpm, accuracy: accuracy, duration: TimeInterval(timeLimit),
            characters: characters, errors: errors, worstKeys: worst,
            isNewBest: previousBest.map { wpm > $0 } ?? true
        )
        practice.saveRace(RaceEntry(
            date: Date(), wordCount: 0, characters: characters, duration: TimeInterval(timeLimit),
            wpm: wpm, accuracy: accuracy, allLetters: allLetters,
            worstKeys: String(worst.map(\.key)), timeLimit: timeLimit
        ))
        Log.success(String(format: "Race done: %.0f WPM, %.0f%% over %ds", wpm, accuracy * 100, timeLimit))
    }
}

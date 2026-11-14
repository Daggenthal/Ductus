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
    static let timeLimitOptions = [30, 60, 180, 300]

    /// "30s", "1 min", "3 min".
    static func lengthLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60) min"
    }

    private(set) var session: TypingSession?
    /// Japanese or Chinese text for romaji or pinyin races.
    private(set) var gloss: Gloss?
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
    var textMode: RaceTextMode {
        didSet {
            UserDefaults.standard.set(textMode.rawValue, forKey: "raceTextMode")
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
        // Older versions stored a true/false "all letters" choice.
        textMode = RaceTextMode(rawValue: defaults.string(forKey: "raceTextMode") ?? "")
            ?? (defaults.bool(forKey: "raceAllLetters") ? .allLetters : .unlocked)
    }

    var isRunning: Bool { startedAt != nil && result == nil }

    /// Best WPM for this length and text mode.
    var bestWPM: Double? {
        practice.raceHistory
            .filter { $0.timeLimit == timeLimit && $0.mode == textMode }
            .map(\.wpm).max()
    }

    func newRace() {
        timer?.cancel()
        timer = nil
        gloss = practice.language.hasTypedForm ? Gloss() : nil
        guard let text = moreWords(offset: 0) else {
            Log.error("No words available for a race")
            return
        }
        session = TypingSession(text: text, mistakeMode: PracticeSettings.mistakeMode)
        lastKeyWrong = false
        result = nil
        startedAt = nil
        raceID += 1
    }

    /// Feeds one typed character. Returns `true` if the race consumed it.
    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard character != "\n" else { return false }  // race text has no line breaks
        if session == nil { newRace() }
        guard result == nil else { return true }  // finished: wait for a new race
        guard let keystroke = session?.type(character, keyCode: keyCode, at: time) else { return true }

        if startedAt == nil { start() }
        lastKeyWrong = !keystroke.isCorrect && session?.mistakeMode == .stop
        practice.onKeystroke?(keystroke.isCorrect)
        practice.recordExternal(keystroke)

        // Keep a comfortable amount of text ahead of the cursor.
        if let session, session.text.count - session.position < 120,
           let more = moreWords(offset: session.text.count + 1) {
            self.session?.extend(with: " " + more)
        }
        return true
    }

    /// Backspace (or Option-Backspace for a word) in "fix with Backspace" mode.
    func backspace(word: Bool) -> Bool {
        guard result == nil, session?.mistakeMode == .backspace else { return false }
        if word { session?.backspaceWord() } else { session?.backspace() }
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

    /// More race text. `offset` is where it will start in the race text, for the gloss.
    private func moreWords(offset: Int) -> String? {
        let words: String?
        switch textMode {
        case .sentences:
            // Real sentences already have their own capitals and punctuation.
            guard let sentences = practice.sentences else { return nil }
            // Only sentences this layout can type (e.g. no "ñ" without a way to make it).
            let pool = practice.typeableLetters.map { sentences.sentences(using: $0) } ?? sentences.entries
            guard let picked = SentenceList.pickEntries(from: pool, minCharacters: 250, using: &rng) else { return nil }
            gloss?.append(Gloss(sentences: picked), offset: offset)
            return picked.map(\.text).joined(separator: " ")
        case .unlocked:
            // Same word picking as practice: unlocked letters, weighted toward
            // weak keys. Picked fresh for each chunk, so it follows the stats live.
            words = practice.practiceStyleWords(atLeast: Self.chunkWords)
        case .allLetters:
            guard let list = practice.words else { return nil }
            words = Race.text(from: list, wordCount: Self.chunkWords, allowed: practice.typeableLetters, using: &rng)
        }
        let text = words.map {
            TextDecorator.decorate($0, style: PracticeSettings.textStyle, language: practice.language, using: &rng)
        }
        if let text, gloss != nil {
            let native = practice.nativeForms
            gloss?.append(text: text, offset: offset, lookup: { native[$0] ?? native[String($0.filter(\.isLetter))] })
        }
        return text
    }

    private func finish() {
        guard let session, result == nil else { return }
        let previousBest = bestWPM
        let minutes = Double(timeLimit) / 60
        let characters = session.correctCount
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
            wpm: wpm, accuracy: accuracy, allLetters: textMode != .unlocked,
            worstKeys: String(worst.map(\.key)), timeLimit: timeLimit, textMode: textMode.rawValue
        ))
        Log.success(String(format: "Race done: %.0f WPM, %.0f%% over %ds", wpm, accuracy * 100, timeLimit))
    }
}

/// What a race is made of.
enum RaceTextMode: String, CaseIterable, Identifiable {
    case allLetters = "all"
    case unlocked
    case sentences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allLetters: "All letters"
        case .unlocked: "Unlocked only"
        case .sentences: "Sentences"
        }
    }
}

import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// Runs practice: holds the trainer and the current drill, and feeds keystrokes in.
@MainActor
@Observable
final class PracticeModel {
    private(set) var trainer: Trainer?
    private(set) var session: TypingSession?
    private(set) var lastSummary: SessionSummary?
    /// The last key pressed was wrong (the cursor stays until it is right).
    private(set) var lastKeyWrong = false
    private(set) var unlockMessage: String?
    private(set) var loadError: String?
    private(set) var drillsCompleted = 0
    /// Changes with every new drill, so views can reset instead of animating across.
    private(set) var drillID = 0

    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    /// - Parameter startingKeys: Letters on the home row of the active layout.
    func start(startingKeys: [Character]) {
        do {
            let words = try WordList.bundledEnglish()
            let trainer = Trainer(wordList: words, startingKeys: startingKeys)
            self.trainer = trainer
            Log.success("Loaded \(words.entries.count) words. Starting keys: \(String(trainer.curriculum.unlocked))")
            nextDrill()
        } catch {
            loadError = "Could not load the word list: \(error)"
            Log.error(loadError!)
        }
    }

    /// Starts over with new starting keys, but only if nothing has been typed yet.
    /// Used when the user switches layouts right after launch.
    func restartIfUntouched(startingKeys: [Character]) {
        guard let trainer, trainer.stats.keys.isEmpty else { return }
        Log.info("Layout changed before practice started. Restarting with the new home row.")
        start(startingKeys: startingKeys)
    }

    func nextDrill() {
        guard let trainer else { return }
        guard let text = trainer.nextDrill(using: &rng) else {
            Log.error("No words can be typed with the unlocked letters")
            return
        }
        session = TypingSession(text: text)
        drillID += 1
        lastKeyWrong = false
        Log.debug("Drill (focus \(trainer.focusKey.map(String.init) ?? "-")): \(text)")
    }

    /// Feeds one typed character. Returns `true` if practice consumed it.
    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard trainer != nil, session != nil else { return false }
        guard let keystroke = session?.type(character, keyCode: keyCode, at: time) else { return true }

        lastKeyWrong = !keystroke.isCorrect
        if let unlocked = trainer?.record(keystroke) {
            unlockMessage = "New key unlocked: \(unlocked.uppercased())"
            Log.success("Unlocked \(unlocked)")
        }

        if session?.isComplete == true {
            lastSummary = session?.summary
            drillsCompleted += 1
            if let summary = lastSummary {
                Log.debug(String(format: "Drill done: %.0f WPM, %.0f%%", summary.wpm ?? 0, summary.accuracy * 100))
            }
            nextDrill()
        }
        return true
    }

    // MARK: - Display helpers

    var nextCharacter: Character? { session?.currentExpected }

    var unlockedLetters: Set<Character>? { trainer?.curriculum.unlockedSet }

    var focusKey: Character? { trainer?.focusKey }

    func stats(for key: Character) -> KeyStats? { trainer?.stats.stats(for: key) }
}

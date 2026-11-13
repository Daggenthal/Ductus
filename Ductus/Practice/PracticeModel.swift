import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// Runs practice: holds the trainer and the current drill, feeds keystrokes in,
/// and saves progress per keyboard layout.
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

    /// Saved progress for the current layout. `nil` until the first keystroke
    /// of a brand new layout, so trying a layout for a second does not leave
    /// an empty profile behind.
    private(set) var profile: LayoutProfile?
    private(set) var layoutID = "unknown"
    private(set) var layoutName = "Unknown layout"

    @ObservationIgnored private var store: ProgressStore?
    @ObservationIgnored private var wordList: WordList?
    @ObservationIgnored private var layout: KeyboardLayout?
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    var isSavingProgress: Bool { store?.isPersistent ?? false }

    // MARK: - Starting and switching

    /// Loads saved progress for `layout`, or starts fresh on its home row.
    func start(layout: KeyboardLayout?, store: ProgressStore) {
        self.store = store
        load(layout: layout)
    }

    /// Saves the current layout's progress and switches to the new layout's.
    func switchLayout(to layout: KeyboardLayout?) {
        guard (layout?.id ?? "unknown") != layoutID else { return }
        persist()
        Log.info("Layout changed to \(layout?.name ?? "unknown"). Switching progress.")
        load(layout: layout)
    }

    /// Deletes all saved progress for the current layout and starts over.
    func resetProgress() {
        if let profile {
            Log.warning("Resetting progress for \(layoutName) (\(profile.drills.count) drills)")
            store?.delete(profile)
        }
        profile = nil
        load(layout: layout, forceFresh: true)
    }

    private func load(layout: KeyboardLayout?, forceFresh: Bool = false) {
        self.layout = layout
        layoutID = layout?.id ?? "unknown"
        layoutName = layout?.name ?? "Unknown layout"
        lastSummary = nil
        unlockMessage = nil
        drillsCompleted = 0

        guard let words = loadWords() else { return }

        if !forceFresh, let saved = store?.profile(for: layoutID) {
            profile = saved
            do {
                let stats = try JSONDecoder().decode(StatsTracker.self, from: saved.statsData)
                let curriculum = Curriculum(order: Array(saved.unlockOrder), unlockedCount: saved.unlockedCount)
                trainer = Trainer(wordList: words, stats: stats, curriculum: curriculum)
                Log.success("Restored \(layoutName): \(saved.drills.count) drills, \(curriculum.unlockedCount) letters unlocked")
            } catch {
                // History is kept; only the live key stats start over.
                Log.error("Saved key stats for \(layoutName) could not be read, starting them fresh: \(error)")
                trainer = Trainer(wordList: words, startingKeys: layout?.homeRowLetters ?? [])
            }
        } else {
            profile = nil
            trainer = Trainer(wordList: words, startingKeys: layout?.homeRowLetters ?? [])
            Log.success("New progress for \(layoutName) (starting keys: \(String(trainer!.curriculum.unlocked)))")
        }
        nextDrill()
    }

    private func loadWords() -> WordList? {
        if let wordList { return wordList }
        do {
            let words = try WordList.bundledEnglish()
            wordList = words
            Log.success("Loaded \(words.entries.count) words")
            return words
        } catch {
            loadError = "Could not load the word list: \(error)"
            Log.error(loadError!)
            return nil
        }
    }

    // MARK: - Practice

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
            ensureProfile()?.unlocks.append(UnlockEntry(letter: String(unlocked), date: Date()))
        }

        if let session, session.isComplete {
            lastSummary = session.summary
            drillsCompleted += 1
            if let summary = lastSummary {
                recordDrill(summary, activeTime: session.activeDuration(pauseThreshold: trainer!.stats.config.pauseThreshold))
            }
            nextDrill()
        }
        return true
    }

    // MARK: - Shared with races

    var words: WordList? { wordList }

    /// Practice-style words for an "Unlocked only" race: unlocked letters,
    /// weighted toward weak keys and the focus key, same as practice drills.
    func practiceStyleWords(atLeast count: Int) -> String? {
        guard let trainer else { return nil }
        var words: [Substring] = []
        while words.count < count {
            guard let chunk = trainer.nextDrill(using: &rng) else { break }
            words += chunk.split(separator: " ")
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// Records a keystroke typed outside practice (in a race) into the same key
    /// stats, so practice targets what races expose. Unlocks can happen here too.
    func recordExternal(_ keystroke: Keystroke) {
        guard let unlocked = trainer?.record(keystroke) else { return }
        unlockMessage = "New key unlocked: \(unlocked.uppercased())"
        Log.success("Unlocked \(unlocked) during a race")
        ensureProfile()?.unlocks.append(UnlockEntry(letter: String(unlocked), date: Date()))
    }

    func saveRace(_ entry: RaceEntry) {
        guard let profile = ensureProfile() else { return }
        profile.races.append(entry)
        persist()
    }

    /// Races for the current layout, oldest first.
    var raceHistory: [RaceEntry] {
        (profile?.races ?? []).sorted { $0.date < $1.date }
    }

    // MARK: - Saving

    /// Writes the trainer's current state to the store. Called after each drill,
    /// on layout switch and on quit.
    func persist() {
        guard let trainer, let profile = ensureProfile() else { return }
        do {
            profile.statsData = try JSONEncoder().encode(trainer.stats)
        } catch {
            Log.error("Could not encode key stats: \(error)")
        }
        profile.unlockOrder = String(trainer.curriculum.order)
        profile.unlockedCount = trainer.curriculum.unlockedCount
        profile.updatedAt = Date()
        store?.save()
    }

    /// The current profile, created on first use. `nil` if nothing has been typed yet.
    @discardableResult
    private func ensureProfile() -> LayoutProfile? {
        if let profile { return profile }
        guard let trainer, let store, !trainer.stats.keys.isEmpty else { return nil }
        let new = LayoutProfile(
            layoutID: layoutID, layoutName: layoutName, statsData: Data(),
            unlockOrder: String(trainer.curriculum.order), unlockedCount: trainer.curriculum.unlockedCount
        )
        store.insert(new)
        profile = new
        return new
    }

    private func recordDrill(_ summary: SessionSummary, activeTime: TimeInterval) {
        guard let trainer, let profile = ensureProfile() else { return }
        let now = Date()
        profile.drills.append(DrillEntry(DrillRecord(
            date: now, characters: summary.characters, duration: summary.duration, activeTime: activeTime,
            wpm: summary.wpm, accuracy: summary.accuracy,
            focusKey: trainer.focusKey.map(String.init), unlockedCount: trainer.curriculum.unlockedCount
        )))

        // Update today's snapshot of every practiced key (one row per key per day).
        let today = Calendar.current.startOfDay(for: now)
        var todays = Dictionary(
            profile.keyDays.filter { $0.day == today }.map { ($0.letter, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for key in trainer.curriculum.unlocked {
            guard let stats = trainer.stats.stats(for: key) else { continue }
            let letter = String(key)
            if let entry = todays[letter] {
                entry.wpm = stats.wpm
                entry.accuracy = stats.accuracy.value
                entry.attempts = stats.attempts
            } else {
                let entry = KeyDayEntry(day: today, letter: letter, wpm: stats.wpm,
                                        accuracy: stats.accuracy.value, attempts: stats.attempts)
                profile.keyDays.append(entry)
                todays[letter] = entry
            }
        }

        persist()
        Log.debug(String(format: "Drill done: %.0f WPM, %.0f%%", summary.wpm ?? 0, summary.accuracy * 100))
    }

    // MARK: - Display helpers

    var nextCharacter: Character? { session?.currentExpected }

    var unlockedLetters: Set<Character>? { trainer?.curriculum.unlockedSet }

    var focusKey: Character? { trainer?.focusKey }

    func stats(for key: Character) -> KeyStats? { trainer?.stats.stats(for: key) }

    /// Finished drills for the current layout, oldest first.
    var drillHistory: [DrillRecord] {
        (profile?.drills ?? []).map(\.record).sorted { $0.date < $1.date }
    }
}

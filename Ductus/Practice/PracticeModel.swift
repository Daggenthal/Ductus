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
    /// The last key pressed was wrong and the cursor is waiting (stop-on-mistake mode).
    private(set) var lastKeyWrong = false
    /// Short banner: a new key unlocked, or the daily goal reached.
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
    /// Language of the word list and sentences: from the layout, or the setting.
    private(set) var language = PracticeLanguage.english
    @ObservationIgnored private var wordLists: [PracticeLanguage: WordList] = [:]
    @ObservationIgnored private var sentenceLists: [PracticeLanguage: SentenceList] = [:]
    private var wordList: WordList? { wordLists[language] }
    /// Called after each keystroke with whether it was correct (for sounds).
    @ObservationIgnored var onKeystroke: ((Bool) -> Void)?
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
        let language = PracticeSettings.language(for: layout)
        guard Self.profileID(layout: layout, language: language) != layoutID else { return }
        persist()
        Log.info("Layout changed to \(layout?.name ?? "unknown"). Switching progress.")
        load(layout: layout)
    }

    /// Progress is saved per layout and language. English keeps the plain
    /// layout ID, so progress saved before languages existed still loads.
    static func profileID(layout: KeyboardLayout?, language: PracticeLanguage) -> String {
        let id = layout?.id ?? "unknown"
        return language == .english ? id : "\(id)|\(language.rawValue)"
    }

    /// Letters the active layout can type, or `nil` if unknown. Korean is
    /// typed as 2-Set jamo whatever the layout.
    var typeableLetters: Set<Character>? {
        language == .korean ? Dubeolsik.allJamo : layout?.typeableLetters
    }

    /// Where unlocking starts: the home row of the layout, or of 2-Set for Korean.
    private var startingKeys: [Character] {
        language == .korean ? Dubeolsik.homeRow : layout?.homeRowLetters ?? []
    }

    /// Whether the active layout can type `character` (directly or with a dead key).
    /// `true` when the layout is unknown, so nothing is thrown away by mistake.
    func canType(_ character: Character) -> Bool {
        if language == .korean, Dubeolsik.allJamo.contains(character) { return true }
        guard let layout else { return true }
        return character == " " || character == "\n" || layout.strokes[character] != nil
    }

    /// Typing time under this long between keys counts as active.
    var pauseThreshold: TimeInterval { trainer?.stats.config.pauseThreshold ?? 2 }

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
        lastPracticeKeystroke = nil
        language = PracticeSettings.language(for: layout)
        layoutID = Self.profileID(layout: layout, language: language)
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
                trainer = Trainer(wordList: words, stats: stats, curriculum: curriculum,
                                  progression: PracticeSettings.progression)
                Log.success("Restored \(layoutName): \(saved.drills.count) drills, \(curriculum.unlockedCount) letters unlocked")
            } catch {
                // History is kept; only the live key stats start over.
                Log.error("Saved key stats for \(layoutName) could not be read, starting them fresh: \(error)")
                trainer = Trainer(wordList: words, startingKeys: startingKeys,
                                  progression: PracticeSettings.progression, typeable: typeableLetters)
            }
        } else {
            profile = nil
            trainer = Trainer(wordList: words, startingKeys: startingKeys,
                              progression: PracticeSettings.progression, typeable: typeableLetters)
            Log.success("New \(language.nativeName) progress for \(layoutName) (starting keys: \(String(trainer!.curriculum.unlocked)))")
        }
        nextDrill()
    }

    private func loadWords() -> WordList? {
        if let wordList { return wordList }
        do {
            let words = try WordList.bundled(language)
            wordLists[language] = words
            loadError = nil
            Log.success("Loaded \(words.entries.count) \(language.nativeName) words")
            return words
        } catch {
            loadError = String(localized: "Could not load the word list: \(error.localizedDescription)", bundle: .ui)
            Log.error(loadError!)
            return nil
        }
    }

    private func loadSentences() -> SentenceList? {
        if let list = sentenceLists[language] { return list }
        do {
            let list = try SentenceList.bundled(language)
            sentenceLists[language] = list
            return list
        } catch {
            Log.error("Could not load sentences: \(error)")
            return nil
        }
    }

    // MARK: - Settings

    /// Applies changed settings. Targets take effect at once; text options from the next drill.
    func applySettings() {
        if trainer != nil, PracticeSettings.language(for: layout) != language {
            persist()
            Log.info("Practice language changed. Switching progress.")
            load(layout: layout)
            return
        }
        let progression = PracticeSettings.progression
        if let trainer, trainer.scorer.config != progression {
            self.trainer?.scorer = WeaknessScorer(config: progression)
            Log.info("Unlock targets: \(Int(progression.targetWPM)) WPM, \(Int(progression.targetAccuracy * 100))%")
            // A lower target can unlock letters right away.
            if let unlocked = self.trainer?.advanceIfReady() { noteUnlock(unlocked) }
        }
    }

    // MARK: - Practice

    /// Sentences made only of unlocked letters. Sentence drills need enough of these.
    var sentencePool: [SentenceList.Entry] {
        guard let unlocked = trainer?.curriculum.unlockedSet else { return [] }
        return loadSentences()?.sentences(using: unlocked) ?? []
    }

    static let minSentencePool = 30

    var sentenceDrillsAvailable: Bool { sentencePool.count >= Self.minSentencePool }

    /// Whether the current drill is a warm-up (mastered keys only).
    private(set) var isWarmUp = false
    /// After this long without practice, the next drill is a warm-up again.
    static let warmUpBreak: TimeInterval = 10 * 60
    @ObservationIgnored private var lastPracticeKeystroke: Date?

    /// Warm up on the first drill of a session: after launch, a layout switch,
    /// or a break of 10 minutes or more.
    private var wantsWarmUp: Bool {
        guard PracticeSettings.warmUp else { return false }
        guard let last = lastPracticeKeystroke else { return true }
        return Date().timeIntervalSince(last) >= Self.warmUpBreak
    }

    /// Called when Ductus comes back to the front. After a break, swaps an
    /// untouched drill for a warm-up.
    func warmUpIfReturning() {
        guard !isWarmUp, wantsWarmUp, lastPracticeKeystroke != nil,
              let session, session.keystrokes.isEmpty else { return }
        nextDrill()
    }

    /// Japanese or Chinese text for the current drill's romaji or pinyin.
    private(set) var gloss: Gloss?

    /// Native forms of the current language's romanized words ("nihongo" → "日本語").
    var nativeForms: [String: String] {
        guard language.hasTypedForm else { return [:] }
        if let cached = nativeFormsCache[language] { return cached }
        let forms = wordList?.nativeForms ?? [:]
        nativeFormsCache[language] = forms
        return forms
    }
    @ObservationIgnored private var nativeFormsCache: [PracticeLanguage: [String: String]] = [:]

    /// A gloss for word text in a romanized language, `nil` otherwise.
    func wordGloss(_ text: String) -> Gloss? {
        language.hasTypedForm ? Gloss(text: text, native: nativeForms) : nil
    }

    func nextDrill() {
        guard let trainer else { return }
        if wantsWarmUp, let words = trainer.warmUpDrill(using: &rng) {
            let text = TextDecorator.decorate(words, style: PracticeSettings.textStyle, language: language, using: &rng)
            gloss = wordGloss(text)
            session = TypingSession(text: text, mistakeMode: PracticeSettings.mistakeMode)
            isWarmUp = true
            drillID += 1
            lastKeyWrong = false
            Log.debug("Warm-up drill: \(text)")
            return
        }
        isWarmUp = false
        guard let text = makeDrillText(trainer) else {
            Log.error("No words can be typed with the unlocked letters")
            return
        }
        session = TypingSession(text: text, mistakeMode: PracticeSettings.mistakeMode)
        drillID += 1
        lastKeyWrong = false
        Log.debug("Drill (focus \(trainer.focusKey.map(String.init) ?? "-")): \(text)")
    }

    /// Sentence drill (if on and enough sentences fit), otherwise a word drill
    /// with optional capitals and punctuation.
    private func makeDrillText(_ trainer: Trainer) -> String? {
        if PracticeSettings.sentenceDrills {
            let pool = sentencePool
            if pool.count >= Self.minSentencePool,
               let picked = SentenceList.pickEntries(from: pool, minCharacters: 90,
                                                     weakness: trainer.drillRequest().keyWeakness, using: &rng) {
                gloss = language.hasTypedForm ? Gloss(sentences: picked) : nil
                return picked.map(\.text).joined(separator: " ")
            }
        }
        guard let words = trainer.nextDrill(using: &rng) else { return nil }
        let text = TextDecorator.decorate(words, style: PracticeSettings.textStyle, language: language, using: &rng)
        gloss = wordGloss(text)
        return text
    }

    /// Feeds one typed character. Returns `true` if practice consumed it.
    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard trainer != nil, session != nil, character != "\n" else { return false }
        guard let keystroke = session?.type(character, keyCode: keyCode, at: time) else { return true }
        lastPracticeKeystroke = Date()

        lastKeyWrong = !keystroke.isCorrect && session?.mistakeMode == .stop
        onKeystroke?(keystroke.isCorrect)
        if let unlocked = trainer?.record(keystroke) { noteUnlock(unlocked) }

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

    /// Backspace (or Option-Backspace for a word) in "fix with Backspace" mode.
    func backspace(word: Bool) -> Bool {
        guard session?.mistakeMode == .backspace else { return false }
        if word { session?.backspaceWord() } else { session?.backspace() }
        return true
    }

    private func noteUnlock(_ letter: Character) {
        unlockMessage = String(localized: "New key unlocked: \(letter.uppercased())", bundle: .ui)
        Log.success("Unlocked \(letter)")
        ensureProfile()?.unlocks.append(UnlockEntry(letter: String(letter), date: Date()))
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
        lastPracticeKeystroke = Date()  // a race counts as warmed up
        guard let unlocked = trainer?.record(keystroke) else { return }
        noteUnlock(unlocked)
    }

    func saveRace(_ entry: RaceEntry) {
        let before = todayPracticeTime
        guard let profile = ensureProfile() else { return }
        profile.races.append(entry)
        persist()
        checkDailyGoal(before: before)
    }

    var sentences: SentenceList? { loadSentences() }

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

    /// A finished part of a custom text: shows in History and counts toward the daily goal.
    func recordTextPart(_ summary: SessionSummary, activeTime: TimeInterval) {
        recordDrill(summary, activeTime: activeTime, custom: true)
    }

    private func recordDrill(_ summary: SessionSummary, activeTime: TimeInterval, custom: Bool = false) {
        let before = todayPracticeTime
        defer { checkDailyGoal(before: before) }
        guard let trainer, let profile = ensureProfile() else { return }
        let now = Date()
        let entry = DrillEntry(DrillRecord(
            date: now, characters: summary.characters, duration: summary.duration, activeTime: activeTime,
            wpm: summary.wpm, accuracy: summary.accuracy,
            focusKey: custom ? nil : trainer.focusKey.map(String.init),
            unlockedCount: trainer.curriculum.unlockedCount
        ))
        if custom { entry.source = DrillEntry.textSource }
        profile.drills.append(entry)

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

    // MARK: - Daily goal

    /// Practice time today: drill typing time plus race lengths.
    var todayPracticeTime: TimeInterval {
        let calendar = Calendar.current
        let drills = (profile?.drills ?? []).filter { calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.activeTime }
        let races = (profile?.races ?? []).filter { calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.duration }
        return drills + races
    }

    private func checkDailyGoal(before: TimeInterval) {
        let goal = TimeInterval(PracticeSettings.dailyGoalMinutes * 60)
        guard goal > 0, before < goal, todayPracticeTime >= goal else { return }
        unlockMessage = String(localized: "Daily goal reached 🎉", bundle: .ui)
        Log.success("Daily goal reached")
    }

    // MARK: - Export

    /// Drills, Text-tab parts and races as CSV, one row each, oldest first.
    func historyCSV() -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["type,date,length,characters,wpm,accuracy,focus_or_worst_keys"]
        for drill in drillHistory {
            rows.append([
                "drill", iso.string(from: drill.date), String(format: "%.1f", drill.duration),
                "\(drill.characters)", drill.wpm.map { String(format: "%.1f", $0) } ?? "",
                String(format: "%.3f", drill.accuracy), drill.focusKey ?? "",
            ].joined(separator: ","))
        }
        for part in textHistory {
            rows.append([
                "text", iso.string(from: part.date), String(format: "%.1f", part.duration),
                "\(part.characters)", part.wpm.map { String(format: "%.1f", $0) } ?? "",
                String(format: "%.3f", part.accuracy), "",
            ].joined(separator: ","))
        }
        for race in raceHistory {
            rows.append([
                "race", iso.string(from: race.date), String(format: "%.0f", race.duration),
                "\(race.characters)", String(format: "%.1f", race.wpm),
                String(format: "%.3f", race.accuracy), race.worstKeys,
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Display helpers

    /// Letters that meet the unlock targets (for fading keyboard labels).
    var masteredLetters: Set<Character> {
        guard let trainer else { return [] }
        return Set(trainer.stats.keys.compactMap { key, stats in
            key.isLetter && trainer.scorer.meetsTarget(stats) ? key : nil
        })
    }

    var nextCharacter: Character? { session?.currentExpected }

    var unlockedLetters: Set<Character>? { trainer?.curriculum.unlockedSet }

    var focusKey: Character? { trainer?.focusKey }

    func stats(for key: Character) -> KeyStats? { trainer?.stats.stats(for: key) }

    /// Finished drills for the current layout, oldest first.
    /// Practice drills, oldest first. Text-tab parts are kept apart (`textHistory`).
    var drillHistory: [DrillRecord] {
        (profile?.drills ?? []).filter { $0.source != DrillEntry.textSource }
            .map(\.record).sorted { $0.date < $1.date }
    }

    /// Finished parts of Text-tab texts, oldest first.
    var textHistory: [DrillRecord] {
        (profile?.drills ?? []).filter { $0.source == DrillEntry.textSource }
            .map(\.record).sorted { $0.date < $1.date }
    }
}

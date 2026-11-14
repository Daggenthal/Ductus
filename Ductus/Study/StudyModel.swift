import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// The Study tab: learning a word set (HSK 1, ...) with spaced repetition.
/// Each card is typed; how it was typed (misses, speed, asking for the answer)
/// is the grade, so there are no buttons to press.
@MainActor
@Observable
final class StudyModel {
    private let store: ProgressStore
    private let practice: PracticeModel
    private let scheduler = FSRS()

    private(set) var wordSet: StudySet?
    private(set) var progress = StudyProgress()
    private var record: StudyRecord?

    private(set) var session: StudySession?
    /// The answer being typed for the current card.
    private(set) var typing: TypingSession?
    private(set) var lastKeyWrong = false
    /// The answer was shown (Return), so this card counts as forgotten.
    private(set) var revealed = false
    /// Changes with every card, so the views start fresh.
    private(set) var cardID = 0
    /// The last finished card and its grade, shown under the next one.
    private(set) var lastResult: (word: StudyWord, grade: StudyGrade?)?
    /// Grades given this session, for the summary.
    private(set) var tally: [StudyGrade: Int] = [:]
    private(set) var isFinished = false
    private(set) var practicingKnown = false
    private(set) var loadError: String?

    // MARK: Grammar

    private(set) var grammar: GrammarSet?
    /// Points practiced, with when (by point ID), for the current level.
    private(set) var practicedPoints: [String: Date] = [:]
    private var grammarRecord: StudyRecord?
    /// The point being practiced and which of its examples is up.
    private(set) var grammarPoint: GrammarSet.Point?
    private(set) var exampleIndex = 0
    private(set) var grammarDone = false

    private var cardStart: TimeInterval = 0
    private var misses = 0

    init(store: ProgressStore, practice: PracticeModel) {
        self.store = store
        self.practice = practice
        load()
    }

    var setID: String {
        UserDefaults.standard.string(forKey: SettingsKey.studySet) ?? "hsk1"  // not UI
    }

    var newPerDay: Int { max(1, UserDefaults.standard.integer(forKey: SettingsKey.studyNewPerDay)) }

    /// Loads the chosen set and its saved progress (after the setting changes too).
    func load() {
        endSession()
        do {
            wordSet = try StudySet.bundled(setID)
            loadError = nil
        } catch {
            Log.error("Could not load study set \(setID): \(error)")
            loadError = String(localized: "This word set could not be loaded.", bundle: .ui)
            wordSet = nil
            return
        }
        record = store.studyRecord(for: setID)
        if let record, let saved = try? JSONDecoder().decode(StudyProgress.self, from: record.progressData) {
            progress = saved
        } else {
            progress = StudyProgress()
        }
        Log.success("Study \(setID): \(progress.cards.count) words learned")
        grammar = GrammarSet.bundled(setID)
        grammarRecord = store.studyRecord(for: "grammar-\(setID)")
        practicedPoints = grammarRecord.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0.progressData) } ?? [:]
        endGrammar()
    }

    func select(setID: String) {
        guard setID != self.setID else { return }
        UserDefaults.standard.set(setID, forKey: SettingsKey.studySet)
        load()
    }

    // MARK: - Overview

    var plan: StudyPlan {
        guard let set = wordSet else { return StudyPlan(reviews: [], new: []) }
        return progress.plan(for: set, now: .now, newPerDay: newPerDay)
    }

    var learnedCount: Int { wordSet.map { progress.learned(in: $0).count } ?? 0 }
    var knownCount: Int { wordSet.map { progress.known(in: $0).count } ?? 0 }
    var totalCount: Int { wordSet?.words.count ?? 0 }
    var startedToday: Int { progress.startedToday(now: .now) }

    // MARK: - Session

    /// Today's reviews and new words.
    func start() {
        begin(plan, knownOnly: false)
    }

    /// More new words after today's are done.
    func keepGoing() {
        guard let set = wordSet else { return }
        let more = progress.plan(for: set, now: .now, newPerDay: 0, extraNew: newPerDay)
        if session == nil || isFinished {
            begin(more, knownOnly: false)
        } else {
            session?.append(more)
        }
    }

    /// Every known word, shuffled, from memory.
    func practiceKnown() {
        guard let set = wordSet else { return }
        begin(StudyPlan(reviews: progress.known(in: set).shuffled(), new: []), knownOnly: true)
    }

    func endSession() {
        session = nil
        typing = nil
        isFinished = false
        lastResult = nil
        tally = [:]
    }

    private func begin(_ plan: StudyPlan, knownOnly: Bool) {
        guard !plan.isEmpty else { return }
        endGrammar()
        session = StudySession(plan: plan)
        practicingKnown = knownOnly
        isFinished = false
        lastResult = nil
        tally = [:]
        nextCard()
    }

    var step: StudySession.Step? { session?.current }

    private func nextCard() {
        guard let step = session?.current else {
            typing = nil
            isFinished = true
            persist()
            return
        }
        typing = TypingSession(text: step.word.typed, mistakeMode: .stop)
        misses = 0
        revealed = false
        lastKeyWrong = false
        cardStart = ProcessInfo.processInfo.systemUptime
        cardID += 1
    }

    /// "I Know This Word": the word goes to the back (next review in about six
    /// months) and leaves this session. Undo it from History with Study Again.
    func markKnown() {
        guard let step = session?.current else { return }
        progress.markKnown(step.word, now: .now)
        session?.skipCurrentWord()
        lastResult = (step.word, nil)
        persist()
        nextCard()
    }

    /// Study Again (History): forgets a word, so it comes back as a new word.
    func reset(_ word: StudyWord) {
        progress.reset(word)
        persist()
    }

    /// Return on an unfinished card shows the answer; the card is then graded Again.
    func reveal() {
        guard typing != nil, !revealed else { return }
        revealed = true
    }

    // MARK: - Grammar practice

    /// Types through a point's example sentences, one after another.
    func practice(_ point: GrammarSet.Point) {
        guard !point.examples.isEmpty else { return }
        grammarPoint = point
        exampleIndex = 0
        grammarDone = false
        startExample()
    }

    func endGrammar() {
        grammarPoint = nil
        grammarDone = false
        if session == nil { typing = nil }
    }

    var currentExample: GrammarSet.Example? {
        guard let point = grammarPoint, !grammarDone, exampleIndex < point.examples.count else { return nil }
        return point.examples[exampleIndex]
    }

    private func startExample() {
        guard let example = currentExample else { return }
        typing = TypingSession(text: example.typed, mistakeMode: .stop)
        lastKeyWrong = false
        revealed = false
        cardID += 1
    }

    private func finishExample() {
        guard let point = grammarPoint else { return }
        exampleIndex += 1
        if exampleIndex >= point.examples.count {
            grammarDone = true
            typing = nil
            practicedPoints[point.id] = .now
            saveGrammar()
        } else {
            startExample()
        }
    }

    private func saveGrammar() {
        guard let data = try? JSONEncoder().encode(practicedPoints) else { return }
        if let grammarRecord {
            grammarRecord.progressData = data
            grammarRecord.updated = .now
        } else {
            let new = StudyRecord(setID: "grammar-\(setID)", progressData: data)
            store.insert(new)
            grammarRecord = new
        }
        store.save()
    }

    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard let typing else { return false }
        if grammarPoint != nil, session == nil {
            if character == "\n" { return true }
            guard let keystroke = self.typing?.type(character, keyCode: keyCode, at: time) else { return true }
            lastKeyWrong = !keystroke.isCorrect
            practice.onKeystroke?(keystroke.isCorrect)
            if practice.language == wordSet?.language { practice.recordExternal(keystroke) }
            if self.typing?.isComplete == true { finishExample() }
            return true
        }
        if character == "\n" {
            reveal()
            return true
        }
        guard let keystroke = self.typing?.type(character, keyCode: keyCode, at: time) else { return true }
        lastKeyWrong = !keystroke.isCorrect
        if !keystroke.isCorrect { misses += 1 }
        practice.onKeystroke?(keystroke.isCorrect)
        // Pinyin keys are the letters of Chinese practice.
        if practice.language == wordSet?.language { practice.recordExternal(keystroke) }
        if self.typing?.isComplete == true {
            finishCard(keys: typing.text.count, finishedAt: time)
        }
        return true
    }

    func backspace(word: Bool) -> Bool { typing != nil }

    private func finishCard(keys: Int, finishedAt time: TimeInterval) {
        guard let step = session?.current else { return }
        let attempt = StudyAttempt(misses: misses, keys: keys, duration: max(0, time - cardStart), usedHint: revealed)
        let grade: StudyGrade
        if case .learn = step {
            grade = .good  // learning a new word is not graded; it comes back from memory soon
        } else {
            grade = StudyGrader.grade(attempt, secondsPerKey: secondsPerKey)
        }
        if let toRecord = session?.answer(grade) {
            progress.record(step.word, toRecord, scheduler: scheduler, now: .now)
            tally[toRecord, default: 0] += 1
            persist()
        }
        if case .recall = step { lastResult = (step.word, grade) } else { lastResult = (step.word, nil) }
        nextCard()
    }

    /// Your usual time per key from practice, so a fast answer is judged against your own speed.
    private var secondsPerKey: TimeInterval? {
        guard let stats = practice.trainer?.stats else { return nil }
        let latencies = stats.keys.values.compactMap(\.latencyMs)
        guard latencies.count >= 5 else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count) / 1000
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        if let record {
            record.progressData = data
            record.updated = .now
        } else {
            let new = StudyRecord(setID: setID, progressData: data)
            store.insert(new)
            record = new
        }
        store.save()
    }
}

extension StudySet {
    /// "HSK 1" ... "HSK 7-9".
    static func title(for id: String) -> String {
        guard id.hasPrefix("hsk"), let level = Int(id.dropFirst(3)) else { return id }  // not UI
        return level == 7 ? "HSK 7-9" : "HSK \(level)"  // not UI
    }
}

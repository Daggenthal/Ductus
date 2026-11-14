import Foundation

// Study: learning words (HSK and more) with spaced repetition, graded by how
// you type them. Plain values only, so it is unit-tested and stays portable.

/// A word to learn: shown as `native` (你好) with its `reading` (nǐ hǎo), typed as `typed` (nihao).
public struct StudyWord: Sendable, Hashable, Identifiable {
    public let native: String
    public let reading: String
    public let typed: String
    public let meaning: String
    public var id: String { native }

    public init(native: String, reading: String, typed: String, meaning: String) {
        self.native = native
        self.reading = reading
        self.typed = typed
        self.meaning = meaning
    }
}

/// A list of words to learn, most common first (HSK 1, HSK 2, ...).
public struct StudySet: Sendable, Identifiable {
    public let id: String
    public let language: PracticeLanguage
    public let words: [StudyWord]

    /// The bundled sets, in order.
    public static let catalog: [(id: String, language: PracticeLanguage)] = (1...7).map { ("hsk\($0)", .chinese) }

    /// Lines of `native <tab> reading <tab> typed <tab> meaning`; `#` lines are comments.
    public init(id: String, language: PracticeLanguage, tsv: String) {
        self.id = id
        self.language = language
        words = tsv.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 4, !columns[0].isEmpty, !columns[2].isEmpty else { return nil }
            return StudyWord(native: columns[0], reading: columns[1], typed: columns[2], meaning: columns[3])
        }
    }

    public static func bundled(_ id: String) throws -> StudySet {
        guard let entry = catalog.first(where: { $0.id == id }),
              let url = Bundle.module.url(forResource: "study-\(id)", withExtension: "tsv") else {
            throw EngineError.missingResource("study-\(id).tsv")
        }
        return StudySet(id: id, language: entry.language, tsv: try String(contentsOf: url, encoding: .utf8))
    }
}

// MARK: - Scheduling (FSRS)

public enum StudyGrade: Int, Codable, Sendable, CaseIterable {
    case again = 1, hard, good, easy
}

/// What Ductus remembers about one word.
public struct CardState: Codable, Sendable, Equatable {
    /// Days until the chance of remembering drops to 90%.
    public var stability: Double
    /// 1 (easy) to 10 (hard).
    public var difficulty: Double
    public var due: Date
    public var lastReview: Date
    public var reviews: Int
    /// Times the word was forgotten after being learned.
    public var lapses: Int
}

/// The FSRS scheduler (version 5, default parameters), the algorithm Anki uses
/// by default. Written from the published formulas:
/// https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
public struct FSRS: Sendable {
    public var weights: [Double]
    /// The chance of remembering a word when it comes back for review.
    public var desiredRetention: Double
    public var maximumInterval: Double

    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    public init(weights: [Double] = FSRS.defaultWeights, desiredRetention: Double = 0.9, maximumInterval: Double = 36500) {
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.maximumInterval = maximumInterval
    }

    /// Chance of remembering after `days` with this stability.
    public func retrievability(days: Double, stability: Double) -> Double {
        pow(1 + Self.factor * max(0, days) / stability, Self.decay)
    }

    /// Days until the next review: when retrievability falls to the desired retention.
    public func interval(stability: Double) -> Double {
        let days = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(maximumInterval, max(1, days.rounded()))
    }

    /// The first time a word is graded.
    public func first(_ grade: StudyGrade, now: Date) -> CardState {
        let stability = max(0.1, weights[grade.rawValue - 1])
        return CardState(stability: stability, difficulty: initialDifficulty(grade), due: due(now, stability),
                         lastReview: now, reviews: 1, lapses: 0)
    }

    /// Every later review.
    public func review(_ card: CardState, _ grade: StudyGrade, now: Date) -> CardState {
        let w = weights
        let g = Double(grade.rawValue)
        let days = now.timeIntervalSince(card.lastReview) / 86_400
        var stability: Double
        if days < 1 {
            // Seen again the same day.
            stability = card.stability * exp(w[17] * (g - 3 + w[18]))
        } else {
            let r = retrievability(days: days, stability: card.stability)
            if grade == .again {
                let forgotten = w[11] * pow(card.difficulty, -w[12]) * (pow(card.stability + 1, w[13]) - 1) * exp(w[14] * (1 - r))
                stability = min(forgotten, card.stability)
            } else {
                let hard = grade == .hard ? w[15] : 1
                let easy = grade == .easy ? w[16] : 1
                stability = card.stability * (exp(w[8]) * (11 - card.difficulty) * pow(card.stability, -w[9])
                    * (exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
            }
        }
        stability = max(0.1, stability)
        let change = -w[6] * (g - 3)
        let moved = card.difficulty + change * (10 - card.difficulty) / 9
        let difficulty = clamp(w[7] * initialDifficulty(.easy) + (1 - w[7]) * moved)
        return CardState(stability: stability, difficulty: difficulty, due: due(now, stability), lastReview: now,
                         reviews: card.reviews + 1, lapses: card.lapses + (grade == .again ? 1 : 0))
    }

    private func initialDifficulty(_ grade: StudyGrade) -> Double {
        clamp(weights[4] - exp(weights[5] * Double(grade.rawValue - 1)) + 1)
    }

    private func clamp(_ difficulty: Double) -> Double { min(10, max(1, difficulty)) }

    private func due(_ now: Date, _ stability: Double) -> Date {
        now.addingTimeInterval(interval(stability: stability) * 86_400)
    }
}

// MARK: - Grading from typing

/// One typed answer.
public struct StudyAttempt: Sendable, Equatable {
    /// Keys pressed wrong (Ductus keeps the cursor until the right key).
    public var misses: Int
    /// Keys in the answer.
    public var keys: Int
    /// From the card appearing to the last key, so time spent recalling counts.
    public var duration: TimeInterval
    /// Asked to see the answer.
    public var usedHint: Bool

    public init(misses: Int, keys: Int, duration: TimeInterval, usedHint: Bool = false) {
        self.misses = misses
        self.keys = keys
        self.duration = duration
        self.usedHint = usedHint
    }
}

/// Turns a typed answer into a grade, so there are no buttons to press: a
/// hint or many misses is Again, any miss or a slow recall is Hard, a clean
/// answer is Good, and a clean answer at your normal typing speed is Easy.
public enum StudyGrader {
    /// `secondsPerKey`: your usual time per key from practice (0.35 s, about 35 WPM, if unknown).
    public static func grade(_ attempt: StudyAttempt, secondsPerKey: TimeInterval? = nil) -> StudyGrade {
        let keys = max(1, attempt.keys)
        if attempt.usedHint || attempt.misses >= max(2, keys / 3) { return .again }
        if attempt.misses > 0 { return .hard }
        let perKey = secondsPerKey ?? 0.35
        if attempt.duration <= 1.0 + Double(keys) * perKey * 1.3 { return .easy }
        if attempt.duration <= 6.0 + Double(keys) * perKey * 2 { return .good }
        return .hard
    }
}

// MARK: - Progress and daily plan

/// Everything learned in one set. Stored as JSON by the app.
public struct StudyProgress: Codable, Sendable, Equatable {
    /// By word ID (its native text).
    public var cards: [String: CardState] = [:]
    /// New words started per day ("2026-11-14": 10), for the daily limit.
    public var startedPerDay: [String: Int] = [:]

    /// Stable for three weeks or more: the word is known.
    public static let knownStability = 21.0

    public init() {}

    public func isKnown(_ word: StudyWord) -> Bool {
        (cards[word.id]?.stability ?? 0) >= Self.knownStability
    }

    public func startedToday(now: Date, calendar: Calendar = .current) -> Int {
        startedPerDay[Self.day(now, calendar)] ?? 0
    }

    /// Today's work: words due for review (most overdue first), then new words
    /// in set order up to the daily limit. `extraNew` is for Keep Going.
    public func plan(for set: StudySet, now: Date, newPerDay: Int, extraNew: Int = 0,
                     calendar: Calendar = .current) -> StudyPlan {
        let reviews = set.words
            .filter { (cards[$0.id]?.due).map { $0 <= now } ?? false }
            .sorted { cards[$0.id]!.due < cards[$1.id]!.due }
        let allowance = max(0, newPerDay - startedToday(now: now, calendar: calendar)) + extraNew
        let new = Array(set.words.lazy.filter { cards[$0.id] == nil }.prefix(allowance))
        return StudyPlan(reviews: reviews, new: new)
    }

    /// Words already learned (graded at least once).
    public func learned(in set: StudySet) -> [StudyWord] { set.words.filter { cards[$0.id] != nil } }

    public func known(in set: StudySet) -> [StudyWord] { set.words.filter(isKnown) }

    /// Saves a grade. The first grade of a word starts it and counts toward today's new words.
    public mutating func record(_ word: StudyWord, _ grade: StudyGrade, scheduler: FSRS = FSRS(), now: Date,
                                calendar: Calendar = .current) {
        if let card = cards[word.id] {
            cards[word.id] = scheduler.review(card, grade, now: now)
        } else {
            cards[word.id] = scheduler.first(grade, now: now)
            startedPerDay[Self.day(now, calendar), default: 0] += 1
        }
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public struct StudyPlan: Sendable, Equatable {
    public var reviews: [StudyWord]
    public var new: [StudyWord]
    public var isEmpty: Bool { reviews.isEmpty && new.isEmpty }

    public init(reviews: [StudyWord], new: [StudyWord]) {
        self.reviews = reviews
        self.new = new
    }
}

// MARK: - A session

/// The order cards come up in. A new word is first typed with everything shown
/// (learn), then a few cards later from memory (recall). Reviews are recall
/// only. A missed recall comes back a few cards later until it is typed right;
/// only the first answer of each word is graded.
public struct StudySession: Sendable {
    public enum Step: Sendable, Equatable {
        case learn(StudyWord)
        case recall(StudyWord)

        public var word: StudyWord {
            switch self {
            case .learn(let word), .recall(let word): word
            }
        }
    }

    public private(set) var queue: [Step]
    public private(set) var completed = 0
    private var graded: Set<String> = []
    private let gap: Int

    public init(plan: StudyPlan, gap: Int = 3) {
        self.gap = gap
        var steps: [Step] = plan.reviews.map(Step.recall)
        // Learn a b c, then recall a once two more words are learned: La Lb Lc Ra Ld Rb ...
        var pending: [StudyWord] = []
        for word in plan.new {
            steps.append(.learn(word))
            pending.append(word)
            if pending.count > gap - 1 { steps.append(.recall(pending.removeFirst())) }
        }
        steps += pending.map(Step.recall)
        queue = steps
    }

    public var current: Step? { queue.first }
    public var remaining: Int { queue.count }
    public var isFinished: Bool { queue.isEmpty }

    /// Moves past the current card. Returns the grade to save, or nil when this
    /// answer is not graded (learn steps and repeats).
    public mutating func answer(_ grade: StudyGrade) -> StudyGrade? {
        guard let step = queue.first else { return nil }
        queue.removeFirst()
        completed += 1
        guard case .recall(let word) = step else { return nil }
        if grade == .again {
            queue.insert(.recall(word), at: min(gap, queue.count))
        }
        return graded.insert(word.id).inserted ? grade : nil
    }

    /// Adds more cards (Keep Going) after the current queue.
    public mutating func append(_ plan: StudyPlan) {
        queue += StudySession(plan: plan, gap: gap).queue
    }
}

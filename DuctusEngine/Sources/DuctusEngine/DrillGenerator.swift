import Foundation

public struct DrillConfig: Sendable, Equatable {
    public var wordCount: Int
    /// Share of words that should contain the focus key, in [0, 1].
    public var focusShare: Double
    /// The curriculum unlocks extra letters at the start until at least this many
    /// real words can be typed, so drills are not the same few words on repeat.
    public var minPoolSize: Int
    /// Most times one word may appear in a drill (when there are other words to use).
    public var maxRepeats: Int
    /// With fewer focus words than this, the focus share is scaled down so a
    /// rare key does not fill the drill with the same two or three words.
    public var fullFocusPoolSize: Int

    public init(
        wordCount: Int = 15, focusShare: Double = 0.6, minPoolSize: Int = 50,
        maxRepeats: Int = 2, fullFocusPoolSize: Int = 8
    ) {
        self.wordCount = wordCount
        self.focusShare = focusShare
        self.minPoolSize = minPoolSize
        self.maxRepeats = maxRepeats
        self.fullFocusPoolSize = fullFocusPoolSize
    }
}

/// What the next drill should practice. Built by `Trainer` from stats, or by hand in tests.
public struct DrillRequest: Sendable, Equatable {
    public var unlocked: Set<Character>
    public var focus: Character?
    /// 0 = fine, higher = weaker. Missing keys count as 0.
    public var keyWeakness: [Character: Double]
    public var bigramWeakness: [Bigram: Double]

    public init(
        unlocked: Set<Character>,
        focus: Character? = nil,
        keyWeakness: [Character: Double] = [:],
        bigramWeakness: [Bigram: Double] = [:]
    ) {
        self.unlocked = unlocked
        self.focus = focus
        self.keyWeakness = keyWeakness
        self.bigramWeakness = bigramWeakness
    }
}

/// Builds drill text from real words only. Words with weak keys and bigrams
/// are picked more often, and most words contain the focus key.
public struct DrillGenerator: Sendable {
    public let wordList: WordList
    public var config: DrillConfig

    public init(wordList: WordList, config: DrillConfig = DrillConfig()) {
        self.wordList = wordList
        self.config = config
    }

    /// Returns `nil` if no word in the list can be typed with the unlocked letters.
    public func generate<G: RandomNumberGenerator>(_ request: DrillRequest, using rng: inout G) -> String? {
        let pool = wordList.words(using: request.unlocked)
        guard !pool.isEmpty else { return nil }
        let focusPool = request.focus.map { focus in pool.filter { $0.letters.contains(focus) } } ?? []

        let focusShare = config.focusShare
            * min(1, Double(focusPool.count) / Double(max(1, config.fullFocusPoolSize)))

        var words: [String] = []
        var uses: [String: Int] = [:]
        for _ in 0..<config.wordCount {
            let wantFocus = !focusPool.isEmpty && Double.random(in: 0..<1, using: &rng) < focusShare
            // Skip words already used up. Focus words fall back to the whole pool,
            // and a tiny pool falls back to anything so the drill still fills.
            let previous = words.last
            let fresh = { (entries: [WordList.Entry]) in
                entries.filter { $0.word != previous && uses[$0.word, default: 0] < config.maxRepeats }
            }
            var source = wantFocus ? fresh(focusPool) : []
            if source.isEmpty { source = fresh(pool) }
            if source.isEmpty { source = pool }
            let word = pick(from: source, request: request, avoiding: previous, using: &rng)
            words.append(word)
            uses[word, default: 0] += 1
        }
        return words.joined(separator: " ")
    }

    /// How much a word is worth practicing: common words and words full of weak spots win.
    func score(_ entry: WordList.Entry, request: DrillRequest) -> Double {
        let letters = Array(entry.word.lowercased())
        let keyWeakness = letters.reduce(0) { $0 + (request.keyWeakness[$1] ?? 0) } / Double(letters.count)
        var bigramWeakness = 0.0
        if letters.count > 1 {
            for i in 1..<letters.count {
                bigramWeakness += request.bigramWeakness[Bigram(letters[i - 1], letters[i])] ?? 0
            }
            bigramWeakness /= Double(letters.count - 1)
        }
        // Log of frequency keeps rarer words in play instead of "the the the".
        return log(Double(entry.count) + 1) * (1 + keyWeakness + bigramWeakness)
    }

    /// Weighted pick that never repeats the previous word when there is a choice.
    private func pick<G: RandomNumberGenerator>(
        from source: [WordList.Entry],
        request: DrillRequest,
        avoiding previous: String?,
        using rng: inout G
    ) -> String {
        let others = source.filter { $0.word != previous }
        let choices = others.isEmpty ? source : others
        return choices.weightedRandomElement(using: &rng, weight: { score($0, request: request) })?.word
            ?? choices[0].word
    }
}

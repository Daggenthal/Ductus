/// Ties the engine together: record keystrokes, unlock keys, generate drills.
///
/// This is the main type the app talks to.
public struct Trainer: Sendable {
    public private(set) var stats: StatsTracker
    public private(set) var curriculum: Curriculum
    public let scorer: WeaknessScorer
    public var generator: DrillGenerator

    public init(
        wordList: WordList,
        startingKeys: [Character],
        progression: ProgressionConfig = ProgressionConfig(),
        engine: EngineConfig = EngineConfig(),
        drill: DrillConfig = DrillConfig()
    ) {
        stats = StatsTracker(config: engine)
        curriculum = Curriculum(startingKeys: startingKeys, frequencyOrder: wordList.letterFrequencyOrder())
        scorer = WeaknessScorer(config: progression)
        generator = DrillGenerator(wordList: wordList, config: drill)

        // Some home rows spell very few words (QWERTY: about 40). Add letters by
        // frequency until drills have enough real words to vary.
        curriculum.unlock { wordList.words(using: $0).count >= drill.minPoolSize }
    }

    /// Records one keystroke. Returns a newly unlocked letter, if this keystroke caused one.
    @discardableResult
    public mutating func record(_ keystroke: Keystroke) -> Character? {
        stats.record(keystroke)
        return curriculum.advance(stats: stats, scorer: scorer)
    }

    public var focusKey: Character? { curriculum.focusKey(stats: stats, scorer: scorer) }

    /// Weakness of `key` in [0, ...). 0 means at target. Useful for the HUD heatmap.
    public func weakness(of key: Character) -> Double { scorer.weakness(of: stats.stats(for: key)) }

    public func drillRequest() -> DrillRequest {
        let unlocked = curriculum.unlockedSet
        var keyWeakness: [Character: Double] = [:]
        for key in unlocked { keyWeakness[key] = weakness(of: key) }

        // Bigrams use a prior of 0: an unseen or barely-seen bigram should not
        // outrank one we know is slow.
        var bigramWeakness: [Bigram: Double] = [:]
        for (bigram, stats) in stats.bigrams
        where unlocked.contains(bigram.first) && unlocked.contains(bigram.second) {
            bigramWeakness[bigram] = scorer.weakness(of: stats, prior: 0)
        }

        return DrillRequest(
            unlocked: unlocked, focus: focusKey,
            keyWeakness: keyWeakness, bigramWeakness: bigramWeakness
        )
    }

    /// `nil` only if the word list has no words for the unlocked letters (e.g. an empty list).
    public func nextDrill<G: RandomNumberGenerator>(using rng: inout G) -> String? {
        generator.generate(drillRequest(), using: &rng)
    }

    public func nextDrill() -> String? {
        var rng = SystemRandomNumberGenerator()
        return nextDrill(using: &rng)
    }
}

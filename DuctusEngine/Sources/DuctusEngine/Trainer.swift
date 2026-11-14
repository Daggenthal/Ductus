/// Ties the engine together: record keystrokes, unlock keys, generate drills.
///
/// This is the main type the app talks to.
public struct Trainer: Sendable {
    public private(set) var stats: StatsTracker
    public private(set) var curriculum: Curriculum
    /// Targets for unlocking. Can be changed any time (Settings); stats are kept.
    public var scorer: WeaknessScorer
    public var generator: DrillGenerator

    public init(
        wordList: WordList,
        startingKeys: [Character],
        progression: ProgressionConfig = ProgressionConfig(),
        engine: EngineConfig = EngineConfig(),
        drill: DrillConfig = DrillConfig(),
        typeable: Set<Character>? = nil
    ) {
        stats = StatsTracker(config: engine)
        // Letters the layout cannot type (e.g. "ñ" with no way to make it) are
        // never unlocked, so no drill asks for them.
        var order = wordList.letterFrequencyOrder()
        if let typeable { order = order.filter(typeable.contains) }
        curriculum = Curriculum(startingKeys: startingKeys, frequencyOrder: order)
        scorer = WeaknessScorer(config: progression)
        generator = DrillGenerator(wordList: wordList, config: drill)

        // Some home rows spell very few words (QWERTY: about 40). Add letters by
        // frequency until drills have enough real words to vary.
        curriculum.unlock { wordList.words(using: $0).count >= drill.minPoolSize }
    }

    /// Restores a saved trainer. No letters are added, even if the word pool is small.
    public init(
        wordList: WordList,
        stats: StatsTracker,
        curriculum: Curriculum,
        progression: ProgressionConfig = ProgressionConfig(),
        drill: DrillConfig = DrillConfig()
    ) {
        self.stats = stats
        self.curriculum = curriculum
        scorer = WeaknessScorer(config: progression)
        generator = DrillGenerator(wordList: wordList, config: drill)
    }

    /// Records one keystroke. Returns a newly unlocked letter, if this keystroke caused one.
    @discardableResult
    public mutating func record(_ keystroke: Keystroke) -> Character? {
        stats.record(keystroke)
        return curriculum.advance(stats: stats, scorer: scorer)
    }

    /// Unlocks the next letter if all unlocked letters already meet the targets
    /// (e.g. right after the targets were lowered). Returns it.
    @discardableResult
    public mutating func advanceIfReady() -> Character? {
        curriculum.advance(stats: stats, scorer: scorer)
    }

    public var focusKey: Character? { curriculum.focusKey(stats: stats, scorer: scorer) }

    /// Weakness of `key` in [0, ...). 0 means at target. Useful for the HUD heatmap.
    public func weakness(of key: Character) -> Double { scorer.weakness(of: stats.stats(for: key)) }

    /// Unlocked letters with at least one attempt, weakest first.
    public func rankedKeys() -> [(key: Character, weakness: Double, stats: KeyStats)] {
        curriculum.unlocked
            .compactMap { key in stats.stats(for: key).map { (key, weakness(of: key), $0) } }
            .sorted { $0.weakness != $1.weakness ? $0.weakness > $1.weakness : $0.key < $1.key }
    }

    /// Letter pairs among unlocked letters with enough attempts to judge, weakest first.
    public func rankedBigrams(minAttempts: Int = 10) -> [(bigram: Bigram, weakness: Double, stats: KeyStats)] {
        let unlocked = curriculum.unlockedSet
        return stats.bigrams
            .filter { unlocked.contains($0.key.first) && unlocked.contains($0.key.second) && $0.value.attempts >= minAttempts }
            .map { ($0.key, scorer.weakness(of: $0.value, prior: 0), $0.value) }
            .sorted { $0.weakness != $1.weakness ? $0.weakness > $1.weakness : $0.bigram.description < $1.bigram.description }
    }

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

    /// Unlocked letters that meet both targets.
    public var masteredKeys: Set<Character> {
        Set(curriculum.unlocked.filter { scorer.meetsTarget(stats.stats(for: $0)) })
    }

    /// An easy drill from mastered letters only: no focus key, no weak-spot
    /// weighting, so common words win. `nil` if the mastered letters spell
    /// fewer than `minWords` real words.
    public func warmUpDrill<G: RandomNumberGenerator>(minWords: Int = 30, using rng: inout G) -> String? {
        let mastered = masteredKeys
        guard generator.wordList.words(using: mastered).count >= minWords else { return nil }
        return generator.generate(DrillRequest(unlocked: mastered), using: &rng)
    }

    public func nextDrill() -> String? {
        var rng = SystemRandomNumberGenerator()
        return nextDrill(using: &rng)
    }
}

/// Targets a key must hit before the next key unlocks.
public struct ProgressionConfig: Sendable, Equatable, Codable {
    public var targetWPM: Double
    /// In [0, 1].
    public var targetAccuracy: Double
    /// Attempts needed before a key's stats are trusted.
    public var minSamples: Int

    public init(targetWPM: Double = 35, targetAccuracy: Double = 0.95, minSamples: Int = 20) {
        self.targetWPM = targetWPM
        self.targetAccuracy = targetAccuracy
        self.minSamples = minSamples
    }
}

/// Turns key or bigram stats into a single weakness number.
///
/// 0 means "at or above target". Higher means weaker. Being 2x slower than
/// target adds 1, and every percentage point of accuracy below target adds 0.1.
/// With few samples the score is blended toward `prior`, so a barely-practiced
/// key is treated as uncertain (weak) rather than as fine.
public struct WeaknessScorer: Sendable, Equatable {
    public let config: ProgressionConfig

    public init(config: ProgressionConfig = ProgressionConfig()) {
        self.config = config
    }

    public func weakness(of stats: KeyStats?, prior: Double = 1) -> Double {
        guard let stats, stats.attempts > 0 else { return prior }
        let confidence = min(1, Double(stats.attempts) / Double(max(1, config.minSamples)))

        var measured = 0.0
        if let wpm = stats.wpm {
            measured += max(0, config.targetWPM / wpm - 1)
        } else {
            measured += prior
        }
        if let accuracy = stats.accuracy.value {
            measured += max(0, config.targetAccuracy - accuracy) * 10
        }
        return confidence * measured + (1 - confidence) * prior
    }

    public func meetsTarget(_ stats: KeyStats?) -> Bool {
        guard let stats, stats.attempts >= config.minSamples,
              let wpm = stats.wpm, let accuracy = stats.accuracy.value
        else { return false }
        return wpm >= config.targetWPM && accuracy >= config.targetAccuracy
    }
}

/// Which letters are unlocked, and in what order the rest will unlock.
///
/// The engine does not know about keyboard layouts. The app reads the
/// physical home-row keys of the active layout and passes those letters in
/// as `startingKeys` (for Dvorak: `aoeuidhtns`).
public struct Curriculum: Sendable, Equatable {
    /// Full unlock order: starting keys, then remaining letters by frequency.
    public let order: [Character]
    public private(set) var unlockedCount: Int

    /// - Parameters:
    ///   - startingKeys: Unlocked from the start. Non-letters are ignored.
    ///     If none are usable, the first `fallbackCount` letters by frequency are used.
    ///   - frequencyOrder: Every letter, most common first.
    ///   - unlockedCount: Restore saved progress.
    public init(
        startingKeys: [Character],
        frequencyOrder: [Character],
        fallbackCount: Int = 6,
        unlockedCount: Int? = nil
    ) {
        var seen = Set<Character>()
        let start = startingKeys
            .map { Character($0.lowercased()) }
            .filter { frequencyOrder.contains($0) && seen.insert($0).inserted }
        let rest = frequencyOrder.filter { !seen.contains($0) }
        order = start + rest

        let initial = start.isEmpty ? min(fallbackCount, order.count) : start.count
        self.unlockedCount = min(max(unlockedCount ?? initial, initial), order.count)
    }

    /// Restores saved progress exactly (no filtering or top-up).
    public init(order: [Character], unlockedCount: Int) {
        self.order = order
        self.unlockedCount = min(max(0, unlockedCount), order.count)
    }

    public var unlocked: [Character] { Array(order.prefix(unlockedCount)) }
    public var unlockedSet: Set<Character> { Set(unlocked) }
    public var newest: Character? { unlocked.last }
    public var nextToUnlock: Character? { unlockedCount < order.count ? order[unlockedCount] : nil }
    public var isFullyUnlocked: Bool { unlockedCount >= order.count }

    /// Unlocks the next letter if every unlocked letter meets the target. Returns it.
    @discardableResult
    public mutating func advance(stats: StatsTracker, scorer: WeaknessScorer) -> Character? {
        guard let next = nextToUnlock,
              unlocked.allSatisfy({ scorer.meetsTarget(stats.stats(for: $0)) })
        else { return nil }
        unlockedCount += 1
        return next
    }

    /// Unlocks letters in order until `hasEnough` returns true for the unlocked set,
    /// or every letter is unlocked. Returns the letters it unlocked.
    @discardableResult
    public mutating func unlock(until hasEnough: (Set<Character>) -> Bool) -> [Character] {
        var added: [Character] = []
        while !hasEnough(unlockedSet), let next = nextToUnlock {
            unlockedCount += 1
            added.append(next)
        }
        return added
    }

    /// The weakest unlocked letter. Ties go to the most recently unlocked one.
    public func focusKey(stats: StatsTracker, scorer: WeaknessScorer) -> Character? {
        var best: (key: Character, weakness: Double)?
        for key in unlocked {
            let weakness = scorer.weakness(of: stats.stats(for: key))
            if best == nil || weakness >= best!.weakness { best = (key, weakness) }
        }
        return best?.key
    }
}

import Foundation

/// Tuning knobs for the stats engine.
public struct EngineConfig: Sendable, Equatable, Codable {
    /// EWMA weight for each new sample. 0.1 means roughly the last ~20 samples dominate.
    public var smoothing: Double
    /// Latencies longer than this (seconds) are treated as pauses and ignored for speed.
    /// Accuracy is still counted.
    public var pauseThreshold: TimeInterval
    /// Count `A` and `a` as the same key. They are the same physical key.
    public var foldCase: Bool

    public init(smoothing: Double = 0.1, pauseThreshold: TimeInterval = 2.0, foldCase: Bool = true) {
        self.smoothing = smoothing
        self.pauseThreshold = pauseThreshold
        self.foldCase = foldCase
    }
}

/// Speed and accuracy for one key or one bigram.
public struct KeyStats: Sendable, Equatable, Codable {
    public private(set) var hits = 0
    public private(set) var misses = 0
    /// Smoothed latency in seconds, from correct first attempts only.
    public private(set) var latency: EWMA
    /// Smoothed accuracy in [0, 1].
    public private(set) var accuracy: EWMA

    public init(smoothing: Double) {
        latency = EWMA(alpha: smoothing)
        accuracy = EWMA(alpha: smoothing)
    }

    public var attempts: Int { hits + misses }

    /// Smoothed latency in milliseconds.
    public var latencyMs: Double? { latency.value.map { $0 * 1000 } }

    /// Speed expressed as words per minute (5 characters per word).
    public var wpm: Double? {
        guard let seconds = latency.value, seconds > 0 else { return nil }
        return 60 / (seconds * 5)
    }

    mutating func record(correct: Bool, latency sample: TimeInterval?) {
        if correct { hits += 1 } else { misses += 1 }
        accuracy.add(correct ? 1 : 0)
        if correct, let sample { latency.add(sample) }
    }
}

/// Rolling per-key and per-bigram stats. Updated after every keystroke.
public struct StatsTracker: Sendable, Equatable {
    public let config: EngineConfig
    public private(set) var keys: [Character: KeyStats] = [:]
    public private(set) var bigrams: [Bigram: KeyStats] = [:]

    public init(config: EngineConfig = EngineConfig()) {
        self.config = config
    }

    public mutating func record(_ keystroke: Keystroke) {
        // Retries on an already-missed position are ignored so one fumble counts once.
        guard keystroke.isFirstAttempt else { return }

        let expected = normalize(keystroke.expected)
        let latency = keystroke.latency.flatMap { $0 <= config.pauseThreshold ? $0 : nil }
        let blank = KeyStats(smoothing: config.smoothing)

        keys[expected, default: blank].record(correct: keystroke.isCorrect, latency: latency)

        if let previous = keystroke.previousExpected {
            let bigram = Bigram(normalize(previous), expected)
            bigrams[bigram, default: blank].record(correct: keystroke.isCorrect, latency: latency)
        }
    }

    public mutating func record(_ keystrokes: some Sequence<Keystroke>) {
        for keystroke in keystrokes { record(keystroke) }
    }

    public func stats(for key: Character) -> KeyStats? { keys[normalize(key)] }

    public func stats(for bigram: Bigram) -> KeyStats? {
        bigrams[Bigram(normalize(bigram.first), normalize(bigram.second))]
    }

    func normalize(_ character: Character) -> Character {
        guard config.foldCase else { return character }
        return character.keyLetter
    }
}

// Characters are not Codable, so keys and bigrams are stored as strings.
extension StatsTracker: Codable {
    private enum CodingKeys: String, CodingKey { case config, keys, bigrams }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decode(EngineConfig.self, forKey: .config)
        let keyStrings = try container.decode([String: KeyStats].self, forKey: .keys)
        let bigramStrings = try container.decode([String: KeyStats].self, forKey: .bigrams)
        for (string, stats) in keyStrings where string.count == 1 {
            keys[Character(string)] = stats
        }
        for (string, stats) in bigramStrings {
            let chars = Array(string)
            if chars.count == 2 { bigrams[Bigram(chars[0], chars[1])] = stats }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(config, forKey: .config)
        try container.encode(Dictionary(uniqueKeysWithValues: keys.map { (String($0.key), $0.value) }), forKey: .keys)
        try container.encode(Dictionary(uniqueKeysWithValues: bigrams.map { ($0.key.description, $0.value) }), forKey: .bigrams)
    }
}

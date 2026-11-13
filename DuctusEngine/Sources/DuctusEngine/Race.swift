import Foundation

/// How one key did within a single race.
public struct RaceKeyResult: Sendable, Equatable {
    public let key: Character
    /// Positions where this key was expected (first attempts).
    public let attempts: Int
    public let misses: Int
    /// Mean time to type this key correctly on the first try (pauses excluded).
    public let averageLatency: TimeInterval?

    public var missRate: Double { attempts == 0 ? 0 : Double(misses) / Double(attempts) }
}

/// Text generation and per-key analysis for races.
public enum Race {
    /// Random common words for a race. Uses the `poolSize` most frequent words
    /// (filtered to `allowed` letters if given), so races read like normal text.
    /// Returns `nil` if no words fit.
    public static func text<G: RandomNumberGenerator>(
        from wordList: WordList,
        wordCount: Int,
        allowed: Set<Character>? = nil,
        poolSize: Int = 1000,
        using rng: inout G
    ) -> String? {
        let candidates = allowed.map { wordList.words(using: $0) } ?? wordList.entries
        let pool = candidates.prefix(poolSize).map(\.word)
        guard !pool.isEmpty, wordCount > 0 else { return nil }

        var words: [String] = []
        for _ in 0..<wordCount {
            var pick = pool.randomElement(using: &rng)!
            // Avoid the same word twice in a row when there is a choice.
            if pool.count > 1, pick == words.last {
                pick = pool.randomElement(using: &rng)!
            }
            words.append(pick)
        }
        return words.joined(separator: " ")
    }

    /// Per-key results from a race's keystrokes. Letters are case-folded.
    public static func keyResults(_ keystrokes: [Keystroke], pauseThreshold: TimeInterval = 2) -> [RaceKeyResult] {
        var attempts: [Character: Int] = [:]
        var misses: [Character: Int] = [:]
        var latencies: [Character: [TimeInterval]] = [:]

        for keystroke in keystrokes where keystroke.isFirstAttempt {
            let key = Character(keystroke.expected.lowercased())
            attempts[key, default: 0] += 1
            if keystroke.isCorrect {
                if let latency = keystroke.latency, latency <= pauseThreshold {
                    latencies[key, default: []].append(latency)
                }
            } else {
                misses[key, default: 0] += 1
            }
        }

        return attempts.keys.sorted().map { key in
            let times = latencies[key] ?? []
            return RaceKeyResult(
                key: key,
                attempts: attempts[key]!,
                misses: misses[key, default: 0],
                averageLatency: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
            )
        }
    }

    /// The keys that cost the most in this race, worst first.
    ///
    /// Score = 3 x miss rate + how much slower than this race's average the key was
    /// (0.5 means 50% slower). Keys seen fewer than `minAttempts` times are skipped.
    public static func worstKeys(_ results: [RaceKeyResult], limit: Int = 5, minAttempts: Int = 2) -> [RaceKeyResult] {
        let timed = results.compactMap(\.averageLatency)
        let mean = timed.isEmpty ? 0 : timed.reduce(0, +) / Double(timed.count)

        func score(_ result: RaceKeyResult) -> Double {
            let slowness = mean > 0 ? max(0, (result.averageLatency ?? mean) / mean - 1) : 0
            return result.missRate * 3 + slowness
        }

        var scored: [(result: RaceKeyResult, score: Double)] = []
        for result in results where result.attempts >= minAttempts {
            let s = score(result)
            if s > 0 { scored.append((result, s)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.result.key < b.result.key }
        return Array(scored.prefix(limit).map(\.result))
    }
}

import Testing
@testable import DuctusEngine

@Suite struct RaceTests {
    let words = WordList([("the", 100), ("and", 90), ("tea", 50), ("eat", 40), ("zebra", 1)])

    @Test func textHasRequestedWordCount() throws {
        var rng = SeededGenerator(seed: 1)
        let text = try #require(Race.text(from: words, wordCount: 20, using: &rng))
        #expect(text.split(separator: " ").count == 20)
    }

    @Test func textRespectsAllowedLetters() throws {
        var rng = SeededGenerator(seed: 2)
        let text = try #require(Race.text(from: words, wordCount: 30, allowed: Set("tea"), using: &rng))
        #expect(Set(text.split(separator: " ").map(String.init)).isSubset(of: ["tea", "eat"]))
    }

    @Test func textPoolUsesMostCommonWords() throws {
        var rng = SeededGenerator(seed: 3)
        let text = try #require(Race.text(from: words, wordCount: 50, poolSize: 2, using: &rng))
        #expect(Set(text.split(separator: " ").map(String.init)).isSubset(of: ["the", "and"]))
    }

    @Test func textNilWhenNothingFits() {
        var rng = SeededGenerator(seed: 4)
        #expect(Race.text(from: words, wordCount: 5, allowed: ["q"], using: &rng) == nil)
    }

    @Test func keyResultsCountFirstAttemptsAndCapPauses() throws {
        var session = TypingSession(text: "aba")
        session.type("a", at: 0)
        session.type("x", at: 0.2)   // miss on b
        session.type("b", at: 0.4)   // retry, not a first attempt
        session.type("a", at: 10)    // long pause, excluded from speed
        let results = Race.keyResults(session.keystrokes, pauseThreshold: 2)

        let a = try #require(results.first { $0.key == "a" })
        #expect(a.attempts == 2)
        #expect(a.misses == 0)
        #expect(a.averageLatency == nil)  // first key has no latency, second was a pause

        let b = try #require(results.first { $0.key == "b" })
        #expect(b.attempts == 1)
        #expect(b.misses == 1)
        #expect(b.missRate == 1)
    }

    @Test func worstKeysRankMissesAndSlowness() {
        let results = [
            RaceKeyResult(key: "a", attempts: 10, misses: 0, averageLatency: 0.2),
            RaceKeyResult(key: "b", attempts: 10, misses: 5, averageLatency: 0.2),  // misses a lot
            RaceKeyResult(key: "c", attempts: 10, misses: 0, averageLatency: 0.5),  // slow
            RaceKeyResult(key: "d", attempts: 1, misses: 1, averageLatency: nil),   // too few tries
        ]
        let worst = Race.worstKeys(results, limit: 5, minAttempts: 2)
        // mean latency 0.3: b = 1.5, c = 0.67, a = 0 (dropped)
        #expect(worst.map(\.key) == ["b", "c"])
    }
}

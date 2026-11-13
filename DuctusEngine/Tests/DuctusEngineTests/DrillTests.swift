import Testing
@testable import DuctusEngine

private let smallList = WordList([
    ("the", 100), ("and", 80), ("sea", 40), ("tea", 30), ("ate", 20),
    ("eat", 20), ("set", 15), ("net", 10), ("ten", 10), ("jazz", 1),
])

@Suite struct WordListTests {
    @Test func parsesTSVAndSorts() throws {
        let list = try WordList(tsv: "b\t1\na\t5\n\n")
        #expect(list.entries.map(\.word) == ["a", "b"])
    }

    @Test func rejectsMalformedLines() {
        #expect(throws: EngineError.malformedLine(number: 2, line: "oops")) {
            try WordList(tsv: "a\t1\noops\n")
        }
    }

    @Test func dropsNonLetterWords() {
        let list = WordList([("Hello", 3), ("don't", 2), ("x1", 1), ("", 1)])
        #expect(list.entries.map(\.word) == ["hello"])
    }

    @Test func filtersByAllowedLetters() {
        let words = smallList.words(using: Set("tea")).map(\.word)
        #expect(Set(words) == ["tea", "ate", "eat"])
    }

    @Test func letterFrequencyOrderUsesCounts() {
        let list = WordList([("aaa", 1), ("b", 10)])
        #expect(list.letterFrequencyOrder() == ["b", "a"])
    }

    @Test func bundledListLoads() throws {
        let list = try WordList.bundledEnglish()
        #expect(list.entries.count > 5_000)
        #expect(list.entries.first?.word == "the")
        #expect(list.letterFrequencyOrder().count == 26)
        // Proper nouns and contraction fragments are filtered out by the build script.
        let words = Set(list.entries.map(\.word))
        #expect(!words.contains("holmes"))
        #expect(!words.contains("ll"))
    }
}

@Suite struct CurriculumTests {
    let order: [Character] = Array("etaoinshrdlucmfwypvbgkjqxz")

    @Test func startingKeysComeFirst() {
        let curriculum = Curriculum(startingKeys: Array("aoeuidhtns"), frequencyOrder: order)
        #expect(String(curriculum.unlocked) == "aoeuidhtns")
        #expect(curriculum.nextToUnlock == "r")
        #expect(curriculum.order.count == 26)
    }

    @Test func ignoresNonLettersAndDuplicates() {
        let curriculum = Curriculum(startingKeys: Array("asdfA;"), frequencyOrder: order)
        #expect(String(curriculum.unlocked) == "asdf")
    }

    @Test func fallsBackToMostFrequent() {
        let curriculum = Curriculum(startingKeys: [], frequencyOrder: order)
        #expect(String(curriculum.unlocked) == "etaoin")
    }

    @Test func restoresSavedProgress() {
        let curriculum = Curriculum(startingKeys: Array("asdf"), frequencyOrder: order, unlockedCount: 7)
        #expect(curriculum.unlockedCount == 7)
    }

    @Test func unlocksOnlyWhenAllKeysMeetTarget() {
        let scorer = WeaknessScorer(config: ProgressionConfig(targetWPM: 30, targetAccuracy: 0.9, minSamples: 5))
        var curriculum = Curriculum(startingKeys: ["a", "b"], frequencyOrder: Array("abc"))
        var stats = StatsTracker()

        // 0.2s per key = 60 WPM, all correct. Only "a" is practiced.
        for i in 0..<5 { stats.record(Keystroke(expected: "a", typed: "a", timestamp: Double(i), latency: 0.2)) }
        #expect(curriculum.advance(stats: stats, scorer: scorer) == nil)

        for i in 0..<5 { stats.record(Keystroke(expected: "b", typed: "b", timestamp: Double(i), latency: 0.2)) }
        #expect(curriculum.advance(stats: stats, scorer: scorer) == "c")
        #expect(curriculum.isFullyUnlocked)
        #expect(curriculum.advance(stats: stats, scorer: scorer) == nil)
    }

    @Test func unlockUntilEnoughWords() {
        var curriculum = Curriculum(startingKeys: ["t"], frequencyOrder: Array("teahnd"))
        let added = curriculum.unlock { smallList.words(using: $0).count >= 3 }
        #expect(added == ["e", "a"])  // t+e+a gives tea, ate, eat
    }

    @Test func focusIsWeakestKey() {
        let scorer = WeaknessScorer(config: ProgressionConfig(minSamples: 1))
        let curriculum = Curriculum(startingKeys: ["a", "b", "c"], frequencyOrder: Array("abc"))
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.2))
        stats.record(Keystroke(expected: "b", typed: "b", timestamp: 0, latency: 0.8))
        stats.record(Keystroke(expected: "c", typed: "c", timestamp: 0, latency: 0.3))
        #expect(curriculum.focusKey(stats: stats, scorer: scorer) == "b")
    }

    @Test func focusTieGoesToNewestKey() {
        let curriculum = Curriculum(startingKeys: ["a", "b", "c"], frequencyOrder: Array("abc"))
        #expect(curriculum.focusKey(stats: StatsTracker(), scorer: WeaknessScorer()) == "c")
    }
}

@Suite struct WeaknessScorerTests {
    let scorer = WeaknessScorer(config: ProgressionConfig(targetWPM: 60, targetAccuracy: 0.95, minSamples: 1))

    @Test func unknownKeyUsesPrior() {
        #expect(scorer.weakness(of: nil) == 1)
        #expect(scorer.weakness(of: nil, prior: 0) == 0)
    }

    @Test func fastAccurateKeyIsZero() {
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.1))  // 120 WPM
        #expect(scorer.weakness(of: stats.stats(for: "a")) == 0)
    }

    @Test func twiceAsSlowAddsOne() throws {
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.4))  // 30 WPM vs 60
        #expect(abs(scorer.weakness(of: stats.stats(for: "a")) - 1) < 1e-9)
    }

    @Test func fewSamplesBlendTowardPrior() {
        let cautious = WeaknessScorer(config: ProgressionConfig(targetWPM: 60, minSamples: 4))
        var stats = StatsTracker()
        stats.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.1))
        // Measured 0, one of four samples: 0.25 * 0 + 0.75 * 1
        #expect(abs(cautious.weakness(of: stats.stats(for: "a")) - 0.75) < 1e-9)
    }
}

@Suite struct DrillGeneratorTests {
    @Test func usesOnlyRealWordsFromUnlockedLetters() throws {
        let generator = DrillGenerator(wordList: smallList, config: DrillConfig(wordCount: 30))
        var rng = SeededGenerator(seed: 42)
        let text = try #require(generator.generate(DrillRequest(unlocked: Set("tea")), using: &rng))
        let words = text.split(separator: " ").map(String.init)
        #expect(words.count == 30)
        #expect(Set(words).isSubset(of: ["tea", "ate", "eat"]))
    }

    @Test func nilWhenNothingFits() {
        let generator = DrillGenerator(wordList: smallList)
        var rng = SeededGenerator(seed: 1)
        #expect(generator.generate(DrillRequest(unlocked: ["q"]), using: &rng) == nil)
    }

    @Test func focusKeyShowsUpOften() throws {
        let generator = DrillGenerator(wordList: smallList, config: DrillConfig(wordCount: 200, focusShare: 0.6))
        var rng = SeededGenerator(seed: 7)
        let request = DrillRequest(unlocked: Set("thesandn"), focus: "n")
        let words = try #require(generator.generate(request, using: &rng)).split(separator: " ")
        let withFocus = Double(words.filter { $0.contains("n") }.count) / Double(words.count)
        // 60% forced plus natural occurrences in the rest.
        #expect(withFocus > 0.6)
    }

    @Test func avoidsImmediateRepeats() throws {
        let generator = DrillGenerator(wordList: smallList, config: DrillConfig(wordCount: 50, focusShare: 0))
        var rng = SeededGenerator(seed: 3)
        let words = try #require(generator.generate(DrillRequest(unlocked: Set("tea")), using: &rng))
            .split(separator: " ")
        let repeats = zip(words, words.dropFirst()).filter { $0 == $1 }.count
        #expect(repeats == 0)
    }

    @Test func weakWordsScoreHigher() {
        let generator = DrillGenerator(wordList: smallList)
        let tea = smallList.entries.first { $0.word == "tea" }!
        let plain = DrillRequest(unlocked: Set("tea"))
        var weakT = plain
        weakT.keyWeakness["t"] = 2
        #expect(generator.score(tea, request: weakT) > generator.score(tea, request: plain))
    }

    @Test func sameSeedSameDrill() {
        let generator = DrillGenerator(wordList: smallList)
        let request = DrillRequest(unlocked: Set("thesandn"), focus: "e")
        var a = SeededGenerator(seed: 9), b = SeededGenerator(seed: 9)
        #expect(generator.generate(request, using: &a) == generator.generate(request, using: &b))
    }
}

@Suite struct TrainerTests {
    @Test func dvorakHomeRowNeedsNoExtraLetters() throws {
        let trainer = Trainer(wordList: try WordList.bundledEnglish(), startingKeys: Array("aoeuidhtns"))
        #expect(String(trainer.curriculum.unlocked) == "aoeuidhtns")
    }

    @Test func qwertyHomeRowGetsTopUp() throws {
        let trainer = Trainer(wordList: try WordList.bundledEnglish(), startingKeys: Array("asdfghjkl"))
        #expect(trainer.curriculum.unlockedCount > 9)
    }

    @Test func drillUsesOnlyUnlockedLetters() throws {
        let trainer = Trainer(wordList: try WordList.bundledEnglish(), startingKeys: Array("aoeuidhtns"))
        var rng = SeededGenerator(seed: 1)
        let text = try #require(trainer.nextDrill(using: &rng))
        #expect(Set(text.replacingOccurrences(of: " ", with: "")).isSubset(of: Set("aoeuidhtns")))
    }

    @Test func practiceUnlocksNextKey() throws {
        let progression = ProgressionConfig(targetWPM: 30, targetAccuracy: 0.9, minSamples: 3)
        var trainer = Trainer(wordList: smallList, startingKeys: Array("tea"), progression: progression,
                              drill: DrillConfig(minPoolSize: 1))
        var unlocked: Character?
        for key in ["t", "e", "a"] as [Character] {
            for i in 0..<3 {
                unlocked = trainer.record(Keystroke(expected: key, typed: key, timestamp: Double(i), latency: 0.2)) ?? unlocked
            }
        }
        #expect(unlocked != nil)
        #expect(trainer.curriculum.unlockedCount == 4)
    }
}

import Testing
@testable import DuctusEngine

@Suite struct BackspaceModeTests {
    @Test func wrongKeyAdvancesAndStaysMarked() throws {
        var session = TypingSession(text: "abc", mistakeMode: .backspace)
        session.type("a", at: 0)
        session.type("x", at: 0.2)  // wrong, moves on anyway
        #expect(session.position == 2)
        #expect(session.isError(at: 1))
        #expect(!session.isError(at: 0))
        #expect(session.correctCount == 1)
    }

    @Test func backspaceFixesButFirstTryStillCounts() throws {
        var session = TypingSession(text: "abc", mistakeMode: .backspace)
        session.type("a", at: 0)
        session.type("x", at: 0.2)
        let stepped = session.backspace()
        #expect(stepped)
        session.type("b", at: 0.4)   // fixed, but not a first attempt
        session.type("c", at: 0.6)
        #expect(session.isComplete)
        #expect(session.keystrokes.map(\.isFirstAttempt) == [true, true, false, true])
        let summary = try #require(session.summary)
        #expect(summary.correctCharacters == 3)
        #expect(summary.firstAttemptMisses == 1)
    }

    @Test func finishingWithMistakesCountsOnlyCorrectCharacters() throws {
        var session = TypingSession(text: "abcd", mistakeMode: .backspace)
        session.type("a", at: 0)
        session.type("x", at: 0.2)
        session.type("c", at: 0.4)
        session.type("d", at: 0.6)
        let summary = try #require(session.summary)
        #expect(summary.correctCharacters == 3)
        // 2 correct chars after the first in 0.6s = 40 WPM
        #expect(abs(try #require(summary.wpm) - 40) < 1e-9)
    }

    @Test func backspaceWordGoesToWordStart() {
        var session = TypingSession(text: "the cat", mistakeMode: .backspace)
        for (i, c) in "the ca".enumerated() { session.type(c, at: Double(i)) }
        session.backspaceWord()
        #expect(session.position == 4)  // start of "cat"
        session.backspaceWord()
        #expect(session.position == 0)
    }

    @Test func stopModeIgnoresBackspace() {
        var session = TypingSession(text: "ab")
        session.type("a", at: 0)
        let stepped = session.backspace()
        #expect(!stepped)
        #expect(session.position == 1)
    }
}

@Suite struct TextDecoratorTests {
    let plain = "the cat sat on the mat and then it ran off to see the dog"

    func strip(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0 == " " })
    }

    @Test func plainStyleChangesNothing() {
        var rng = SeededGenerator(seed: 1)
        #expect(TextDecorator.decorate(plain, style: TextStyle(), using: &rng) == plain)
    }

    @Test func wordsAreKept() {
        var rng = SeededGenerator(seed: 2)
        let styled = TextDecorator.decorate(plain, style: TextStyle(capitals: true, punctuation: true), using: &rng)
        #expect(strip(styled) == plain)
    }

    @Test func capitalsStartSentences() {
        var rng = SeededGenerator(seed: 3)
        let styled = TextDecorator.decorate(plain, style: TextStyle(capitals: true), using: &rng)
        #expect(styled.first == "T")
        #expect(!styled.contains("."))
    }

    @Test func punctuationEndsTheText() throws {
        var rng = SeededGenerator(seed: 4)
        let styled = TextDecorator.decorate(plain, style: TextStyle(punctuation: true), using: &rng)
        #expect([".", "?", "!"].contains(try #require(styled.last)))
        #expect(styled.first == "t")  // no capitals asked for
    }
}

@Suite struct SentenceTests {
    @Test func bundledSentencesLoad() throws {
        let list = try SentenceList.bundledEnglish()
        #expect(list.entries.count > 1000)
        #expect(list.entries.allSatisfy { [".", "!", "?"].contains($0.text.last!) })
    }

    @Test func filtersByAllowedLetters() {
        let list = SentenceList(text: "The cat sat.\nA dog ran far!\n")
        #expect(list.sentences(using: Set("thecasa")).map(\.text) == ["The cat sat."])
    }

    @Test func pickReachesLength() throws {
        let list = SentenceList(text: "One two three.\nFour five six.\n")
        var rng = SeededGenerator(seed: 5)
        let text = try #require(SentenceList.pick(from: list.entries, minCharacters: 60, using: &rng))
        #expect(text.count >= 60)
    }

    @Test func weakLettersArePickedMore() throws {
        let list = SentenceList(text: "Zzz zzz.\nZzz zz.\nZz zzz.\nAaa aaa.\nAaa aa.\nAa aaa.\n")
        var rng = SeededGenerator(seed: 6)
        let text = try #require(SentenceList.pick(
            from: list.entries, minCharacters: 2000, weakness: ["z": 3], using: &rng))
        let z = text.filter { $0 == "z" || $0 == "Z" }.count, a = text.filter { $0 == "a" || $0 == "A" }.count
        #expect(z > a * 3)
    }
}

@Suite struct AdjustableTargetsTests {
    @Test func changingTargetsKeepsStats() throws {
        var stats = StatsTracker()
        for i in 0..<20 { stats.record(Keystroke(expected: "a", typed: "a", timestamp: Double(i), latency: 0.3)) }
        var trainer = Trainer(wordList: WordList([("a", 1)]), stats: stats,
                              curriculum: Curriculum(order: ["a"], unlockedCount: 1))
        #expect(trainer.weakness(of: "a") == 0)  // 40 WPM beats the default 35
        trainer.scorer = WeaknessScorer(config: ProgressionConfig(targetWPM: 80))
        #expect(trainer.weakness(of: "a") > 0)
        #expect(trainer.stats == stats)
    }

    @Test func loweringTargetsCanUnlock() {
        var stats = StatsTracker()
        for i in 0..<20 { stats.record(Keystroke(expected: "a", typed: "a", timestamp: Double(i), latency: 0.5)) }
        var trainer = Trainer(wordList: WordList([("a", 1), ("b", 1)]), stats: stats,
                              curriculum: Curriculum(order: ["a", "b"], unlockedCount: 1))
        #expect(trainer.advanceIfReady() == nil)  // 24 WPM is below 35
        trainer.scorer = WeaknessScorer(config: ProgressionConfig(targetWPM: 20))
        #expect(trainer.advanceIfReady() == "b")
    }
}

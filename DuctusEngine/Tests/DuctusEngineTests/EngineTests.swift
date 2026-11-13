import Testing
@testable import DuctusEngine

@Suite struct EWMATests {
    @Test func emptyHasNoValue() {
        #expect(EWMA(alpha: 0.1).value == nil)
    }

    @Test func firstSampleIsExact() {
        var avg = EWMA(alpha: 0.1)
        avg.add(0.25)
        #expect(avg.value == 0.25)
    }

    @Test func constantInputStaysConstant() throws {
        var avg = EWMA(alpha: 0.1)
        for _ in 0..<50 { avg.add(3) }
        #expect(abs(try #require(avg.value) - 3) < 1e-9)
    }

    @Test func recentSamplesDominate() throws {
        var avg = EWMA(alpha: 0.2)
        for _ in 0..<50 { avg.add(1) }
        for _ in 0..<50 { avg.add(0) }
        #expect(try #require(avg.value) < 0.01)
    }
}

@Suite struct TypingSessionTests {
    @Test func cleanRun() throws {
        var session = TypingSession(text: "the")
        session.type("t", at: 0.0)
        session.type("h", at: 0.2)
        session.type("e", at: 0.5)

        #expect(session.isComplete)
        #expect(session.keystrokes.count == 3)
        #expect(session.keystrokes[0].latency == nil)
        #expect(session.keystrokes[1].latency == 0.2)
        #expect(session.keystrokes[2].previousExpected == "h")

        let summary = try #require(session.summary)
        #expect(summary.accuracy == 1)
        #expect(summary.duration == 0.5)
        // 2 chars in 0.5s = 4 chars/s = 240 chars/min = 48 WPM
        #expect(abs(try #require(summary.wpm) - 48) < 1e-9)
    }

    @Test func errorBlocksCursorAndCountsOnce() throws {
        var session = TypingSession(text: "ab")
        session.type("a", at: 0)
        session.type("x", at: 0.1)   // miss
        session.type("y", at: 0.2)   // miss again, same position
        session.type("b", at: 0.3)   // correct

        #expect(session.isComplete)
        #expect(session.keystrokes.map(\.isFirstAttempt) == [true, true, false, false])
        #expect(try #require(session.summary).firstAttemptMisses == 1)
        #expect(try #require(session.summary).accuracy == 0.5)
    }

    @Test func ignoresInputAfterCompletion() {
        var session = TypingSession(text: "a")
        session.type("a", at: 0)
        #expect(session.type("b", at: 1) == nil)
        #expect(session.keystrokes.count == 1)
    }

    @Test func keepsKeyCode() {
        var session = TypingSession(text: "a")
        // Dvorak "a" sits on the QWERTY "A" key, keycode 0.
        #expect(session.type("a", keyCode: 0, at: 0)?.keyCode == 0)
    }
}

@Suite struct StatsTrackerTests {
    @Test func tracksKeysAndBigrams() throws {
        var session = TypingSession(text: "the")
        session.type("t", at: 0.0)
        session.type("h", at: 0.2)
        session.type("e", at: 0.5)

        var tracker = StatsTracker()
        tracker.record(session.keystrokes)

        let h = try #require(tracker.stats(for: "h"))
        #expect(h.hits == 1)
        #expect(abs(try #require(h.latencyMs) - 200) < 1e-6)

        // First key has no latency, so speed is unknown but accuracy is counted.
        let t = try #require(tracker.stats(for: "t"))
        #expect(t.latency.value == nil)
        #expect(t.accuracy.value == 1)

        let he = try #require(tracker.stats(for: Bigram("h", "e")))
        #expect(abs(try #require(he.latencyMs) - 300) < 1e-6)
        #expect(tracker.stats(for: Bigram("e", "t")) == nil)
    }

    @Test func missCountsOnceAndRetriesIgnored() throws {
        var session = TypingSession(text: "ab")
        session.type("a", at: 0)
        session.type("x", at: 0.1)
        session.type("x", at: 0.2)
        session.type("b", at: 0.3)

        var tracker = StatsTracker()
        tracker.record(session.keystrokes)

        let b = try #require(tracker.stats(for: "b"))
        #expect(b.misses == 1)
        #expect(b.hits == 0)
        #expect(b.accuracy.value == 0)
        #expect(b.latency.value == nil) // misses never contribute speed
    }

    @Test func longPausesDoNotCountForSpeed() throws {
        var tracker = StatsTracker(config: EngineConfig(pauseThreshold: 2))
        tracker.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 10))
        let a = try #require(tracker.stats(for: "a"))
        #expect(a.hits == 1)
        #expect(a.latency.value == nil)
    }

    @Test func foldsCaseByDefault() throws {
        var tracker = StatsTracker()
        tracker.record(Keystroke(expected: "T", typed: "T", timestamp: 0, latency: 0.1))
        tracker.record(Keystroke(expected: "t", typed: "t", timestamp: 0, latency: 0.3))
        #expect(try #require(tracker.stats(for: "t")).hits == 2)
        #expect(try #require(tracker.stats(for: "T")).hits == 2)
    }

    @Test func caseFoldingCanBeDisabled() {
        var tracker = StatsTracker(config: EngineConfig(foldCase: false))
        tracker.record(Keystroke(expected: "T", typed: "T", timestamp: 0))
        #expect(tracker.stats(for: "t") == nil)
    }

    @Test func wpmFromLatency() throws {
        var tracker = StatsTracker()
        tracker.record(Keystroke(expected: "a", typed: "a", timestamp: 0, latency: 0.2))
        // 0.2s per char = 300 chars/min = 60 WPM
        #expect(abs(try #require(tracker.stats(for: "a")?.wpm) - 60) < 1e-9)
    }
}

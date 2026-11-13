import Foundation

/// Tracks the user's progress through one drill text and turns raw input
/// into `Keystroke` events.
///
/// The cursor only advances on a correct key. A wrong key is logged and the
/// user must type the right one before moving on.
public struct TypingSession: Sendable {
    public private(set) var text: [Character]
    public private(set) var position = 0
    public private(set) var keystrokes: [Keystroke] = []
    public private(set) var startTime: TimeInterval?
    public private(set) var endTime: TimeInterval?

    private var lastTimestamp: TimeInterval?
    private var missedCurrent = false

    public init(text: String) {
        precondition(!text.isEmpty, "Drill text must not be empty")
        self.text = Array(text)
    }

    public var isComplete: Bool { position >= text.count }

    /// Adds more text to the end, e.g. for timed races that must not run out.
    /// A completed session becomes incomplete again.
    public mutating func extend(with more: String) {
        guard !more.isEmpty else { return }
        text.append(contentsOf: more)
        endTime = nil
    }

    /// The character the user should type next, or `nil` when done.
    public var currentExpected: Character? { isComplete ? nil : text[position] }

    /// Feed one typed character. Returns the logged keystroke, or `nil` if the key was
    /// ignored (session already complete, or a leading space, see below).
    @discardableResult
    public mutating func type(_ typed: Character, keyCode: UInt16? = nil, at time: TimeInterval) -> Keystroke? {
        guard let expected = currentExpected else { return nil }

        // A space before the first key is the habit of finishing the previous
        // drill's last word. Drills never start with a space, so drop it.
        if keystrokes.isEmpty, typed == " ", expected != " " { return nil }

        let keystroke = Keystroke(
            expected: expected,
            typed: typed,
            previousExpected: position > 0 ? text[position - 1] : nil,
            keyCode: keyCode,
            timestamp: time,
            latency: lastTimestamp.map { time - $0 },
            isFirstAttempt: !missedCurrent
        )

        if startTime == nil { startTime = time }
        lastTimestamp = time
        keystrokes.append(keystroke)

        if keystroke.isCorrect {
            position += 1
            missedCurrent = false
            if isComplete { endTime = time }
        } else {
            missedCurrent = true
        }
        return keystroke
    }

    /// Speed so far, measured from the first key to the latest correct key.
    /// `nil` until at least two characters are typed.
    public var liveWPM: Double? {
        guard let startTime, position > 1,
              let lastCorrect = keystrokes.last(where: \.isCorrect)?.timestamp
        else { return nil }
        let elapsed = lastCorrect - startTime
        guard elapsed > 0 else { return nil }
        return Double(position - 1) / 5 / (elapsed / 60)
    }

    /// Share of positions so far typed correctly on the first try. `nil` before the first key.
    public var liveAccuracy: Double? {
        let firstAttempts = keystrokes.filter(\.isFirstAttempt)
        guard !firstAttempts.isEmpty else { return nil }
        return Double(firstAttempts.filter(\.isCorrect).count) / Double(firstAttempts.count)
    }

    /// Time actually spent typing: the gaps between keys, with each gap capped
    /// at `pauseThreshold` so walking away does not count as practice.
    public func activeDuration(pauseThreshold: TimeInterval = 2) -> TimeInterval {
        keystrokes.compactMap(\.latency).reduce(0) { $0 + min($1, pauseThreshold) }
    }

    public var summary: SessionSummary? {
        guard let startTime, let endTime else { return nil }
        let firstAttemptMisses = keystrokes.filter { $0.isFirstAttempt && !$0.isCorrect }.count
        return SessionSummary(
            characters: text.count,
            duration: endTime - startTime,
            firstAttemptMisses: firstAttemptMisses
        )
    }
}

/// Results for a finished session.
public struct SessionSummary: Sendable, Equatable {
    public let characters: Int
    /// Seconds from the first key press to the last.
    public let duration: TimeInterval
    public let firstAttemptMisses: Int

    /// Words per minute (5 characters per word). The first key starts the clock,
    /// so it is not counted as typed within the measured time.
    public var wpm: Double? {
        guard duration > 0, characters > 1 else { return nil }
        return Double(characters - 1) / 5 / (duration / 60)
    }

    /// Share of positions typed correctly on the first try, in [0, 1].
    public var accuracy: Double {
        guard characters > 0 else { return 0 }
        return Double(characters - firstAttemptMisses) / Double(characters)
    }
}

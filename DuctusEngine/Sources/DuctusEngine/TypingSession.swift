import Foundation

/// Tracks the user's progress through one drill text and turns raw input
/// into `Keystroke` events.
///
/// The cursor only advances on a correct key. A wrong key is logged and the
/// user must type the right one before moving on.
public struct TypingSession: Sendable {
    public let text: [Character]
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

    /// The character the user should type next, or `nil` when done.
    public var currentExpected: Character? { isComplete ? nil : text[position] }

    /// Feed one typed character. Returns the logged keystroke, or `nil` if the session is already complete.
    @discardableResult
    public mutating func type(_ typed: Character, keyCode: UInt16? = nil, at time: TimeInterval) -> Keystroke? {
        guard let expected = currentExpected else { return nil }

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

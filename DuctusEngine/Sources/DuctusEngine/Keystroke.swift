import Foundation

/// One key press during a practice session.
///
/// Characters are compared, not keycodes, so the engine does not care which
/// layout is active. The physical keycode is kept for the HUD and heatmap.
public struct Keystroke: Sendable, Equatable {
    /// The character the drill asked for.
    public let expected: Character
    /// The character the user actually produced.
    public let typed: Character
    /// The expected character at the previous position, if any. Used for bigram stats.
    public let previousExpected: Character?
    /// Physical keycode (macOS virtual keycode), if known.
    public let keyCode: UInt16?
    /// Event time in seconds. Any monotonic clock works (e.g. `NSEvent.timestamp`).
    public let timestamp: TimeInterval
    /// Seconds since the previous key press in this session. `nil` for the first press.
    /// This is the raw value; long pauses are filtered later by `StatsTracker`.
    public let latency: TimeInterval?
    /// `false` if the user already missed this position at least once.
    /// Only first attempts count toward stats, so a fumble is counted once.
    public let isFirstAttempt: Bool

    public var isCorrect: Bool { expected == typed }

    public init(
        expected: Character,
        typed: Character,
        previousExpected: Character? = nil,
        keyCode: UInt16? = nil,
        timestamp: TimeInterval,
        latency: TimeInterval? = nil,
        isFirstAttempt: Bool = true
    ) {
        self.expected = expected
        self.typed = typed
        self.previousExpected = previousExpected
        self.keyCode = keyCode
        self.timestamp = timestamp
        self.latency = latency
        self.isFirstAttempt = isFirstAttempt
    }
}

/// Two consecutive characters, e.g. `th`.
public struct Bigram: Hashable, Sendable, CustomStringConvertible {
    public let first: Character
    public let second: Character

    public init(_ first: Character, _ second: Character) {
        self.first = first
        self.second = second
    }

    public var description: String { String([first, second]) }
}

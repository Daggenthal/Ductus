import Foundation

/// What happens when the user types a wrong character.
public enum MistakeMode: String, Sendable, Codable, CaseIterable {
    /// The cursor stays until the right key is typed.
    case stop
    /// The cursor moves on; the mistake stays marked and can be fixed with Backspace.
    case backspace
}

/// Tracks the user's progress through one drill text and turns raw input
/// into `Keystroke` events.
///
/// In `.stop` mode the cursor only advances on a correct key. In `.backspace`
/// mode every key advances, wrong ones are remembered, and `backspace()` steps
/// back. Either way, only the first try at each position counts toward stats.
public struct TypingSession: Sendable {
    public private(set) var text: [Character]
    public let mistakeMode: MistakeMode
    public private(set) var position = 0
    /// What was typed at each position before the cursor.
    public private(set) var typed: [Character] = []
    public private(set) var keystrokes: [Keystroke] = []
    public private(set) var startTime: TimeInterval?
    public private(set) var endTime: TimeInterval?

    private var lastTimestamp: TimeInterval?
    private var missedCurrent = false
    /// Furthest position ever reached; positions before it were already attempted.
    private var furthest = 0

    public init(text: String, mistakeMode: MistakeMode = .stop) {
        precondition(!text.isEmpty, "Drill text must not be empty")
        self.text = text.typingUnits
        self.mistakeMode = mistakeMode
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

    /// `true` if the character typed at `index` (before the cursor) was wrong.
    public func isError(at index: Int) -> Bool {
        index < typed.count && typed[index] != text[index]
    }

    /// Positions before the cursor that hold the right character.
    public var correctCount: Int {
        var count = 0
        for i in 0..<typed.count where typed[i] == text[i] { count += 1 }
        return count
    }

    /// Feed one typed character. Returns the logged keystroke, or `nil` if the key was
    /// ignored (session already complete, or a leading space, see below).
    @discardableResult
    public mutating func type(_ character: Character, keyCode: UInt16? = nil, at time: TimeInterval) -> Keystroke? {
        guard let expected = currentExpected else { return nil }

        // A space before the first key is the habit of finishing the previous
        // drill's last word. Drills never start with a space, so drop it.
        if keystrokes.isEmpty, character == " ", expected != " " { return nil }

        let firstAttempt = switch mistakeMode {
        case .stop: !missedCurrent
        case .backspace: position >= furthest
        }
        let keystroke = Keystroke(
            expected: expected,
            typed: character,
            previousExpected: position > 0 ? text[position - 1] : nil,
            keyCode: keyCode,
            timestamp: time,
            latency: lastTimestamp.map { time - $0 },
            isFirstAttempt: firstAttempt
        )

        if startTime == nil { startTime = time }
        lastTimestamp = time
        keystrokes.append(keystroke)

        switch mistakeMode {
        case .stop:
            if keystroke.isCorrect {
                typed.append(character)
                position += 1
                missedCurrent = false
            } else {
                missedCurrent = true
            }
        case .backspace:
            typed.append(character)
            position += 1
            furthest = max(furthest, position)
        }
        if isComplete { endTime = time }
        return keystroke
    }

    /// Steps back one character (`.backspace` mode only). Returns `false` if it could not.
    @discardableResult
    public mutating func backspace() -> Bool {
        guard mistakeMode == .backspace, position > 0 else { return false }
        position -= 1
        typed.removeLast()
        endTime = nil
        return true
    }

    /// Steps back to the start of the current (or previous) word, like Option-Delete.
    @discardableResult
    public mutating func backspaceWord() -> Bool {
        guard mistakeMode == .backspace, position > 0 else { return false }
        while position > 0, text[position - 1] == " " { backspace() }
        while position > 0, text[position - 1] != " " { backspace() }
        return true
    }

    /// Speed so far (correct characters), measured from the first key to the latest key.
    /// `nil` until at least two characters are typed.
    public var liveWPM: Double? {
        let correct = correctCount
        guard let startTime, correct > 1, let last = keystrokes.last?.timestamp else { return nil }
        let elapsed = last - startTime
        guard elapsed > 0 else { return nil }
        return Double(correct - 1) / 5 / (elapsed / 60)
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
            correctCharacters: correctCount,
            duration: endTime - startTime,
            firstAttemptMisses: firstAttemptMisses
        )
    }
}

/// Results for a finished session.
public struct SessionSummary: Sendable, Equatable {
    public let characters: Int
    /// Characters left correct at the end. Equal to `characters` in `.stop` mode.
    public let correctCharacters: Int
    /// Seconds from the first key press to the last.
    public let duration: TimeInterval
    public let firstAttemptMisses: Int

    public init(characters: Int, correctCharacters: Int? = nil, duration: TimeInterval, firstAttemptMisses: Int) {
        self.characters = characters
        self.correctCharacters = correctCharacters ?? characters
        self.duration = duration
        self.firstAttemptMisses = firstAttemptMisses
    }

    /// Words per minute (5 characters per word), counting only correct characters.
    /// The first key starts the clock, so it is not counted within the measured time.
    public var wpm: Double? {
        guard duration > 0, correctCharacters > 1 else { return nil }
        return Double(correctCharacters - 1) / 5 / (duration / 60)
    }

    /// Share of positions typed correctly on the first try, in [0, 1].
    public var accuracy: Double {
        guard characters > 0 else { return 0 }
        return Double(characters - firstAttemptMisses) / Double(characters)
    }
}

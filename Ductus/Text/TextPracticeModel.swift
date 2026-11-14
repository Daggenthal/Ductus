import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// Practice on your own text: paste an article, a chapter or some code and
/// type through it part by part. Keystrokes count toward your key stats like
/// practice and races do, and finished parts show in History.
@MainActor
@Observable
final class TextPracticeModel {
    private(set) var texts: [SavedText] = []
    private(set) var selected: SavedText?
    /// The selected text split into parts of about 300 characters.
    private(set) var parts: [String] = []
    private(set) var session: TypingSession?
    private(set) var lastKeyWrong = false
    private(set) var lastSummary: SessionSummary?
    /// A short message after adding a text, e.g. characters left out.
    private(set) var notice: String?
    private(set) var sessionID = 0

    @ObservationIgnored private let practice: PracticeModel
    @ObservationIgnored private let store: ProgressStore

    init(practice: PracticeModel, store: ProgressStore) {
        self.practice = practice
        self.store = store
        texts = store.savedTexts()
        select(texts.first)
    }

    var isFinished: Bool {
        guard let selected else { return false }
        return !parts.isEmpty && selected.part >= parts.count
    }

    /// Share of the selected text typed, 0 to 1.
    var progress: Double {
        guard let selected, !parts.isEmpty else { return 0 }
        return Double(min(selected.part, parts.count)) / Double(parts.count)
    }

    // MARK: - Texts

    /// Cleans and saves a pasted text, then selects it. Returns `false` if
    /// nothing typeable is left.
    @discardableResult
    func add(_ raw: String, title: String, keepLineBreaks: Bool) -> Bool {
        let cleaned = CustomText.clean(raw, keepLineBreaks: keepLineBreaks, canType: practice.canType)
        guard !cleaned.text.isEmpty else {
            notice = "Nothing in that text can be typed on this layout."
            return false
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = SavedText(
            title: name.isEmpty ? CustomText.title(for: cleaned.text) : name,
            body: cleaned.text, keepLineBreaks: keepLineBreaks
        )
        store.insert(text)
        texts.insert(text, at: 0)
        select(text)
        notice = cleaned.dropped > 0
            ? "\(cleaned.dropped) character\(cleaned.dropped == 1 ? "" : "s") your layout cannot type \(cleaned.dropped == 1 ? "was" : "were") left out."
            : nil
        Log.info("Added text \"\(text.title)\" (\(cleaned.text.count) characters, \(parts.count) parts)")
        return true
    }

    func select(_ text: SavedText?) {
        selected = text
        notice = nil
        lastSummary = nil
        parts = text.map { CustomText.parts(of: $0.body) } ?? []
        if let text {
            text.lastOpened = Date()
            store.save()
        }
        startPart()
    }

    func rename(_ text: SavedText, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        text.title = name
        store.save()
    }

    func delete(_ text: SavedText) {
        let wasSelected = text === selected
        texts.removeAll { $0 === text }
        store.delete(text)
        if wasSelected { select(texts.first) }
    }

    // MARK: - Moving through a text

    func startOver() {
        guard let selected else { return }
        selected.part = 0
        store.save()
        lastSummary = nil
        startPart()
    }

    func skipPart() {
        guard let selected, selected.part < parts.count else { return }
        selected.part += 1
        store.save()
        startPart()
    }

    func previousPart() {
        guard let selected, selected.part > 0 else { return }
        selected.part = min(selected.part, parts.count) - 1
        store.save()
        startPart()
    }

    private func startPart() {
        lastKeyWrong = false
        sessionID += 1
        guard let selected, selected.part < parts.count else {
            session = nil
            return
        }
        session = TypingSession(text: parts[selected.part], mistakeMode: PracticeSettings.mistakeMode)
    }

    // MARK: - Typing

    /// Feeds one typed character. Returns `true` if it was used.
    func type(_ character: Character, keyCode: UInt16, at time: TimeInterval) -> Bool {
        guard session != nil else { return false }
        guard let keystroke = session?.type(character, keyCode: keyCode, at: time) else { return true }
        lastKeyWrong = !keystroke.isCorrect && session?.mistakeMode == .stop
        practice.onKeystroke?(keystroke.isCorrect)
        practice.recordExternal(keystroke)

        if let session, session.isComplete {
            finishPart(session)
        }
        return true
    }

    /// Backspace (or Option-Backspace for a word) in "fix with Backspace" mode.
    func backspace(word: Bool) -> Bool {
        guard session?.mistakeMode == .backspace else { return false }
        if word { session?.backspaceWord() } else { session?.backspace() }
        return true
    }

    private func finishPart(_ session: TypingSession) {
        if let summary = session.summary {
            lastSummary = summary
            practice.recordTextPart(summary, activeTime: session.activeDuration(pauseThreshold: practice.pauseThreshold))
        }
        selected?.part += 1
        store.save()
        startPart()
    }
}

import DuctusEngine
import SwiftUI

struct PracticeView: View {
    @Environment(PracticeModel.self) private var practice
    @Environment(KeyboardState.self) private var keyboard
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.keyboardPoppedOut) private var poppedOut = false
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 0
    private var keyboardDocked: Bool { showKeyboard && !poppedOut }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            if let error = practice.loadError {
                Text(error).foregroundStyle(.red)
            } else if let session = practice.session {
                if practice.language == .korean, let gloss = practice.gloss {
                    // Korean shows real syllable blocks that build up as you type.
                    HangulText(session: session, gloss: gloss, lastKeyWrong: practice.lastKeyWrong,
                               fontSize: 34 * textScale)
                } else {
                    if let gloss = practice.gloss {
                        GlossBar(gloss: gloss, position: session.position, fontSize: 40 * textScale)
                    }
                    DrillText(session: session, lastKeyWrong: practice.lastKeyWrong, fontSize: 28 * textScale)
                }
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
            LetterProgress()
            if keyboardDocked {
                PracticeKeyboard(keyboard: keyboard, practice: practice)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            footer
        }
        .padding(32)
        .frame(minWidth: 760, minHeight: keyboardDocked ? 700 : 440, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: keyboardDocked)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            Stat(title: "Now", value: practice.session?.liveWPM.map { String(format: "%.0f WPM", $0) } ?? "-")
            Stat(title: "Last drill", value: practice.lastSummary?.wpm.map { String(format: "%.0f WPM", $0) } ?? "-")
            Stat(title: "Accuracy", value: practice.lastSummary.map { String(format: "%.0f%%", $0.accuracy * 100) } ?? "-")
            if practice.isWarmUp {
                Stat(title: "Focus key", value: String(localized: "Warm-up", bundle: .ui))
                    .help("An easy drill with only the keys you have mastered, to start a session")
            } else if let focus = practice.focusKey {
                Stat(title: "Focus key", value: focus.uppercased())
            }
            if dailyGoal > 0 {
                DailyGoalRing(practiced: practice.todayPracticeTime, goalMinutes: dailyGoal)
            }
            Spacer()
            if let message = practice.unlockMessage {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("Just start typing. Mistakes keep the cursor in place until you hit the right key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Keyboard", isOn: $showKeyboard)
                .help("Show or hide the keyboard (⌘K)")
            Toggle("Pop out", isOn: $poppedOut)
                .help("Float the keyboard in its own window (⌘⇧K)")
                .disabled(!showKeyboard)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

struct Stat: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

/// The drill text: typed part faded, current character highlighted
/// (red after a miss), the rest normal.
struct DrillText: View {
    let session: TypingSession
    let lastKeyWrong: Bool
    var fontSize: CGFloat = 28

    var body: some View {
        Text(attributed)
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .lineSpacing(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)
    }

    private var attributed: AttributedString {
        let text = session.text
        let position = session.position

        // Typed part, with mistakes left behind (Backspace mode) in red.
        var done = AttributedString()
        var runStart = 0
        func flush(_ end: Int, error: Bool) {
            guard end > runStart else { return }
            var run = AttributedString(String(text[runStart..<end]))
            run.foregroundColor = error ? .red : .secondary.opacity(0.6)
            if error { run.backgroundColor = .red.opacity(0.15) }
            done += run
            runStart = end
        }
        var inError = false
        for i in 0..<position where session.isError(at: i) != inError {
            flush(i, error: inError)
            inError.toggle()
        }
        flush(position, error: inError)

        var current = AttributedString(position < text.count ? String(text[position]) : "")
        current.backgroundColor = lastKeyWrong ? .red.opacity(0.35) : .accentColor.opacity(0.3)

        var rest = AttributedString(position + 1 < text.count ? String(text[(position + 1)...]) : "")
        rest.foregroundColor = .primary

        return done + current + rest
    }
}

/// All letters in unlock order: unlocked ones bold, the next one outlined, the rest faded.
private struct LetterProgress: View {
    @Environment(PracticeModel.self) private var practice

    var body: some View {
        if let curriculum = practice.trainer?.curriculum {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unlocked \(curriculum.unlockedCount) of \(curriculum.order.count)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(Array(curriculum.order.enumerated()), id: \.offset) { index, letter in
                        let unlocked = index < curriculum.unlockedCount
                        let isNext = index == curriculum.unlockedCount
                        Text(letter.uppercased())
                            .font(.system(.body, design: .monospaced).weight(unlocked ? .bold : .regular))
                            .foregroundStyle(unlocked ? .primary : .tertiary)
                            .frame(width: 22, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(letter == practice.focusKey ? Color.accentColor.opacity(0.25) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(isNext ? Color.secondary : .clear, style: StrokeStyle(lineWidth: 1, dash: [3]))
                            )
                    }
                }
            }
        }
    }
}

import DuctusEngine
import SwiftUI

struct PracticeView: View {
    @Environment(PracticeModel.self) private var practice
    @Environment(KeyboardState.self) private var keyboard
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.keyboardPoppedOut) private var poppedOut = false
    @Environment(AppUIState.self) private var ui

    private var keyboardDocked: Bool { showKeyboard && !poppedOut }

    var body: some View {
        @Bindable var ui = ui
        practiceContent
            .inspector(isPresented: $ui.showSettings) {
                SettingsView()
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        ui.setSettings(!ui.showSettings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings (⌘,)")
                }
            }
            .onChange(of: ui.showSettings) { _, showing in
                if !showing { ui.settingsDidClose() }
            }
    }

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            if let error = practice.loadError {
                Text(error).foregroundStyle(.red)
            } else if let session = practice.session {
                DrillText(session: session, lastKeyWrong: practice.lastKeyWrong)
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
            if let focus = practice.focusKey {
                let stats = practice.stats(for: focus)
                Stat(
                    title: "Focus key",
                    value: focus.uppercased()
                        + (stats?.wpm.map { String(format: "  %.0f WPM", $0) } ?? "")
                        + (stats?.accuracy.value.map { String(format: "  %.0f%%", $0 * 100) } ?? "")
                )
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

private struct Stat: View {
    let title: String
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
private struct DrillText: View {
    let session: TypingSession
    let lastKeyWrong: Bool

    var body: some View {
        Text(attributed)
            .font(.system(size: 28, weight: .regular, design: .monospaced))
            .lineSpacing(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)
    }

    private var attributed: AttributedString {
        let text = session.text
        let position = session.position

        var done = AttributedString(String(text[..<position]))
        done.foregroundColor = .secondary.opacity(0.6)

        var current = AttributedString(position < text.count ? String(text[position]) : "")
        current.backgroundColor = lastKeyWrong ? .red.opacity(0.35) : .accentColor.opacity(0.3)
        current.underlineStyle = .single

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

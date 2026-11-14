import AppKit
import DuctusEngine
import SwiftUI

/// The Text tab: your saved texts on the left, the selected one to type on the right.
struct TextPracticeView: View {
    @Environment(TextPracticeModel.self) private var model
    @Environment(KeyboardState.self) private var keyboard
    @Environment(PracticeModel.self) private var practice
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @AppStorage(SettingsKey.fadeMastered) private var fadeMastered = true
    @State private var adding = false
    @State private var renaming: SavedText?
    @State private var newTitle = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            detail
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: showKeyboard ? 720 : 480)
        .sheet(isPresented: $adding) {
            NewTextSheet { raw, title, keepLineBreaks in
                model.add(raw, title: title, keepLineBreaks: keepLineBreaks)
            }
        }
        .alert("Rename Text", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let renaming { model.rename(renaming, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(
                get: { model.selected?.persistentModelID },
                set: { id in model.select(model.texts.first { $0.persistentModelID == id }) }
            )) {
                ForEach(model.texts) { text in
                    TextRow(text: text, partCount: text === model.selected ? model.parts.count : nil)
                        .tag(text.persistentModelID)
                        .contextMenu {
                            Button("Rename…") {
                                newTitle = text.title
                                renaming = text
                            }
                            Button("Delete", role: .destructive) { model.delete(text) }
                        }
                }
            }
            .listStyle(.sidebar)
            Divider()
            Button {
                adding = true
            } label: {
                Label("New Text…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let text = model.selected {
            VStack(alignment: .leading, spacing: 24) {
                header(text)
                if let notice = model.notice {
                    Text(notice).font(.callout).foregroundStyle(.orange)
                }
                if let session = model.session {
                    RaceTextView(session: session, lastKeyWrong: model.lastKeyWrong,
                                 fontSize: 28 * textScale, visibleLines: 4)
                        .id(model.sessionID)
                    if session.position == 0 {
                        Text(text.keepLineBreaks
                             ? "Press Return at each ↵. Indentation is skipped."
                             : "Just start typing. Your keys count toward practice, like races do.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if model.isFinished {
                    finished
                }
                Spacer(minLength: 0)
                if showKeyboard, let session = model.session {
                    KeyboardView(
                        keyboard: keyboard,
                        nextCharacter: session.currentExpected,
                        mastered: fadeMastered ? practice.masteredLetters : [],
                        animatesPresses: false
                    )
                    .background(ThemedKeyboardBacking())
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            empty
        }
    }

    private func header(_ text: SavedText) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(text.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.previousPart()
                } label: {
                    Label("Previous Part", systemImage: "chevron.left")
                }
                .disabled(text.part == 0)
                Button {
                    model.skipPart()
                } label: {
                    Label("Skip Part", systemImage: "chevron.right")
                }
                .disabled(model.isFinished)
                Button("Start Over") { model.startOver() }
                    .disabled(text.part == 0)
            }
            .labelStyle(.iconOnly)
            HStack(spacing: 28) {
                Stat(title: "Part", value: "\(min(text.part + 1, model.parts.count)) of \(model.parts.count)")
                Stat(title: "Now", value: model.session?.liveWPM.map { String(format: "%.0f WPM", $0) } ?? "-")
                Stat(title: "Last part",
                     value: model.lastSummary?.wpm.map { String(format: "%.0f WPM", $0) } ?? "-")
                Stat(title: "Accuracy",
                     value: model.lastSummary.map { String(format: "%.0f%%", $0.accuracy * 100) } ?? "-")
            }
            ProgressView(value: model.progress)
                .tint(.accentColor)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You typed the whole text 🎉")
                .font(.title3.weight(.semibold))
            Button("Start Over") { model.startOver() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Practice on your own text")
                .font(.title3.weight(.semibold))
            Text("Paste an article, a book chapter or some code. You type it part by part, and your keys count toward practice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Button("New Text…") { adding = true }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TextRow: View {
    let text: SavedText
    /// Known for the selected text; others show only their title.
    let partCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text.title).lineLimit(1)
            if let partCount, partCount > 0 {
                Text(text.part >= partCount ? "Done" : "Part \(text.part + 1) of \(partCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if text.part > 0 {
                Text("In progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Paste or type a new text.
private struct NewTextSheet: View {
    let onAdd: (String, String, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var keepLineBreaks = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Text").font(.title3.weight(.semibold))
            TextField("Title (optional)", text: $title)
            TextEditor(text: $body_)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Button("Paste from Clipboard") {
                    if let string = NSPasteboard.general.string(forType: .string) { body_ = string }
                }
                Spacer()
                Text("\(body_.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Keep line breaks (for code and poems)", isOn: $keepLineBreaks)
            Text("Curly quotes, long dashes and similar are changed to keys you can type. Characters your layout cannot type are left out. The text is saved on this Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if failed {
                Text("Nothing in that text can be typed on this layout.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if onAdd(body_, title, keepLineBreaks) { dismiss() } else { failed = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

import DuctusEngine
import DuctusLog
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.keyboardPoppedOut) private var poppedOut = false
    @AppStorage(SettingsKey.hudOpacity) private var opacity = 0.9
    @AppStorage(SettingsKey.hudClickThrough) private var clickThrough = false
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true
    @AppStorage(SettingsKey.showDrillInFloating) private var showDrillInFloating = true
    @AppStorage(SettingsKey.showStatsInFloating) private var showStatsInFloating = true

    @AppStorage(SettingsKey.targetWPM) private var targetWPM = 35.0
    @AppStorage(SettingsKey.targetAccuracy) private var targetAccuracy = 95.0
    @AppStorage(SettingsKey.mistakeMode) private var mistakeMode = MistakeMode.stop.rawValue
    @AppStorage(SettingsKey.capitals) private var capitals = false
    @AppStorage(SettingsKey.punctuation) private var punctuation = false
    @AppStorage(SettingsKey.sentenceDrills) private var sentenceDrills = false
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 0
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @AppStorage(SettingsKey.fadeMastered) private var fadeMastered = true
    @AppStorage(SettingsKey.keySounds) private var keySounds = false
    @AppStorage(SettingsKey.mistakeSound) private var mistakeSound = false
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = 0.5
    @AppStorage(SettingsKey.systemWideHighlighting) private var systemWide = false
    @AppStorage(SettingsKey.warmUp) private var warmUp = true
    @AppStorage(SettingsKey.shortcutKeys) private var shortcutKeys = SettingsKey.defaultShortcutKeys
    @AppStorage(SettingsKey.keyboardShape) private var keyboardShape = "auto"
    @AppStorage(SettingsKey.practiceLanguage) private var practiceLanguage = "auto"
    @Environment(KeyboardState.self) private var keyboard

    @Environment(PracticeModel.self) private var practice
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var hasInputMonitoring = GlobalKeyMonitor.hasPermission
    @State private var showingCredits = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                note("System follows your macOS setting. Applies to the floating keyboard too.")
                Picker("Practice language", selection: $practiceLanguage) {
                    Text("Automatic (\(PracticeSettings.detectedLanguage(for: keyboard.layout).nativeName))").tag("auto")
                    ForEach(PracticeLanguage.allCases) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
                note("The words and sentences you practice. Automatic follows your keyboard layout or input method, so a French layout practices French and the Japanese input method practices Japanese. Japanese is typed in romaji, Chinese in pinyin (no tones, v for ü) and Korean on the 2-Set layout, with the text shown above. Progress is kept separately for each layout and language.")
            }

            Section("Unlocking") {
                LabeledContent("Target speed") {
                    Stepper("\(Int(targetWPM)) WPM", value: $targetWPM, in: 10...150, step: 5)
                }
                LabeledContent("Target accuracy") {
                    Stepper("\(Int(targetAccuracy))%", value: $targetAccuracy, in: 80...100, step: 1)
                }
                note("Every unlocked key must reach both before the next letter unlocks. Your stats are kept when you change these.")
            }

            Section("Typing") {
                Toggle("Warm up first", isOn: $warmUp)
                note("Each session starts with one easy drill using only keys you have mastered. A session starts at launch or after a 10 minute break.")
                Picker("Mistakes", selection: $mistakeMode) {
                    Text("Stop until corrected").tag(MistakeMode.stop.rawValue)
                    Text("Keep going, fix with Backspace").tag(MistakeMode.backspace.rawValue)
                }
                note("With Backspace, mistakes stay marked in red. Option-Backspace deletes a word. Only your first try at each letter counts toward stats. Applies from the next drill or race.")
                Toggle("Capitals", isOn: $capitals)
                Toggle("Punctuation", isOn: $punctuation)
                note("Words are grouped into short sentences with capitals and commas, periods and question marks. When a character needs Shift, the Shift keys are outlined.")
                Toggle("Sentence drills", isOn: $sentenceDrills)
                if sentenceDrills && !practice.sentenceDrillsAvailable {
                    note("Not enough sentences use only your unlocked letters yet (\(practice.sentencePool.count) of \(PracticeModel.minSentencePool) needed). Practice stays on words until then.", color: .orange)
                } else {
                    note("Practice with real sentences from books, using only your unlocked letters, weighted toward your weak keys.")
                }
                Picker("Daily goal", selection: $dailyGoal) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }

            Section("Display") {
                LabeledContent("Text size") {
                    Slider(value: $textScale, in: 0.75...1.5, step: 0.05)
                        .frame(width: 180)
                }
                Toggle("Fade keys you have mastered", isOn: $fadeMastered)
                note("Labels fade on keys that meet your targets, so you look down less. The next key is still outlined.")
            }

            Section("Keyboard") {
                Toggle("Show keyboard", isOn: $showKeyboard)
                Picker("Keyboard type", selection: $keyboardShape) {
                    Text("Automatic (\(keyboard.detectedShape.title))").tag("auto")
                    Text("ANSI (U.S.)").tag(KeyboardGeometry.Shape.ansi.rawValue)
                    Text("ISO (Europe)").tag(KeyboardGeometry.Shape.iso.rawValue)
                    Text("JIS (Japan)").tag(KeyboardGeometry.Shape.jis.rawValue)
                }
                note("The shape of your physical keyboard. Automatic uses the keyboard you last typed on. ISO has a tall Return and an extra key next to left Shift.")
                Toggle("Pop out into a floating window", isOn: $poppedOut)
                Toggle("Show drill text above the floating keyboard", isOn: $showDrillInFloating)
                note("Keeps the words and the keys close together so your eyes do not have to travel.")
                Toggle("Show stats above the floating keyboard", isOn: $showStatsInFloating)
                note("Live speed and accuracy, the last drill, your focus key and unlock progress.")
                LabeledContent("Floating opacity") {
                    Slider(value: $opacity, in: 0.2...1)
                        .frame(width: 180)
                }
                Toggle("Show physical key labels", isOn: $showPhysicalLabels)
                note("A faint QWERTY letter in the corner of each key, showing what is printed on your real keyboard.")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shortcut glow")
                        Spacer()
                        Button("Reset") { shortcutKeys = SettingsKey.defaultShortcutKeys }
                            .disabled(shortcutKeys == SettingsKey.defaultShortcutKeys)
                    }
                    ShortcutKeyPicker(selection: $shortcutKeys)
                }
                note("While you hold Command, these keys glow so you can find shortcuts like ⌘C. Works with layouts that switch to QWERTY under Command.")
                Toggle("Floating click-through", isOn: $clickThrough)
                note("Clicks pass through the floating keyboard to whatever is underneath. You cannot drag it or type into it while this is on.")
            }

            Section("Typing in other apps") {
                Toggle("Light up the floating keyboard in other apps", isOn: $systemWide)
                    .onChange(of: systemWide) { _, on in
                        if on, !GlobalKeyMonitor.hasPermission { GlobalKeyMonitor.requestPermission() }
                        hasInputMonitoring = GlobalKeyMonitor.hasPermission
                    }
                note("Needs the Input Monitoring permission. Ductus only uses which keys are down to light them up. Nothing is stored or sent anywhere, and macOS blocks it in password fields.")
                if systemWide && !hasInputMonitoring {
                    note("Permission not granted yet. Turn on Ductus in Input Monitoring, then quit and reopen Ductus.", color: .orange)
                    Button("Open Input Monitoring Settings") { GlobalKeyMonitor.openPrivacySettings() }
                }
            }

            Section("Sound") {
                Toggle("Key clicks", isOn: $keySounds)
                Toggle("Mistake sound", isOn: $mistakeSound)
                LabeledContent("Volume") {
                    Slider(value: $soundVolume, in: 0...1)
                        .frame(width: 180)
                }
                .disabled(!keySounds && !mistakeSound)
            }

            Section("Text Sources") {
                note("Words and sentences come from public-domain books on Project Gutenberg. Japanese, Chinese and Korean sentences come from Tatoeba (CC BY 2.0 FR), changed for typing: romanized and split into chunks for Japanese and Chinese (Chinese converted to Simplified), and paired with the 2-Set keys for Korean.")
                HStack {
                    Link("Project Gutenberg", destination: URL(string: "https://www.gutenberg.org")!)
                    Link("Tatoeba", destination: URL(string: "https://tatoeba.org")!)
                    Spacer()
                    Button("Sentence Authors…") { showingCredits = true }
                }
                note("Readings were made with UniDic, pypinyin and OpenCC when building the lists. See CORPUS.md in the source code for every book and tool.")
            }

            Section("Progress") {
                LabeledContent("Layout", value: practice.layoutName)
                LabeledContent("Drills completed", value: "\(practice.profile?.drills.count ?? 0)")
                if !practice.isSavingProgress {
                    note("Progress could not be saved this session. Check the log for details.", color: .orange)
                } else {
                    note("Progress is saved on this Mac, separately for each keyboard layout.")
                }
                Button("Export History…") { exporting = true }
                    .disabled(practice.profile == nil)
                Button("Reset Progress…", role: .destructive) { confirmingReset = true }
                    .disabled(practice.profile == nil)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingCredits) { SentenceAuthorsSheet() }
        .onAppear { hasInputMonitoring = GlobalKeyMonitor.hasPermission }
        .confirmationDialog(
            "Reset all progress for \(practice.layoutName)?",
            isPresented: $confirmingReset
        ) {
            Button("Reset Progress", role: .destructive) { practice.resetProgress() }
        } message: {
            Text("This deletes your key stats, unlocked letters and history for this layout. It cannot be undone.")
        }
        .fileExporter(
            isPresented: $exporting,
            document: CSVDocument(text: practice.historyCSV()),
            contentType: .commaSeparatedText,
            defaultFilename: "Ductus history"
        ) { result in
            if case .failure(let error) = result {
                Log.error("Could not export history: \(error)")
            }
        }
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
    }
}

/// Every Tatoeba author whose sentences are bundled, as the license asks.
private struct SentenceAuthorsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let languages = PracticeLanguage.allCases
        .map { ($0, $0.sentenceAuthors()) }
        .filter { !$0.1.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentence Authors").font(.title3.weight(.semibold))
            Text("Sentences from Tatoeba (tatoeba.org) under CC BY 2.0 FR, by these contributors. Each sentence's ID and author is listed in the credits files in the source code.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(languages, id: \.0) { language, authors in
                    Section("\(language.nativeName): \(authors.count) authors") {
                        ForEach(authors, id: \.author) { entry in
                            LabeledContent(entry.author, value: "\(entry.sentences)")
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 520)
    }
}

/// Grid of A to Z toggles. The selection is stored as a sorted string, e.g. "cvxz".
private struct ShortcutKeyPicker: View {
    @Binding var selection: String
    private let letters = Array("abcdefghijklmnopqrstuvwxyz")

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
            ForEach(letters, id: \.self) { letter in
                let on = selection.contains(letter)
                Button {
                    var set = Set(selection)
                    if on { set.remove(letter) } else { set.insert(letter) }
                    selection = String(set.sorted())
                } label: {
                    Text(letter.uppercased())
                        .font(.system(.callout, design: .rounded).weight(on ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(on ? Color.yellow.opacity(0.35) : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(on ? Color.yellow.opacity(0.8) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(letter.uppercased()) shortcut glow")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A CSV file for the exporter.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

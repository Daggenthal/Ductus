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
    @AppStorage(SettingsKey.practiceLayout) private var practiceLayout = ""
    @AppStorage(SettingsKey.practiceLayoutAuto) private var practiceLayoutAuto = false
    @AppStorage(SettingsKey.practiceLanguage) private var practiceLanguage = "auto"
    @Environment(KeyboardState.self) private var keyboard

    @Environment(PracticeModel.self) private var practice
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var hasInputMonitoring = GlobalKeyMonitor.hasPermission
    @Environment(\.openWindow) private var openWindow
    @Environment(UpdateChecker.self) private var updater
    @AppStorage(UpdateChecker.Keys.automatic) private var checkAutomatically = false
    @AppStorage(SettingsKey.debugMode) private var debugMode = false
    @AppStorage(SettingsKey.fingerZones) private var fingerZones = false

    /// The Debug section is hidden unless Option is held when Settings opens, or debug is on.
    @State private var showDebug = false
    @State private var browsingLayouts = false

    var body: some View {
        let _ = LanguageState.shared.locale  // redraw when the app language changes
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                note("System follows your macOS setting. Applies to the floating keyboard too.")
                Picker("App language", selection: Binding(
                    get: { LanguageState.shared.language },
                    set: { LanguageState.shared.set($0) }
                )) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                }
                note("Translated with AI, so some wording may not be completely accurate.", color: Color.secondary.opacity(0.7))
                if LanguageState.shared.changedThisSession {
                    note("The menu bar changes the next time Ductus opens.")
                }
                Picker("Practice language", selection: $practiceLanguage) {
                    Text("Automatic (\(PracticeSettings.detectedLanguage(for: keyboard.layout).nativeName))").tag("auto")
                    ForEach(PracticeLanguage.allCases) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
                note("The words and sentences you practice. Automatic follows your keyboard layout or input method, so a French layout practices French and the Japanese input method practices Japanese. Japanese is typed in romaji, Chinese in pinyin (no tones, v for ü) and Korean on the 2-Set layout, with the text shown above. Progress is kept separately for each layout and language.")
                layoutPicker
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
                Toggle("Color keys by finger", isOn: $fingerZones)
                FingerLegend()
                note("Tints each key by the finger that presses it in touch typing: pinky, ring, middle, index, and thumbs for the space bar. Handy in the first days of a new layout.")
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

            Section("Updates") {
                LabeledContent("Version", value: updater.currentVersion.description)
                Toggle("Check for updates automatically", isOn: $checkAutomatically)
                note("At most once a day, Ductus asks GitHub whether there is a newer version and tells you. Updates are only downloaded and installed when you click Download and Install. Nothing about you is sent.")
                HStack {
                    Button("Check Now") {
                        updater.check(userInitiated: true)
                        openWindow(id: UpdateView.windowID)
                    }
                    if let last = updater.lastChecked {
                        Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Text Sources") {
                note("Words and sentences come from public-domain books on Project Gutenberg and from Tatoeba contributors (CC BY 2.0 FR).")
                Button("About and Credits…") { openWindow(id: AboutView.windowID) }
            }

            if showDebug {
                Section("Debug") {
                    Toggle("Debug mode", isOn: $debugMode)
                        .disabled(Log.debugFromEnvironment)
                    if Log.debugFromEnvironment {
                        note("On because DUCTUS_DEBUG=1 is set.")
                    } else {
                        note("Logs everything Ductus does (drill text, unlocks, saves, errors) to a file on this Mac. Typed keys are never logged. This section shows when you hold Option while opening Settings.")
                    }
                    HStack {
                        Button("Show Log File") {
                            NSWorkspace.shared.activateFileViewerSelecting([DebugMode.logFileURL])
                        }
                        .disabled(!FileManager.default.fileExists(atPath: DebugMode.logFileURL.path))
                        Button("Clear Log") {
                            try? FileManager.default.removeItem(at: DebugMode.logFileURL)
                            if Log.logFile != nil { Log.logFile = DebugMode.logFileURL }
                        }
                    }
                }
            }

            Section("Progress") {
                LabeledContent("Layout", value: practice.layoutName)
                LabeledContent("Drills completed", value: "\(practice.drillHistory.count)")
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
        .onAppear {
            if NSEvent.modifierFlags.contains(.option) || debugMode || Log.debugFromEnvironment { showDebug = true }
        }
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
            defaultFilename: String(localized: "Ductus history", bundle: .ui, comment: "File name for the exported history")
        ) { result in
            if case .failure(let error) = result {
                Log.error("Could not export history: \(error)")
            }
        }
    }

    private func note(_ text: LocalizedStringKey, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
    }
}

extension SettingsView {
    /// The layout Ductus types and shows, which can differ from the Mac's.
    @ViewBuilder
    var layoutPicker: some View {
        let language = PracticeLanguage(rawValue: practiceLanguage)
        let suggested = language.map(LayoutCatalog.layouts(for:)) ?? []
        let onMac = LayoutCatalog.enabled
        let alternatives = LayoutCatalog.alternatives.filter { entry in !onMac.contains(entry) }
        let shown = Set((onMac + alternatives + suggested).map(\.id))
        // A layout picked from the full list still needs a row so the menu can show it.
        let picked = LayoutCatalog.all.first { $0.id == practiceLayout && !shown.contains($0.id) }
        LabeledContent("Keyboard in Ductus") {
            HStack {
                Picker("Keyboard in Ductus", selection: Binding(
                    get: { practiceLayout },
                    set: { practiceLayout = $0; practiceLayoutAuto = false }
                )) {
                    Text("Same as macOS (\(keyboard.systemLayout?.name ?? "-"))").tag("")
                    if let picked {
                        Text(verbatim: picked.name).tag(picked.id)
                    }
                    if !onMac.isEmpty {
                        Section("On this Mac") {
                            ForEach(onMac) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                    if !alternatives.isEmpty {
                        Section("Alternative layouts") {
                            ForEach(alternatives) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                    if let language, !suggested.isEmpty {
                        Section("For \(language.nativeName)") {
                            ForEach(suggested) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button("Browse All Layouts…") { browsingLayouts = true }
            }
        }
        .sheet(isPresented: $browsingLayouts) {
            LayoutBrowser(selection: practiceLayout) { id in
                practiceLayout = id
                practiceLayoutAuto = false
            }
        }
        if practiceLayoutAuto, let language, let layout = keyboard.layout, let system = keyboard.systemLayout {
            note("Your Mac's layout cannot type \(language.nativeName), so Ductus uses \(layout.name) in its windows. Other apps keep \(system.name).")
        } else {
            note("Types and shows another layout inside Ductus only. Your Mac keeps its own layout in other apps, and nothing needs to be installed.")
        }
    }
}

/// Every Tatoeba author whose sentences are bundled, as the license asks.
struct SentenceAuthorsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<PracticeLanguage> = []
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
                    // Collapsed by default, so each language is one line until you open it.
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(language) },
                        set: { open in if open { expanded.insert(language) } else { expanded.remove(language) } }
                    )) {
                        ForEach(authors, id: \.author) { entry in
                            LabeledContent(entry.author, value: "\(entry.sentences)")
                        }
                    } label: {
                        Button {
                            if expanded.contains(language) { expanded.remove(language) } else { expanded.insert(language) }
                        } label: {
                            Text("\(language.nativeName): \(authors.count) authors")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

/// Every installed layout, grouped by language and searchable, for
/// Settings › Keyboard in Ductus › Browse All Layouts.
struct LayoutBrowser: View {
    let selection: String
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let locale = LanguageState.shared.locale
        let groups = LayoutCatalog.groupedByLanguage(locale: locale).compactMap { group -> (name: String, layouts: [LayoutCatalog.Entry])? in
            guard !query.isEmpty, !group.name.localizedCaseInsensitiveContains(query) else { return group }
            let matches = group.layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : (group.name, matches)
        }
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if groups.isEmpty {
                Text("No layouts match").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.layouts) { entry in
                                Button {
                                    choose(entry.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(verbatim: entry.name)
                                        Spacer()
                                        if entry.id == selection {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 480)
    }
}

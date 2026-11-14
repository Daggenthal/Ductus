import DuctusEngine
import SwiftUI

/// The Study tab: pick a word set, see today's plan, then type each card.
struct StudyView: View {
    @Environment(StudyModel.self) private var study
    @Environment(KeyboardState.self) private var keyboard
    @Environment(PracticeModel.self) private var practice
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.fadeMastered) private var fadeMastered = true
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @AppStorage(SettingsKey.studyShowCharacters) private var showCharacters = true
    @AppStorage(SettingsKey.studyShowPinyin) private var showPinyin = false
    @AppStorage(SettingsKey.studyShowMeaning) private var showMeaning = true
    @AppStorage(SettingsKey.studyNewPerDay) private var newPerDay = 10

    var body: some View {
        let _ = LanguageState.shared.locale  // redraw when the app language changes
        VStack(alignment: .leading, spacing: 24) {
            header
            if let error = study.loadError {
                Text(error).foregroundStyle(.red)
            } else if !LayoutCatalog.canType(.chinese, on: keyboard.layout) {
                Text("Pinyin is typed with Latin letters, which the keyboard Ductus uses now cannot type. Set Keyboard in Ductus to Same as macOS in Settings.")
                    .foregroundStyle(.orange)
            } else if study.session == nil {
                overview
            } else if study.isFinished {
                finished
            } else if let step = study.step {
                card(step)
            }
            Spacer(minLength: 0)
            if study.session != nil, !study.isFinished {
                toggles
            }
            if showKeyboard, let typing = study.typing {
                KeyboardView(
                    keyboard: keyboard,
                    nextCharacter: typing.currentExpected,
                    mastered: fadeMastered ? practice.masteredLetters : [],
                    animatesPresses: false
                )
                .background(ThemedKeyboardBacking())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(32)
        .frame(minWidth: 860, minHeight: showKeyboard ? 720 : 480, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            Picker("Word set", selection: Binding(get: { study.setID }, set: { study.select(setID: $0) })) {
                ForEach(StudySet.catalog, id: \.id) { entry in
                    Text(verbatim: StudySet.title(for: entry.id)).tag(entry.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(study.session != nil && !study.isFinished)
            Stat(title: "New today", value: "\(min(study.startedToday, newPerDay)) / \(newPerDay)")
            Stat(title: "To review", value: "\(study.plan.reviews.count)")
            Stat(title: "Learned", value: "\(study.learnedCount) / \(study.totalCount)")
            Stat(title: "Known", value: "\(study.knownCount)")
            Spacer()
            if study.session != nil, !study.isFinished {
                Button("End") { study.endSession() }
                    .help("Stop this session. Words you already answered are saved.")
            }
        }
    }

    // MARK: - Before and after a session

    private var overview: some View {
        let plan = study.plan
        return VStack(alignment: .leading, spacing: 16) {
            if plan.isEmpty {
                Text("All done for today").font(.title2.weight(.semibold))
                Text("Come back tomorrow for your reviews, or keep going with more new words.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Today: \(plan.new.count) new, \(plan.reviews.count) to review").font(.title2.weight(.semibold))
                Text("New words are typed once with everything shown, then again from memory a few cards later. Words you know well come back less often, and words you miss come back sooner.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if !plan.isEmpty {
                    Button("Start") { study.start() }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                if study.learnedCount < study.totalCount {
                    Button("Keep Going (+\(newPerDay))") { study.keepGoing() }
                        .controlSize(.large)
                }
                if study.knownCount > 0 {
                    Button("Practice Known Words (\(study.knownCount))") { study.practiceKnown() }
                        .controlSize(.large)
                }
            }
            Text("Type the pinyin without tones, and v for ü. Press Return to see the answer if you are stuck.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session done").font(.title2.weight(.semibold))
            HStack(spacing: 28) {
                ForEach(StudyGrade.allCases, id: \.self) { grade in
                    Stat(title: grade.title, value: "\(study.tally[grade] ?? 0)")
                }
            }
            HStack(spacing: 12) {
                Button("Done") { study.endSession() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                if study.learnedCount < study.totalCount {
                    Button("Keep Going (+\(newPerDay))") { study.keepGoing() }
                        .controlSize(.large)
                }
            }
        }
    }

    // MARK: - A card

    private func card(_ step: StudySession.Step) -> some View {
        let word = step.word
        let learning: Bool = if case .learn = step { true } else { false }
        // From memory needs something to recall from.
        let characters = learning || showCharacters || !showMeaning
        let pinyin = learning || showPinyin || study.revealed
        let meaning = learning || showMeaning
        return VStack(spacing: 14) {
            Text(cardLabel(learning: learning))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(study.revealed ? Color.orange : .secondary)
            if characters {
                Text(verbatim: word.native)
                    .font(.system(size: 76 * textScale))
                    .textSelection(.disabled)
            }
            Text(verbatim: pinyin ? word.reading : " ")
                .font(.system(size: 28 * textScale))
                .foregroundStyle(study.revealed && !learning ? Color.orange : .primary)
            if meaning {
                Text(verbatim: word.meaning)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 640)
            }
            if let typing = study.typing {
                DrillText(session: typing, lastKeyWrong: study.lastKeyWrong, fontSize: 34 * textScale)
                    .fixedSize()
                    .padding(.top, 8)
                    .id(study.cardID)
            }
            if let session = study.session {
                ProgressView(value: Double(session.completed), total: Double(session.completed + session.remaining))
                    .frame(maxWidth: 360)
                    .padding(.top, 8)
            }
            if let last = study.lastResult {
                lastLine(last.word, last.grade)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cardLabel(learning: Bool) -> LocalizedStringKey {
        if learning { return "New word" }
        if study.revealed { return "Answer shown" }
        return "From memory"
    }

    private func lastLine(_ word: StudyWord, _ grade: StudyGrade?) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(word.native) \(word.reading)")
            if let grade {
                Text(grade.title).foregroundStyle(grade.color)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var toggles: some View {
        HStack(spacing: 18) {
            Text("When recalling, show:").foregroundStyle(.secondary)
            Toggle("Chinese characters", isOn: $showCharacters)
            Toggle("Pinyin", isOn: $showPinyin)
            Toggle("Meaning", isOn: $showMeaning)
            Spacer()
            Text("Return shows the answer").foregroundStyle(.tertiary)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

extension StudyGrade {
    var title: LocalizedStringKey {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

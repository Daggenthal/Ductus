import Charts
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
    @AppStorage(SettingsKey.studyMode) private var mode = "words"

    var body: some View {
        let _ = LanguageState.shared.locale  // redraw when the app language changes
        VStack(alignment: .leading, spacing: 24) {
            header
            if let error = study.loadError {
                Text(error).foregroundStyle(.red)
            } else if !LayoutCatalog.canType(.chinese, on: keyboard.layout) {
                Text("Pinyin is typed with Latin letters, which the keyboard Ductus uses now cannot type. Set Keyboard in Ductus to Same as macOS in Settings.")
                    .foregroundStyle(.orange)
            } else if mode == "grammar" {
                GrammarStudyView()
            } else if study.session == nil {
                overview
            } else if study.isFinished {
                finished
            } else if let step = study.step {
                card(step)
            }
            Spacer(minLength: 0)
            if mode != "grammar", study.session != nil, !study.isFinished {
                toggles
            }
            if showKeyboard, let typing = study.typing {
                KeyboardView(
                    keyboard: keyboard,
                    // No key hints when recalling: they would give the answer away.
                    nextCharacter: study.step.map(hidesAnswer) == true || study.candidates != nil ? nil : typing.currentExpected,
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
            Picker("Study", selection: Binding(get: { mode }, set: { new in
                study.endSession()
                study.endGrammar()
                mode = new
            })) {
                Text("Words").tag("words")
                Text("Grammar").tag("grammar")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if mode != "grammar" {
                Stat(title: "New today", value: "\(min(study.startedToday, newPerDay)) / \(newPerDay)")
                Stat(title: "To review", value: "\(study.plan.reviews.count)")
                Stat(title: "Learned", value: "\(study.learnedCount) / \(study.totalCount)")
                Stat(title: "Known", value: "\(study.knownCount)")
            }
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
        let characters = learning || showCharacters || !showMeaning || study.awaitingNext
        // Once answered, the whole card shows until Return.
        let pinyin = learning || showPinyin || study.revealed || study.awaitingNext
        let meaning = learning || showMeaning || study.awaitingNext
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
                if hidesAnswer(step) {
                    // From memory: the letters still to type stay hidden.
                    MaskedAnswer(session: typing, lastKeyWrong: study.lastKeyWrong, fontSize: 34 * textScale)
                        .padding(.top, 8)
                        .id(study.cardID)
                } else {
                    DrillText(session: typing, lastKeyWrong: study.lastKeyWrong, fontSize: 34 * textScale)
                        .fixedSize()
                        .padding(.top, 8)
                        .id(study.cardID)
                }
            }
            if let candidates = study.candidates {
                CandidateBar(candidates: candidates, wrong: study.lastKeyWrong, fontSize: 30 * textScale,
                             answer: study.revealed ? candidates.firstIndex(of: word.native) : nil)
                Text("Press the number of the right characters (space for 1)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if study.awaitingNext {
                HStack(spacing: 10) {
                    if let grade = study.answeredGrade {
                        Text(grade.title).font(.title3.weight(.semibold)).foregroundStyle(grade.color)
                    }
                    Text("Press Return for the next card").foregroundStyle(.secondary)
                }
            }
            Button("I Know This Word") { study.markKnown() }
                .help("Skip this word. It comes back for review in about six months. Undo it in History with Study Again.")
                .focusable(false)
            if let session = study.session {
                ProgressView(value: Double(session.completed), total: Double(session.completed + session.remaining))
                    .frame(maxWidth: 360)
                    .padding(.top, 8)
            }
            if let last = study.lastResult, !study.awaitingNext {
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

    /// Recall cards hide the pinyin to type until it is typed, shown (Return) or finished.
    private func hidesAnswer(_ step: StudySession.Step) -> Bool {
        guard case .recall = step else { return false }
        return !study.revealed && !study.awaitingNext && !showPinyin
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

/// History's Study card: answers per day, what is due this week, and the
/// words studied most recently, where a word marked as known can be put back.
struct StudyHistoryCard: View {
    @Environment(StudyModel.self) private var study

    var body: some View {
        if let set = study.wordSet, !study.progress.cards.isEmpty {
            let progress = study.progress
            let days = Self.lastDays(30)
            let forecast = progress.dueForecast(in: set, days: 7, now: .now)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Study").font(.headline)
                    Text(verbatim: StudySet.title(for: set.id)).foregroundStyle(.secondary)
                }
                HStack(spacing: 28) {
                    stat("Learned", "\(study.learnedCount) / \(study.totalCount)")
                    stat("Known", "\(study.knownCount)")
                    stat("Due this week", "\(forecast.reduce(0, +))")
                }
                Chart {
                    ForEach(days, id: \.self) { day in
                        BarMark(
                            x: .value("Day", day, unit: .day),
                            y: .value("Answers", progress.answersPerDay[StudyProgress.day(day)] ?? 0)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                .chartYAxisLabel("Answers per day")
                .frame(height: 120)
                Text("Recently studied").font(.subheadline.weight(.semibold))
                VStack(spacing: 0) {
                    ForEach(progress.recent(in: set, limit: 25), id: \.word.id) { item in
                        row(item.word, item.card)
                        Divider()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func row(_ word: StudyWord, _ card: CardState) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: word.native).font(.title3).frame(minWidth: 60, alignment: .leading)
            Text(verbatim: word.reading).foregroundStyle(.secondary).frame(minWidth: 90, alignment: .leading)
            Text(verbatim: word.meaning).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if card.markedKnown == true {
                Text("Marked as known").font(.caption).foregroundStyle(.green)
            } else {
                Text("Next \(card.due.formatted(.dateTime.month(.abbreviated).day().locale(LanguageState.shared.locale)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Study Again") { study.reset(word) }
                .controlSize(.small)
                .help("Forget this word, so it comes back as a new word.")
        }
        .padding(.vertical, 6)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    private static func lastDays(_ count: Int) -> [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<count).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }
}


/// The answer while recalling: typed letters shown, the rest as dots.
struct MaskedAnswer: View {
    let session: TypingSession
    let lastKeyWrong: Bool
    var fontSize: CGFloat = 34

    var body: some View {
        let typed = String(session.text[..<session.position])
        let rest = String(session.text[session.position...].map { $0 == " " ? Character(" ") : Character("·") })
        (Text(verbatim: typed).foregroundStyle(.secondary)
            + Text(verbatim: rest).foregroundStyle(lastKeyWrong ? Color.red : .primary))
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
    }
}

/// The numbered choices after the pinyin, like an input method's candidate bar.
struct CandidateBar: View {
    let candidates: [String]
    let wrong: Bool
    var fontSize: CGFloat = 30
    /// The right choice, shown after Return.
    var answer: Int?

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, word in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Text(verbatim: word).font(.system(size: fontSize))
                }
                .padding(.horizontal, 4)
                .background(index == answer ? Color.orange.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(wrong ? Color.red.opacity(0.6) : .clear))
    }
}

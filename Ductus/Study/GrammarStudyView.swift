import DuctusEngine
import SwiftUI

/// Study › Grammar: the HSK grammar points for the chosen level, each with
/// example sentences that were checked by hand, to read and to type.
struct GrammarStudyView: View {
    @Environment(StudyModel.self) private var study
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @AppStorage(SettingsKey.studyShowPinyin) private var showPinyin = false
    @State private var selectedID: String?

    var body: some View {
        if let grammar = study.grammar {
            HStack(alignment: .top, spacing: 20) {
                list(grammar)
                    .frame(width: 300)
                Divider()
                Group {
                    if let point = grammar.points.first(where: { $0.id == selectedID }) ?? grammar.points.first {
                        detail(point, hasExamples: grammar.hasExamples)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            Text("No grammar points for this word set.").foregroundStyle(.secondary)
        }
    }

    private func list(_ grammar: GrammarSet) -> some View {
        List(selection: $selectedID) {
            ForEach(grammar.points) { point in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: point.english.isEmpty ? point.title : point.english)
                            .font(.body.weight(.medium))
                        Text(verbatim: "\(point.title) · \(point.items)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if study.practicedPoints[point.id] != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityLabel(Text("Practiced"))
                    } else if !point.examples.isEmpty {
                        Text(verbatim: "\(point.examples.count)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .tag(point.id)
            }
        }
        .listStyle(.sidebar)
        .disabled(study.grammarPoint != nil && !study.grammarDone)
    }

    @ViewBuilder
    private func detail(_ point: GrammarSet.Point, hasExamples: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: point.english.isEmpty ? point.title : point.english).font(.title2.weight(.semibold))
                Text(verbatim: "\(point.section) \(point.title)").foregroundStyle(.secondary)
                Text(Self.highlighted(point.items, words: point.markers)).font(.title3)
            }
            HStack(spacing: 12) {
                if !point.examples.isEmpty, study.grammarPoint == nil || study.grammarDone {
                    Button("Practice") { study.practice(point) }
                        .keyboardShortcut(.defaultAction)
                }
                if study.grammarPoint != nil, !study.grammarDone {
                    Button("End") { study.endGrammar() }
                }
                Link("Look It Up", destination: Self.lookUp(point))
                    .help("Search the Chinese Grammar Wiki for this point")
                Toggle("Pinyin", isOn: $showPinyin).toggleStyle(.checkbox)
            }
            if study.grammarPoint?.id == point.id {
                practiceCard
            } else if point.examples.isEmpty {
                Text(Self.noExamplesNote(levelReviewed: hasExamples))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(point.examples) { example in
                            exampleRow(example)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func exampleRow(_ example: GrammarSet.Example) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SpokenText.attributed(example.text, speaker: study.speaker, base: Self.highlighted(example)))
                    .font(.system(size: 22 * textScale))
                if example.isAIWritten { aiBadge }
                Button {
                    study.speaker.speak(example.text)
                } label: {
                    Image(systemName: study.speaker.isSpeaking(example.text) ? "stop.fill" : "speaker.wave.2.fill")  // not UI
                }
                .buttonStyle(.borderless)
                .help("Read aloud")
            }
            if showPinyin {
                Text(verbatim: example.pinyin).foregroundStyle(.secondary)
            }
            Text(verbatim: example.english).font(.callout).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var practiceCard: some View {
        if study.grammarDone {
            VStack(alignment: .leading, spacing: 10) {
                Text("All examples typed").font(.title3.weight(.semibold))
                Button("Again") { if let point = study.grammarPoint { study.practice(point) } }
            }
        } else if let example = study.currentExample, let point = study.grammarPoint, let typing = study.typing {
            VStack(spacing: 12) {
                Text(verbatim: "\(study.exampleIndex + 1) / \(point.examples.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(SpokenText.attributed(example.text, speaker: study.speaker, base: Self.highlighted(example)))
                    .font(.system(size: 40 * textScale))
                if example.isAIWritten { aiBadge }
                SpeakButton(text: example.text, speaker: study.speaker)
                Text(verbatim: showPinyin ? example.pinyin : " ").font(.system(size: 20 * textScale)).foregroundStyle(.secondary)
                Text(verbatim: example.english).font(.title3).foregroundStyle(.secondary)
                DrillText(session: typing, lastKeyWrong: study.lastKeyWrong, fontSize: 28 * textScale)
                    .fixedSize()
                    .id(study.cardID)
                if study.awaitingNext {
                    Text("Press Return for the next sentence").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private static func noExamplesNote(levelReviewed: Bool) -> LocalizedStringKey {
        if levelReviewed {
            return "No example sentences for this point yet. Every example in Ductus is checked by hand, and none of the available sentences showed this point clearly enough."
        }
        return "Example sentences for this level are still being checked by hand. The grammar points are listed so you can look them up."
    }

    /// Marks sentences written by AI where no human sentence fit.
    private var aiBadge: some View {
        Text("AI-written")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(.secondary)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
            .help("Written by AI because no human-written sentence showed this point. Checked by a second model (DeepSeek).")
    }

    /// The sentence with the grammar point's words in the accent color.
    static func highlighted(_ example: GrammarSet.Example) -> AttributedString {
        var result = AttributedString()
        for (index, character) in example.text.enumerated() {
            var piece = AttributedString(String(character))
            if example.highlights.contains(where: { $0.contains(index) }) {
                piece.foregroundColor = .accentColor
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            result += piece
        }
        return result
    }

    /// The point's items with its key words in the accent color.
    static func highlighted(_ text: String, words: [String]) -> AttributedString {
        var result = AttributedString(text)
        for word in words where !word.isEmpty {
            var searchRange = result.startIndex..<result.endIndex
            while let found = result[searchRange].range(of: word) {
                result[found].foregroundColor = .accentColor
                searchRange = found.upperBound..<result.endIndex
            }
        }
        return result
    }

    /// The Chinese Grammar Wiki's search for the point's words (or its title).
    static func lookUp(_ point: GrammarSet.Point) -> URL {
        let first = point.items.split(whereSeparator: { "、，".contains($0) }).first.map(String.init) ?? point.title
        let query = first.contains(where: { $0.isLetter && !$0.isASCII }) && first.count <= 6 ? first : point.title
        var components = URLComponents(string: "https://resources.allsetlearning.com/chinese/grammar/index.php")!
        components.queryItems = [URLQueryItem(name: "search", value: query)]
        return components.url!
    }
}

import DuctusEngine
import SwiftUI

/// Race against your own best: common words, live speed, a ghost at your
/// best pace, and the keys that cost you the most.
struct RaceView: View {
    @Environment(RaceModel.self) private var race
    @Environment(PracticeModel.self) private var practice
    @Environment(KeyboardState.self) private var keyboard
    @Environment(AppUIState.self) private var ui
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true

    var body: some View {
        @Bindable var race = race
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Picker("Length", selection: $race.timeLimit) {
                    ForEach(RaceModel.timeLimitOptions, id: \.self) { Text("\($0 / 60) min").tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker("Letters", selection: $race.allLetters) {
                    Text("All letters").tag(true)
                    Text("Unlocked only").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Button("New Race") { race.newRace() }
                    .help("⌘N")
            }
            .labelsHidden()
            .disabled(race.isRunning)

            if let result = race.result {
                RaceResults(result: result, bestWPM: race.bestWPM, onAgain: race.newRace) {
                    ui.tab = .practice
                }
            } else if let session = race.session {
                LiveRace(session: session, startedAt: race.startedAt, timeLimit: race.timeLimit, bestWPM: race.bestWPM)
                RaceTextView(session: session, lastKeyWrong: race.lastKeyWrong)
                    .id(race.raceID)
                if race.startedAt == nil {
                    Text("The clock starts on your first key.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if showKeyboard, race.result == nil {
                KeyboardView(
                    keyboard: keyboard,
                    nextCharacter: race.session?.currentExpected,
                    unlockedLetters: race.allLetters ? nil : practice.unlockedLetters,
                    animatesPresses: false
                )
                .background(ThemedKeyboardBacking())
                .frame(maxWidth: .infinity)
            }

            RaceRecord(races: practice.raceHistory.filter {
                $0.timeLimit == race.timeLimit && $0.allLetters == race.allLetters
            })
        }
        .padding(32)
        .frame(minWidth: 760, minHeight: showKeyboard ? 720 : 480, alignment: .topLeading)
        .onAppear { if race.session == nil { race.newRace() } }
    }
}

/// Countdown, live speed and accuracy, and the You vs Best track.
private struct LiveRace: View {
    let session: TypingSession
    let startedAt: Date?
    let timeLimit: Int
    let bestWPM: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: startedAt == nil)) { context in
            let elapsed = min(Double(timeLimit), startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
            let remaining = Double(timeLimit) - elapsed
            let typed = Double(session.position)
            let wpm = elapsed > 1 ? typed / 5 / (elapsed / 60) : nil
            // Bars are measured against the characters your best would type in this length.
            let bestTotal = bestWPM.map { $0 * 5 * Double(timeLimit) / 60 }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 28) {
                    Stat(title: "Time left", value: Self.clock(remaining))
                    Stat(title: "Speed", value: wpm.map { String(format: "%.0f WPM", $0) } ?? "-")
                    Stat(title: "Accuracy", value: session.liveAccuracy.map { String(format: "%.0f%%", $0 * 100) } ?? "-")
                }
                // Bars appear once the race starts.
                if startedAt != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let bestTotal, let bestWPM, bestTotal > 0 {
                        TrackBar(label: "You", progress: min(1, typed / bestTotal), color: .accentColor)
                        TrackBar(label: String(format: "Best %.0f", bestWPM), progress: elapsed / Double(timeLimit),
                                 color: .secondary.opacity(0.5))
                    } else {
                        TrackBar(label: "Time", progress: elapsed / Double(timeLimit), color: .accentColor)
                        Text("Finish a race to set a best to race against.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                }
            }
        }
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct TrackBar: View {
    let label: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(color)
                        .frame(width: max(8, geometry.size.width * progress))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct RaceResults: View {
    let result: RaceModel.Result
    let bestWPM: Double?
    let onAgain: () -> Void
    let onPractice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%.0f", result.wpm))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                Text("WPM").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                if result.isNewBest {
                    Text("New best!")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 28) {
                Stat(title: "Accuracy", value: String(format: "%.0f%%", result.accuracy * 100))
                Stat(title: "Length", value: "\(Int(result.duration) / 60) min")
                Stat(title: "Characters", value: "\(result.characters)")
                Stat(title: "Errors", value: "\(result.errors)")
                if let bestWPM, !result.isNewBest {
                    Stat(title: "Your best", value: String(format: "%.0f WPM", bestWPM))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Keys that cost you the most").font(.headline)
                if result.worstKeys.isEmpty {
                    Text("Nothing stood out. Clean race.")
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            Text("Key"); Text("Misses"); Text("Average time")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ForEach(result.worstKeys, id: \.key) { key in
                            GridRow {
                                Text(key.key == " " ? "Space" : key.key.uppercased())
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                Text("\(key.misses) of \(key.attempts)")
                                Text(key.averageLatency.map { String(format: "%.0f ms", $0 * 1000) } ?? "-")
                            }
                            .font(.callout.monospacedDigit())
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Race Again", action: onAgain)
                    .keyboardShortcut(.defaultAction)
                Button("Practice These Keys", action: onPractice)
                    .disabled(result.worstKeys.isEmpty)
            }
            Text("Race keystrokes count toward your key stats, so practice drills will target these keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Best, recent average and count for races with the current letter setting.
private struct RaceRecord: View {
    let races: [RaceEntry]

    var body: some View {
        if !races.isEmpty {
            let recent = races.suffix(10)
            HStack(spacing: 28) {
                Stat(title: "Best race", value: String(format: "%.0f WPM", races.map(\.wpm).max() ?? 0))
                Stat(title: "Last 10 average", value: String(format: "%.0f WPM", recent.map(\.wpm).reduce(0, +) / Double(recent.count)))
                Stat(title: "Races", value: "\(races.count)")
            }
            .padding(.top, 4)
        }
    }
}

/// The keyboard's themed backing outside the practice views.
struct ThemedKeyboardBacking: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape.fill(KeyboardPalette(colorScheme).backing)
            .background(.ultraThinMaterial, in: shape)
    }
}

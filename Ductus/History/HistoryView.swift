import Charts
import DuctusEngine
import SwiftUI

/// Progress over time for the current keyboard layout.
struct HistoryView: View {
    @Environment(PracticeModel.self) private var practice
    @Environment(KeyboardState.self) private var keyboard
    @State private var range: ChartRange = .days
    @State private var trendLetter: String?

    var body: some View {
        let drills = practice.drillHistory
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.largeTitle.weight(.semibold))
                    Text(practice.layoutName).foregroundStyle(.secondary)
                }

                if drills.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Finish a drill and your progress shows up here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    TotalsRow(totals: HistoryMath.totals(drills))
                    speedAndAccuracy(drills)
                    heatmap
                    keyLists
                    keyTrend
                    unlockTimeline
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Speed and accuracy

    private enum ChartRange: String, CaseIterable, Identifiable {
        case days = "By day"
        case drills = "Last 50 drills"
        var id: String { rawValue }
    }

    private func speedAndAccuracy(_ drills: [DrillRecord]) -> some View {
        let points: [(label: String, wpm: Double?, accuracy: Double)]
        switch range {
        case .days:
            points = HistoryMath.daily(drills).map {
                ($0.day.formatted(.dateTime.month(.abbreviated).day()), $0.wpm, $0.accuracy)
            }
        case .drills:
            let recent = drills.suffix(50)
            let offset = drills.count - recent.count
            points = recent.enumerated().map { ("Drill \(offset + $0.offset + 1)", $0.element.wpm, $0.element.accuracy) }
        }
        let wpmPoints = points.enumerated().compactMap { i, p in p.wpm.map { MetricPoint(index: i, label: p.label, value: $0) } }
        let accuracyPoints = points.enumerated().map { i, p in MetricPoint(index: i, label: p.label, value: p.accuracy * 100) }

        return Card {
            HStack {
                Text("Speed and accuracy").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            // Two charts, never one chart with two y-axes.
            HStack(alignment: .top, spacing: 24) {
                MetricChart(title: "Speed", unit: "WPM", points: wpmPoints, format: "%.0f WPM")
                MetricChart(title: "Accuracy", unit: "%", points: accuracyPoints, format: "%.1f%%",
                            domain: max(0, (accuracyPoints.map(\.value).min() ?? 100) - 5)...100)
            }
        }
    }

    // MARK: - Heatmap

    private var heatmap: some View {
        let ranked = practice.trainer?.rankedKeys() ?? []
        let heat = Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, min(1, $0.weakness / 1.5)) })
        return Card {
            HStack {
                Text("Keys that need work").font(.headline)
                Spacer()
                HeatLegend()
            }
            KeyboardView(
                keyboard: keyboard,
                unlockedLetters: practice.unlockedLetters,
                showPhysicalLabels: false,
                heat: heat,
                unit: 36
            )
            .background(KeyboardBacking())
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Key lists

    private var keyLists: some View {
        let ranked = practice.trainer?.rankedKeys() ?? []
        let minSamples = practice.trainer?.scorer.config.minSamples ?? 20
        let strongest = ranked.reversed().filter { $0.stats.attempts >= minSamples }
        let pairs = practice.trainer?.rankedBigrams() ?? []
        return HStack(alignment: .top, spacing: 20) {
            Card {
                Text("Work on these").font(.headline)
                KeyTable(rows: ranked.prefix(6).map { (String($0.key).uppercased(), $0.stats) })
            }
            Card {
                Text("Slowest letter pairs").font(.headline)
                KeyTable(rows: pairs.prefix(6).map { ($0.bigram.description, $0.stats) })
            }
            Card {
                Text("Strongest keys").font(.headline)
                KeyTable(rows: strongest.prefix(6).map { (String($0.key).uppercased(), $0.stats) })
            }
        }
    }

    // MARK: - Per-key trend

    private var keyTrend: some View {
        let entries = practice.profile?.keyDays ?? []
        let letters = Set(entries.map(\.letter)).sorted()
        let selected = trendLetter ?? practice.focusKey.map(String.init) ?? letters.first
        let points = entries
            .filter { $0.letter == selected && $0.wpm != nil }
            .sorted { $0.day < $1.day }
            .enumerated()
            .map { MetricPoint(index: $0.offset, label: $0.element.day.formatted(.dateTime.month(.abbreviated).day()), value: $0.element.wpm!) }

        return Card {
            HStack {
                Text("One key over time").font(.headline)
                Spacer()
                Picker("Key", selection: Binding(get: { selected ?? "" }, set: { trendLetter = $0 })) {
                    ForEach(letters, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if points.count < 2 {
                Text("Practice on a couple of different days to see this key's trend.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                MetricChart(title: "Speed of \(selected?.uppercased() ?? "")", unit: "WPM", points: points, format: "%.0f WPM")
            }
        }
    }

    // MARK: - Unlock timeline

    private var unlockTimeline: some View {
        let unlockDates = Dictionary(
            (practice.profile?.unlocks ?? []).map { ($0.letter, $0.date) },
            uniquingKeysWith: { first, _ in first }
        )
        let curriculum = practice.trainer?.curriculum
        return Card {
            Text("Unlocked letters").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array((curriculum?.order ?? []).enumerated()), id: \.offset) { index, letter in
                    let unlocked = index < (curriculum?.unlockedCount ?? 0)
                    VStack(spacing: 2) {
                        Text(letter.uppercased())
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(unlocked ? .primary : .tertiary)
                        Text(unlocked
                             ? unlockDates[String(letter)].map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Start"
                             : "Locked")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(unlocked ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Pieces

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TotalsRow: View {
    let totals: HistoryTotals

    var body: some View {
        HStack(spacing: 12) {
            tile("Practice time", Self.duration(totals.practiceTime))
            tile("Drills", "\(totals.drills)")
            tile("Characters", totals.characters.formatted())
            tile("Days practiced", "\(totals.daysPracticed)")
            tile("Streak", totals.currentStreak == 1 ? "1 day" : "\(totals.currentStreak) days")
            tile("Best drill", totals.bestWPM.map { String(format: "%.0f WPM", $0) } ?? "-")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}

private struct MetricPoint: Identifiable {
    let index: Int
    let label: String
    let value: Double
    var id: Int { index }
}

/// Single-series line chart with a hover readout.
private struct MetricChart: View {
    let title: String
    let unit: String
    let points: [MetricPoint]
    let format: String
    var domain: ClosedRange<Double>?

    @State private var selected: Int?

    var body: some View {
        let hovered = selected.flatMap { index in points.min { abs($0.index - index) < abs($1.index - index) } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                // Readout: the hovered point, or the latest one.
                if let shown = hovered ?? points.last {
                    Text("\(shown.label): \(String(format: format, shown.value))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Index", point.index), y: .value(unit, point.value))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if points.count <= 40 {
                        PointMark(x: .value("Index", point.index), y: .value(unit, point.value))
                            .symbolSize(30)
                    }
                }
                if let hovered {
                    RuleMark(x: .value("Index", hovered.index))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Index", hovered.index), y: .value(unit, hovered.value))
                        .symbolSize(70)
                }
            }
            .foregroundStyle(Color.accentColor)
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel {
                        if let i = value.as(Int.self), let point = points.first(where: { $0.index == i }) {
                            Text(point.label)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel()
                }
            }
            .modifier(OptionalYDomain(domain: domain))
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OptionalYDomain: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}

/// Key, WPM, accuracy and attempts in a small table.
private struct KeyTable: View {
    let rows: [(name: String, stats: KeyStats)]

    var body: some View {
        if rows.isEmpty {
            Text("Not enough practice yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Key"); Text("Speed"); Text("Accuracy"); Text("Tries")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(rows.indices, id: \.self) { i in
                    let stats = rows[i].stats
                    GridRow {
                        Text(rows[i].name).font(.system(.body, design: .monospaced).weight(.semibold))
                        Text(stats.wpm.map { String(format: "%.0f WPM", $0) } ?? "-")
                        Text(stats.accuracy.value.map { String(format: "%.0f%%", $0 * 100) } ?? "-")
                        Text("\(stats.attempts)").foregroundStyle(.secondary)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
    }
}

/// "Strong to needs work" scale for the heatmap.
private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Strong").font(.caption).foregroundStyle(.secondary)
            LinearGradient(
                colors: [KeyboardPalette.heat.opacity(0.12), KeyboardPalette.heat.opacity(0.8)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 80, height: 8)
            .clipShape(Capsule())
            Text("Needs work").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The keyboard's themed backing, outside the practice views.
private struct KeyboardBacking: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape.fill(KeyboardPalette(colorScheme).backing)
            .background(.ultraThinMaterial, in: shape)
    }
}

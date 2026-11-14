import DuctusEngine
import SwiftUI

/// Compact stats row for the floating keyboard panel: live speed and accuracy,
/// the last drill, the focus key and unlock progress.
struct FloatingStatsBar: View {
    let practice: PracticeModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = LanguageState.shared.locale  // redraw when the app language changes
        let palette = KeyboardPalette(colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Item(title: "Now", value: wpm(practice.session?.liveWPM), detail: percent(practice.session?.liveAccuracy))
            Item(title: "Last drill", value: wpm(practice.lastSummary?.wpm), detail: percent(practice.lastSummary?.accuracy))
            if practice.isWarmUp {
                Item(title: "Focus", value: String(localized: "Warm-up", bundle: .ui), detail: "")
            } else if let focus = practice.focusKey {
                Item(title: "Focus", value: focus.uppercased(), detail: "")
            }
            Spacer(minLength: 0)
            if let curriculum = practice.trainer?.curriculum {
                Item(
                    title: "Unlocked",
                    value: "\(curriculum.unlockedCount)/\(curriculum.order.count)",
                    detail: curriculum.nextToUnlock.map { "next \($0.uppercased())" } ?? ""
                )
            }
        }
        .foregroundStyle(palette.text)
        .environment(\.keyboardPaletteSecondary, palette.secondaryText)
    }

    private func wpm(_ value: Double?) -> String {
        value.map { String(format: "%.0f WPM", $0) } ?? "-"
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? "-"
    }

    private struct Item: View {
        let title: LocalizedStringKey
        let value: String
        let detail: String
        @Environment(\.keyboardPaletteSecondary) private var secondary

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondary.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, design: .rounded).monospacedDigit())
                            .foregroundStyle(secondary)
                    }
                }
            }
        }
    }
}

private struct KeyboardPaletteSecondaryKey: EnvironmentKey {
    static let defaultValue = Color.secondary
}

private extension EnvironmentValues {
    var keyboardPaletteSecondary: Color {
        get { self[KeyboardPaletteSecondaryKey.self] }
        set { self[KeyboardPaletteSecondaryKey.self] = newValue }
    }
}

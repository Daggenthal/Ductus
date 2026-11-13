import SwiftUI

/// The keyboard wired to practice state, with its dark rounded backing.
/// Used both docked in the practice window and in the floating panel.
struct PracticeKeyboard: View {
    let keyboard: KeyboardState
    let practice: PracticeModel
    /// Show the one-line drill text right above the keys.
    var showsDrill = false
    /// Show the compact stats row at the top.
    var showsStats = false
    /// Buttons for the top-right corner (the floating panel's Dock and Close).
    var controls: AnyView?
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            if showsStats || controls != nil {
                HStack(alignment: .top, spacing: 12) {
                    if showsStats {
                        FloatingStatsBar(practice: practice)
                    } else {
                        Spacer()
                    }
                    if let controls { controls }
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.top, showsStats ? 12 : 8)
            }
            if showsDrill, let session = practice.session {
                DrillStrip(session: session, lastKeyWrong: practice.lastKeyWrong)
                    .id(practice.drillID)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            KeyboardView(
                keyboard: keyboard,
                nextCharacter: practice.nextCharacter,
                unlockedLetters: practice.unlockedLetters,
                showPhysicalLabels: showPhysicalLabels
            )
        }
        .background(KeyboardPalette(colorScheme).backing, in: shape)
        .background(.ultraThinMaterial, in: shape)
    }
}

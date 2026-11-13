import SwiftUI

/// The keyboard wired to practice state, with its dark rounded backing.
/// Used both docked in the practice window and in the floating panel.
struct PracticeKeyboard: View {
    let keyboard: KeyboardState
    let practice: PracticeModel
    /// Show the one-line drill text right above the keys.
    var showsDrill = false
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
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
        .background(.black.opacity(0.55), in: shape)
        .background(.ultraThinMaterial, in: shape)
    }
}

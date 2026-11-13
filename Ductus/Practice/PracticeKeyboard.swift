import SwiftUI

/// The keyboard wired to practice state, with its dark rounded backing.
/// Used both docked in the practice window and in the floating panel.
struct PracticeKeyboard: View {
    let keyboard: KeyboardState
    let practice: PracticeModel
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        KeyboardView(
            keyboard: keyboard,
            nextCharacter: practice.nextCharacter,
            unlockedLetters: practice.unlockedLetters,
            showPhysicalLabels: showPhysicalLabels
        )
        .background(.black.opacity(0.55), in: shape)
        .background(.ultraThinMaterial, in: shape)
    }
}

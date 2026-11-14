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
    /// Buttons for the top-left corner (the floating panel's Dock button).
    var controls: AnyView?
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true
    @AppStorage(SettingsKey.fadeMastered) private var fadeMastered = true
    @AppStorage(SettingsKey.textScale) private var textScale = 1.0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            if showsStats || controls != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let controls { controls }
                    if showsStats {
                        FloatingStatsBar(practice: practice)
                    } else {
                        Spacer()
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 16)
                .padding(.top, showsStats ? 12 : 8)
            }
            if showsDrill, let session = practice.session, let gloss = practice.gloss,
               practice.language == .korean {
                HangulText(session: session, gloss: gloss, lastKeyWrong: practice.lastKeyWrong,
                           fontSize: 26 * textScale, style: .strip(anchor: 0.35))
                    .id(practice.drillID)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            } else if showsDrill, let session = practice.session {
                if let gloss = practice.gloss {
                    GlossBar(gloss: gloss, position: session.position, fontSize: 28 * textScale, before: 1, after: 2)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                DrillStrip(session: session, lastKeyWrong: practice.lastKeyWrong, fontSize: 22 * textScale)
                    .id(practice.drillID)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            KeyboardView(
                keyboard: keyboard,
                nextCharacter: practice.nextCharacter,
                unlockedLetters: practice.unlockedLetters,
                showPhysicalLabels: showPhysicalLabels,
                mastered: fadeMastered ? practice.masteredLetters : []
            )
        }
        .background(KeyboardPalette(colorScheme).backing, in: shape)
        .background(.ultraThinMaterial, in: shape)
    }
}

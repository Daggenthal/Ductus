import SwiftUI

/// On-screen keyboard drawn from the active layout.
///
/// - Pressed keys light up.
/// - The key for the next character in the drill gets an outline.
/// - Letters not unlocked yet are dimmed.
/// - Optionally, each key shows a faint second label with what is printed on
///   the physical keycap (QWERTY), when it differs from the main label.
/// - While Command is held, labels switch to the Command map (QWERTY on
///   "Dvorak - QWERTY ⌘") and the shortcut keys (Z X C V) glow soft yellow.
struct KeyboardView: View {
    let keyboard: KeyboardState
    var nextCharacter: Character?
    var unlockedLetters: Set<Character>?
    var showPhysicalLabels = true
    /// Heatmap: 0 (fine) to 1 (weakest) per letter. Tints keys in one hue.
    var heat: [Character: Double]?
    /// Soft press animation. Off for races, where it smears at high speed.
    var animatesPresses = true
    var unit: CGFloat = 40

    private let spacing: CGFloat = 4

    var body: some View {
        let shortcutCodes = keyboard.commandHeld ? keyboard.shortcutKeyCodes : []
        let nextCode = nextCharacter.flatMap { keyboard.keyCode(for: Character($0.lowercased())) }

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(KeyboardGeometry.ansi.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { key in
                        KeyCap(
                            label: label(for: key),
                            physicalLabel: physicalLabel(for: key),
                            width: unit * key.width + spacing * (key.width - 1),
                            height: unit,
                            isPressed: keyboard.pressed.contains(key.code),
                            isNext: key.code == nextCode,
                            isShortcut: shortcutCodes.contains(key.code),
                            isDimmed: isLocked(key),
                            heat: heatValue(for: key),
                            scalesOnPress: animatesPresses
                        )
                    }
                }
            }
        }
        .padding(spacing * 3)
        .animation(animatesPresses ? .easeOut(duration: 0.08) : nil, value: keyboard.pressed)
        .animation(.easeInOut(duration: 0.15), value: keyboard.commandHeld)
    }

    private func label(for key: KeyboardGeometry.Key) -> String {
        if let fixed = key.fixedLabel { return fixed }
        let character = keyboard.layout?.character(for: key.code, commandHeld: keyboard.commandHeld) ?? ""
        return character.uppercased()
    }

    /// The keycap's printed letter, only when it differs from the main label.
    private func physicalLabel(for key: KeyboardGeometry.Key) -> String? {
        guard showPhysicalLabels, key.isCharacterKey,
              let printed = keyboard.physicalLayout?.character(for: key.code)?.uppercased()
        else { return nil }
        return printed == label(for: key) ? nil : printed
    }

    private func heatValue(for key: KeyboardGeometry.Key) -> Double? {
        guard let heat, key.isCharacterKey,
              let label = keyboard.layout?.character(for: key.code), label.count == 1
        else { return nil }
        return heat[Character(label.lowercased())]
    }

    private func isLocked(_ key: KeyboardGeometry.Key) -> Bool {
        guard let unlockedLetters, !keyboard.commandHeld, key.isCharacterKey,
              let label = keyboard.layout?.character(for: key.code), label.count == 1,
              let letter = label.first, letter.isLetter
        else { return false }
        return !unlockedLetters.contains(Character(label.lowercased()))
    }
}

private struct KeyCap: View {
    let label: String
    let physicalLabel: String?
    let width: CGFloat
    let height: CGFloat
    let isPressed: Bool
    let isNext: Bool
    let isShortcut: Bool
    let isDimmed: Bool
    var heat: Double?
    var scalesOnPress = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = KeyboardPalette(colorScheme)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(label)
            .font(.system(size: label.count > 1 ? 11 : 16, weight: .medium, design: .rounded))
            .foregroundStyle(isPressed ? palette.pressedLabel : isDimmed ? palette.dimmedLabel : palette.label)
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if let physicalLabel {
                    Text(physicalLabel)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(isPressed ? palette.pressedLabel.opacity(0.6) : palette.physicalLabel)
                        .padding(.trailing, 4)
                        .padding(.bottom, 2)
                }
            }
            .background(shape.fill(fill(palette)))
            .overlay(shape.strokeBorder(stroke(palette), lineWidth: isNext ? 2 : 1))
            .shadow(color: isShortcut ? palette.shortcutGlow : .clear, radius: 8)
            .scaleEffect(isPressed && scalesOnPress ? 0.94 : 1)
    }

    private func fill(_ palette: KeyboardPalette) -> Color {
        if isPressed { return Color.accentColor.opacity(0.85) }
        if isShortcut { return palette.shortcutFill }
        if let heat { return KeyboardPalette.heat.opacity(0.12 + 0.68 * min(1, max(0, heat))) }
        return palette.keyFill
    }

    private func stroke(_ palette: KeyboardPalette) -> Color {
        if isNext { return Color.accentColor }
        if isShortcut { return palette.shortcutStroke }
        return palette.keyStroke
    }
}

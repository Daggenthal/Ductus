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
                            isDimmed: isLocked(key)
                        )
                    }
                }
            }
        }
        .padding(spacing * 3)
        .animation(.easeOut(duration: 0.08), value: keyboard.pressed)
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

    static let shortcutGlow = Color(red: 1.0, green: 0.84, blue: 0.4)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(label)
            .font(.system(size: label.count > 1 ? 11 : 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(isDimmed ? 0.25 : 0.9))
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if let physicalLabel {
                    Text(physicalLabel)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.trailing, 4)
                        .padding(.bottom, 2)
                }
            }
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: isNext ? 2 : 1))
            .shadow(color: isShortcut ? Self.shortcutGlow.opacity(0.7) : .clear, radius: 8)
            .scaleEffect(isPressed ? 0.94 : 1)
    }

    private var fill: Color {
        if isPressed { return Color.accentColor.opacity(0.85) }
        if isShortcut { return Self.shortcutGlow.opacity(0.45) }
        return .white.opacity(0.08)
    }

    private var stroke: Color {
        if isNext { return Color.accentColor }
        if isShortcut { return Self.shortcutGlow.opacity(0.8) }
        return .white.opacity(0.15)
    }
}

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
    /// Letters whose labels fade because they meet the targets. The next-key
    /// outline still shows, so help is there when needed.
    var mastered: Set<Character> = []
    /// Heatmap: 0 (fine) to 1 (weakest) per letter. Tints keys in one hue.
    var heat: [Character: Double]?
    /// Soft press animation. Off for races, where it smears at high speed.
    var animatesPresses = true
    var unit: CGFloat = 40

    private let spacing: CGFloat = 4

    var body: some View {
        let shortcutCodes = keyboard.commandHeld ? keyboard.shortcutKeyCodes : []
        let next = nextCharacter.flatMap { keyboard.nextStroke(for: $0) }

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(KeyboardGeometry.rows(for: keyboard.shape).enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { key in
                        if key.kind == .returnGap {
                            Color.clear.frame(width: width(key.width), height: unit)
                        } else {
                            KeyCap(
                                label: label(for: key),
                                physicalLabel: physicalLabel(for: key),
                                width: width(key.width),
                                height: unit,
                                tallBottomWidth: tallBottomWidth(key),
                                rowSpacing: spacing,
                                isPressed: keyboard.pressed.contains(key.code),
                                isNext: isNext(key, next),
                                isShortcut: shortcutCodes.contains(key.code),
                                isDimmed: isLocked(key),
                                isFaded: isMastered(key),
                                heat: heatValue(for: key),
                                scalesOnPress: animatesPresses
                            )
                        }
                    }
                }
            }
        }
        .padding(spacing * 3)
        .animation(animatesPresses ? .easeOut(duration: 0.08) : nil, value: keyboard.pressed)
        .animation(.easeInOut(duration: 0.15), value: keyboard.commandHeld)
    }

    /// The next key, plus Shift or Option when it needs them (both sides outlined).
    private func isNext(_ key: KeyboardGeometry.Key, _ next: KeyboardLayout.Stroke?) -> Bool {
        guard let next else { return false }
        if key.code == next.code { return true }
        if next.shift, key.code == 56 || key.code == 60 { return true }
        if next.option, key.code == 58 || key.code == 61 { return true }
        return false
    }

    private func width(_ units: Double) -> CGFloat {
        unit * units + spacing * (units - 1)
    }

    private func tallBottomWidth(_ key: KeyboardGeometry.Key) -> CGFloat? {
        if case .tallReturn(let bottom) = key.kind { return width(bottom) }
        return nil
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

    private func isMastered(_ key: KeyboardGeometry.Key) -> Bool {
        guard !mastered.isEmpty, !keyboard.commandHeld, key.isCharacterKey,
              let label = keyboard.layout?.character(for: key.code), label.count == 1
        else { return false }
        return mastered.contains(Character(label.lowercased()))
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
    /// For the L-shaped ISO/JIS Return: width of the lower part, which reaches
    /// down one row (plus `rowSpacing`), aligned right.
    var tallBottomWidth: CGFloat?
    var rowSpacing: CGFloat = 4
    let isPressed: Bool
    let isNext: Bool
    let isShortcut: Bool
    let isDimmed: Bool
    var isFaded = false
    var heat: Double?
    var scalesOnPress = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = KeyboardPalette(colorScheme)
        let shape = KeyShape(bottomWidth: tallBottomWidth, rowHeight: height)
        let fullHeight = tallBottomWidth == nil ? height : height * 2 + rowSpacing
        Text(label)
            .font(.system(size: label.count > 1 ? 11 : 16, weight: .medium, design: .rounded))
            .foregroundStyle(isPressed ? palette.pressedLabel : isDimmed ? palette.dimmedLabel : palette.label)
            .opacity(isFaded && !isPressed && !isNext ? 0.18 : 1)
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
            .background(alignment: .top) {
                ZStack {
                    shape.fill(fill(palette))
                    shape.strokeBorder(stroke(palette), lineWidth: isNext ? 2 : 1)
                }
                .frame(width: width, height: fullHeight)
                .shadow(color: isShortcut ? palette.shortcutGlow : .clear, radius: 8)
            }
            .scaleEffect(isPressed && scalesOnPress ? 0.94 : 1, anchor: tallBottomWidth == nil ? .center : .top)
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

/// A rounded key, or the L-shaped ISO/JIS Return when `bottomWidth` is set:
/// full width for the top row, narrower and right-aligned below.
private struct KeyShape: InsettableShape {
    var bottomWidth: CGFloat?
    var rowHeight: CGFloat
    var inset: CGFloat = 0
    var radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard let bottomWidth else {
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r)
        }
        let neckX = r.maxX - bottomWidth + inset * 2
        let neckY = r.minY + rowHeight - inset * 2
        let c = radius
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: neckX + c, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: neckX, y: r.maxY - c), control: CGPoint(x: neckX, y: r.maxY))
        path.addLine(to: CGPoint(x: neckX, y: neckY + c))
        // Inner corner curves outward.
        path.addQuadCurve(to: CGPoint(x: neckX - c, y: neckY), control: CGPoint(x: neckX, y: neckY))
        path.addLine(to: CGPoint(x: r.minX + c, y: neckY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: neckY - c), control: CGPoint(x: r.minX, y: neckY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> KeyShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

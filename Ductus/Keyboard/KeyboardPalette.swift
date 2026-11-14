import SwiftUI

/// Colors for the keyboard, drill strip and floating stats, in light and dark.
/// Views pick one with `KeyboardPalette(colorScheme)`, so they follow the app
/// appearance (System, Light or Dark in Settings).
struct KeyboardPalette {
    /// Tint laid over the blur material behind the keyboard.
    let backing: Color
    let keyFill: Color
    let keyStroke: Color
    let label: Color
    let dimmedLabel: Color
    let physicalLabel: Color
    let pressedLabel: Color
    let shortcutFill: Color
    let shortcutStroke: Color
    let shortcutGlow: Color
    /// Primary text in the drill strip and stats row.
    let text: Color
    let secondaryText: Color
    let fadedText: Color

    /// Heatmap hue. A single hue whose strength shows weakness (sequential scale).
    static let heat = Color(red: 0.93, green: 0.42, blue: 0.16)

    init(_ scheme: ColorScheme) {
        switch scheme {
        case .light:
            backing = .white.opacity(0.55)
            keyFill = .white.opacity(0.9)
            keyStroke = .black.opacity(0.14)
            label = .black.opacity(0.85)
            dimmedLabel = .black.opacity(0.22)
            physicalLabel = .black.opacity(0.4)
            pressedLabel = .white
            shortcutFill = Color(red: 1.0, green: 0.78, blue: 0.25).opacity(0.6)
            shortcutStroke = Color(red: 0.85, green: 0.6, blue: 0.0)
            shortcutGlow = Color(red: 1.0, green: 0.72, blue: 0.1).opacity(0.6)
            text = .black.opacity(0.85)
            secondaryText = .black.opacity(0.5)
            fadedText = .black.opacity(0.28)
        default:
            backing = .black.opacity(0.55)
            keyFill = .white.opacity(0.08)
            keyStroke = .white.opacity(0.15)
            label = .white.opacity(0.9)
            dimmedLabel = .white.opacity(0.25)
            physicalLabel = .white.opacity(0.35)
            pressedLabel = .white
            shortcutFill = Color(red: 1.0, green: 0.84, blue: 0.4).opacity(0.45)
            shortcutStroke = Color(red: 1.0, green: 0.84, blue: 0.4).opacity(0.8)
            shortcutGlow = Color(red: 1.0, green: 0.84, blue: 0.4).opacity(0.7)
            text = .white.opacity(0.9)
            secondaryText = .white.opacity(0.55)
            fadedText = .white.opacity(0.3)
        }
    }
}

/// App appearance choice stored in Settings.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension KeyboardGeometry.Finger {
    /// Finger-zone tint, the same on both hands, like a typing chart.
    var color: Color {
        switch self {
        case .pinky: Color(red: 0.62, green: 0.42, blue: 0.95)
        case .ring: Color(red: 0.25, green: 0.55, blue: 0.98)
        case .middle: Color(red: 0.22, green: 0.75, blue: 0.45)
        case .index: Color(red: 0.98, green: 0.58, blue: 0.20)
        case .thumb: Color(red: 0.55, green: 0.55, blue: 0.60)
        }
    }
}

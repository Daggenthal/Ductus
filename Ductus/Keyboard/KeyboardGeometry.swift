import Carbon.HIToolbox

/// Physical key positions for Mac keyboards (ANSI, ISO, JIS), by macOS
/// virtual keycode. Labels for character keys come from the active layout,
/// not from here.
enum KeyboardGeometry {
    /// Physical keyboard standard.
    enum Shape: String, CaseIterable, Identifiable, Sendable {
        /// U.S. and most of the Americas and Asia.
        case ansi
        /// Most of Europe: an extra key next to left Shift and a tall Return.
        case iso
        /// Japan: ¥ and _ keys, 英数 and かな beside the space bar.
        case jis

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ansi: "ANSI"
            case .iso: "ISO"
            case .jis: "JIS"
            }
        }

        /// The kind of keyboard macOS last saw typing (built-in or external).
        @MainActor
        static var detected: Shape {
            switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
            case kKeyboardISO: .iso
            case kKeyboardJIS: .jis
            default: .ansi
            }
        }
    }

    struct Key: Identifiable, Hashable {
        enum Kind: Hashable {
            case normal
            /// Upper part of the L-shaped ISO/JIS Return. Drawn reaching down
            /// into the next row, over the gap left by `returnGap`.
            case tallReturn(bottomWidth: Double)
            /// Empty space under the tall Return.
            case returnGap
        }

        let code: UInt16
        /// Width in key units (a letter key is 1).
        let width: Double
        /// Fixed label for non-character keys (Tab, Shift, ...). `nil` for character keys.
        let fixedLabel: String?
        var kind: Kind = .normal

        var id: String { "\(code)-\(kind)" }
        var isCharacterKey: Bool { fixedLabel == nil }

        static func char(_ code: UInt16) -> Key { Key(code: code, width: 1, fixedLabel: nil) }
        static func special(_ code: UInt16, _ label: String, _ width: Double) -> Key {
            Key(code: code, width: width, fixedLabel: label)
        }
        static func tallReturn(top: Double, bottom: Double) -> Key {
            Key(code: 36, width: top, fixedLabel: "return", kind: .tallReturn(bottomWidth: bottom))
        }
        static func returnGap(_ width: Double) -> Key {
            Key(code: 36, width: width, fixedLabel: "", kind: .returnGap)
        }
    }

    /// Modifier keycodes, so flagsChanged events can light them up.
    static let commandCodes: Set<UInt16> = [55, 54]
    static let modifierCodes: Set<UInt16> = [55, 54, 56, 60, 58, 61, 59, 62, 63, 57]

    /// QWERTY A S D F G H J K L ; positions (the same on all three shapes).
    static let homeRowCodes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41]

    static func rows(for shape: Shape) -> [[Key]] {
        switch shape {
        case .ansi: ansi
        case .iso: iso
        case .jis: jis
        }
    }

    /// Every character keycode on any shape, so layouts translate them all.
    static let allCharacterCodes: Set<UInt16> = Set(
        Shape.allCases.flatMap { rows(for: $0).joined() }.filter(\.isCharacterKey).map(\.code)
    )

    static func characterCodes(for shape: Shape) -> Set<UInt16> {
        switch shape {
        case .ansi: ansiCodes
        case .iso: isoCodes
        case .jis: jisCodes
        }
    }

    private static let ansiCodes = Set(ansi.joined().filter(\.isCharacterKey).map(\.code))
    private static let isoCodes = Set(iso.joined().filter(\.isCharacterKey).map(\.code))
    private static let jisCodes = Set(jis.joined().filter(\.isCharacterKey).map(\.code))

    // Every row is 14.5 units wide.

    private static let qRow: [Key] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30].map(Key.char)
    private static let zRow: [Key] = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44].map(Key.char)
    private static let macBottomRow: [Key] = [
        .special(63, "fn", 1), .special(59, "⌃", 1), .special(58, "⌥", 1), .special(55, "⌘", 1.25),
        .special(49, "", 6.5), .special(54, "⌘", 1.25), .special(61, "⌥", 1), .special(62, "⌃", 1.5),
    ]

    static let ansi: [[Key]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24].map(Key.char) + [.special(51, "delete", 1.5)],
        [.special(48, "tab", 1.5)] + qRow + [.char(42)],
        [.special(57, "caps", 1.75)] + [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39].map(Key.char)
            + [.special(36, "return", 1.75)],
        [.special(56, "shift", 2.25)] + zRow + [.special(60, "shift", 2.25)],
        macBottomRow,
    ]

    /// Mac ISO: § (10) top left, the key left of Z is 50, and the key left of
    /// Return on the home row is 42.
    static let iso: [[Key]] = [
        [10, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24].map(Key.char) + [.special(51, "delete", 1.5)],
        [.special(48, "tab", 1.5)] + qRow + [.tallReturn(top: 1, bottom: 0.75)],
        [.special(57, "caps", 1.75)] + [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42].map(Key.char)
            + [.returnGap(0.75)],
        [.special(56, "shift", 1.25), .char(50)] + zRow + [.special(60, "shift", 2.25)],
        macBottomRow,
    ]

    /// Apple JIS: ¥ (93) and _ (94), Control left of A, 英数 (102) and かな (104)
    /// beside the space bar.
    static let jis: [[Key]] = [
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 93].map(Key.char) + [.special(51, "delete", 1.5)],
        [.special(48, "tab", 1.5)] + qRow + [.tallReturn(top: 1, bottom: 0.75)],
        [.special(59, "control", 1.75)] + [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42].map(Key.char)
            + [.returnGap(0.75)],
        [.special(56, "shift", 2.25)] + zRow + [.char(94), .special(60, "shift", 1.25)],
        [.special(57, "caps", 1.25), .special(58, "⌥", 1), .special(55, "⌘", 1.25),
         .special(102, "英数", 1.25), .special(49, "", 4.75), .special(104, "かな", 1.25),
         .special(54, "⌘", 1.25), .special(63, "fn", 1), .special(61, "⌥", 1.5)],
    ]
}

/// Physical key positions for an ANSI Mac keyboard, by macOS virtual keycode.
/// Labels for character keys come from the active layout, not from here.
enum KeyboardGeometry {
    struct Key: Identifiable, Hashable {
        let code: UInt16
        /// Width in key units (a letter key is 1).
        let width: Double
        /// Fixed label for non-character keys (Tab, Shift, ...). `nil` for character keys.
        let fixedLabel: String?

        var id: UInt16 { code }
        var isCharacterKey: Bool { fixedLabel == nil }

        static func char(_ code: UInt16) -> Key { Key(code: code, width: 1, fixedLabel: nil) }
        static func special(_ code: UInt16, _ label: String, _ width: Double) -> Key {
            Key(code: code, width: width, fixedLabel: label)
        }
    }

    /// Modifier keycodes, so flagsChanged events can light them up.
    static let commandCodes: Set<UInt16> = [55, 54]
    static let modifierCodes: Set<UInt16> = [55, 54, 56, 60, 58, 61, 59, 62, 63, 57]

    /// QWERTY A S D F G H J K L ; positions.
    static let homeRowCodes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41]

    static let ansi: [[Key]] = [
        [.char(50), .char(18), .char(19), .char(20), .char(21), .char(23), .char(22), .char(26),
         .char(28), .char(25), .char(29), .char(27), .char(24), .special(51, "delete", 1.5)],
        [.special(48, "tab", 1.5), .char(12), .char(13), .char(14), .char(15), .char(17), .char(16),
         .char(32), .char(34), .char(31), .char(35), .char(33), .char(30), .char(42)],
        [.special(57, "caps", 1.75), .char(0), .char(1), .char(2), .char(3), .char(5), .char(4),
         .char(38), .char(40), .char(37), .char(41), .char(39), .special(36, "return", 1.75)],
        [.special(56, "shift", 2.25), .char(6), .char(7), .char(8), .char(9), .char(11), .char(45),
         .char(46), .char(43), .char(47), .char(44), .special(60, "shift", 2.25)],
        [.special(63, "fn", 1), .special(59, "⌃", 1), .special(58, "⌥", 1), .special(55, "⌘", 1.25),
         .special(49, "", 6.5), .special(54, "⌘", 1.25), .special(61, "⌥", 1), .special(62, "⌃", 1.5)],
    ]
}

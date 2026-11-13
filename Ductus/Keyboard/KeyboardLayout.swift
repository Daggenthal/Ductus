import Carbon.HIToolbox
import DuctusLog
import Foundation

/// Snapshot of the active keyboard layout: what each physical key types,
/// plain, with Shift, and with Command.
///
/// Read from the system with TIS + UCKeyTranslate, so any layout works
/// without hardcoding. Layouts like "Dvorak - QWERTY ⌘" map differently when
/// Command is held, and that falls out of passing the Command modifier.
struct KeyboardLayout: Equatable, Sendable {
    let id: String
    let name: String
    private(set) var plain: [UInt16: String] = [:]
    private(set) var shifted: [UInt16: String] = [:]
    private(set) var command: [UInt16: String] = [:]

    /// The active layout, or `nil` if it has no Unicode layout data
    /// (some input methods, e.g. CJK, do not).
    @MainActor
    static func current() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            Log.warning("No current keyboard layout input source")
            return nil
        }
        return KeyboardLayout(source: source)
    }

    @MainActor
    init?(source: TISInputSource) {
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            Log.warning("Input source has no Unicode layout data")
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        id = Self.stringProperty(source, kTISPropertyInputSourceID) ?? "unknown"
        name = Self.stringProperty(source, kTISPropertyLocalizedName) ?? id

        let keyboardType = UInt32(LMGetKbdType())
        for key in KeyboardGeometry.ansi.flatMap({ $0 }) where key.isCharacterKey {
            plain[key.code] = Self.translate(data, key.code, modifiers: 0, keyboardType: keyboardType)
            shifted[key.code] = Self.translate(data, key.code, modifiers: shiftKey, keyboardType: keyboardType)
            command[key.code] = Self.translate(data, key.code, modifiers: cmdKey, keyboardType: keyboardType)
        }
    }

    /// Character a key types, using the Command map while Command is held.
    func character(for code: UInt16, commandHeld: Bool = false) -> String? {
        commandHeld ? command[code] : plain[code]
    }

    /// The physical key that types `character` without Command (checks unshifted first).
    func keyCode(for character: Character) -> UInt16? {
        let target = String(character)
        return plain.first { $0.value == target }?.key ?? shifted.first { $0.value == target }?.key
    }

    /// The physical key that types `character` while Command is held.
    func commandKeyCode(for character: Character) -> UInt16? {
        let target = String(character)
        return command.first { $0.value == target }?.key
    }

    /// Letters on the home-row keys, in physical order. For Dvorak: a o e u i d h t n s.
    var homeRowLetters: [Character] {
        KeyboardGeometry.homeRowCodes.compactMap { code in
            plain[code].flatMap { $0.count == 1 ? Character($0.lowercased()) : nil }
        }.filter(\.isLetter)
    }

    private static func translate(_ data: Data, _ code: UInt16, modifiers: Int, keyboardType: UInt32) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDisplay),
                UInt32((modifiers >> 8) & 0xFF), keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: chars, count: length)
            // Skip control characters; they have no useful label.
            return string.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } ? string : nil
        }
    }

    @MainActor
    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

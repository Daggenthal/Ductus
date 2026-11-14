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
    /// One key press: a physical key plus the modifiers it needs.
    struct Stroke: Hashable, Sendable {
        let code: UInt16
        var shift = false
        var option = false
    }

    /// What a key press typed, with dead keys (accents) applied.
    enum Typed: Equatable {
        /// A dead key: nothing yet, the next key gets the accent ("´" then "e" is "é").
        case deadKey
        case text(String)
        case nothing
    }

    let id: String
    let name: String
    /// Language codes macOS lists for this layout, e.g. ["fr"]. Often just ["en"].
    let languages: [String]
    /// The active input method when it is not a plain layout (Japanese or
    /// Chinese input methods type through a layout like ABC), and its languages.
    private(set) var inputMethodID: String?
    private(set) var inputMethodLanguages: [String] = []
    private(set) var plain: [UInt16: String] = [:]
    private(set) var shifted: [UInt16: String] = [:]
    private(set) var command: [UInt16: String] = [:]
    /// How to type each character: one stroke, or a dead key then a stroke.
    /// Single strokes and fewer modifiers win when there is more than one way.
    private(set) var strokes: [Character: [Stroke]] = [:]
    /// The layout's `UCKeyboardLayout` data, for translating key presses live.
    private let keyData: Data
    private let keyboardType: UInt32

    static func == (a: KeyboardLayout, b: KeyboardLayout) -> Bool {
        a.id == b.id && a.keyboardType == b.keyboardType && a.inputMethodID == b.inputMethodID
    }

    /// The active layout, or `nil` if it has no Unicode layout data
    /// (some input methods, e.g. CJK, do not).
    @MainActor
    static func current() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            Log.warning("No current keyboard layout input source")
            return nil
        }
        var layout = KeyboardLayout(source: source)
        // With an input method on (Japanese, Chinese), the layout above is the one
        // it types through; the input method says which language is being typed.
        if let input = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let inputID = stringProperty(input, kTISPropertyInputSourceID), inputID != layout?.id {
            layout?.inputMethodID = inputID
            layout?.inputMethodLanguages = arrayProperty(input, kTISPropertyInputSourceLanguages)
        }
        return layout
    }

    /// A specific installed layout by input source ID, e.g. `com.apple.keylayout.US`.
    /// Works even if the layout is not enabled in System Settings.
    @MainActor
    static func installed(id: String) -> KeyboardLayout? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first
        else {
            Log.warning("Keyboard layout \(id) not found")
            return nil
        }
        return KeyboardLayout(source: source)
    }

    /// What is printed on the physical keycaps. Mac ANSI keyboards are U.S. QWERTY.
    static let physicalKeycapsID = "com.apple.keylayout.US"

    @MainActor
    init?(source: TISInputSource) {
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            Log.warning("Input source has no Unicode layout data")
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        id = Self.stringProperty(source, kTISPropertyInputSourceID) ?? "unknown"
        name = Self.stringProperty(source, kTISPropertyLocalizedName) ?? id
        languages = Self.arrayProperty(source, kTISPropertyInputSourceLanguages)
        keyData = data

        let keyboardType = UInt32(LMGetKbdType())
        self.keyboardType = keyboardType
        for code in KeyboardGeometry.allCharacterCodes {
            plain[code] = Self.translate(data, code, modifiers: 0, keyboardType: keyboardType)
            shifted[code] = Self.translate(data, code, modifiers: shiftKey, keyboardType: keyboardType)
            command[code] = Self.translate(data, code, modifiers: cmdKey, keyboardType: keyboardType)
        }
        strokes = Self.strokeMap(data, keyboardType: keyboardType)
    }

    /// Lowercase letters this layout can type, directly or with a dead key.
    var typeableLetters: Set<Character> {
        Set(strokes.keys.filter { $0.isLetter && $0.isLowercase })
    }

    /// Translates one key press, carrying dead-key state between presses.
    func type(code: UInt16, shift: Bool, option: Bool, capsLock: Bool, state: inout UInt32) -> Typed {
        var modifiers = 0
        if shift { modifiers |= shiftKey }
        if option { modifiers |= optionKey }
        if capsLock { modifiers |= alphaLock }
        let output = Self.translateLive(keyData, code, modifiers: modifiers, keyboardType: keyboardType, state: &state)
        if let output, !output.isEmpty { return .text(output) }
        return state != 0 ? .deadKey : .nothing
    }

    private static let modifierCombos: [(shift: Bool, option: Bool)] = [
        (false, false), (true, false), (false, true), (true, true),
    ]

    private static func strokeMap(_ data: Data, keyboardType: UInt32) -> [Character: [Stroke]] {
        var map: [Character: [Stroke]] = [:]
        var deadKeys: [(stroke: Stroke, state: UInt32)] = []
        let codes = KeyboardGeometry.allCharacterCodes.sorted()
        for combo in modifierCombos {
            let modifiers = (combo.shift ? shiftKey : 0) | (combo.option ? optionKey : 0)
            for code in codes {
                var state: UInt32 = 0
                let stroke = Stroke(code: code, shift: combo.shift, option: combo.option)
                let output = translateLive(data, code, modifiers: modifiers, keyboardType: keyboardType, state: &state)
                if let output, output.count == 1, let character = output.first {
                    if map[character] == nil { map[character] = [stroke] }
                } else if state != 0 {
                    deadKeys.append((stroke, state))
                }
            }
        }
        // Accented letters made with a dead key, e.g. ´ then e.
        for dead in deadKeys {
            for combo in modifierCombos where !combo.option {
                for code in codes {
                    var state = dead.state
                    let output = translateLive(data, code, modifiers: combo.shift ? shiftKey : 0,
                                               keyboardType: keyboardType, state: &state)
                    guard let output, output.count == 1, let character = output.first, map[character] == nil
                    else { continue }
                    map[character] = [dead.stroke, Stroke(code: code, shift: combo.shift)]
                }
            }
        }
        return map
    }

    /// `UCKeyTranslate` with dead keys on. Control characters come back as `nil`.
    private static func translateLive(
        _ data: Data, _ code: UInt16, modifiers: Int, keyboardType: UInt32, state: inout UInt32
    ) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown),
                UInt32((modifiers >> 8) & 0xFF), keyboardType, 0,
                &state, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: chars, count: length)
            return string.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } ? string : nil
        }
    }

    /// Character a key types, using the Command map while Command is held.
    func character(for code: UInt16, commandHeld: Bool = false) -> String? {
        commandHeld ? command[code] : plain[code]
    }

    /// The physical key that types `character` while Command is held.
    func commandKeyCode(for character: Character, on shape: KeyboardGeometry.Shape) -> UInt16? {
        let target = String(character)
        let codes = KeyboardGeometry.characterCodes(for: shape)
        return command.filter { codes.contains($0.key) && $0.value == target }.keys.min()
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
    private static func arrayProperty(_ source: TISInputSource, _ key: CFString) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }

    @MainActor
    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

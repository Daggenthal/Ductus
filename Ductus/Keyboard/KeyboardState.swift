import AppKit
import Carbon.HIToolbox
import DuctusLog
import Observation

/// Live keyboard state shared by the practice window and the HUD:
/// the active layout, which keys are down, and whether Command is held.
@MainActor
@Observable
final class KeyboardState {
    private(set) var layout: KeyboardLayout?
    /// What is printed on the physical keycaps (U.S. QWERTY), for the faint secondary labels.
    let physicalLayout = KeyboardLayout.installed(id: KeyboardLayout.physicalKeycapsID)
    private(set) var pressed: Set<UInt16> = []
    private(set) var commandHeld = false

    /// Keys that glow while Command is held. Found by asking the layout which
    /// key types each of these with Command, so positions are never hardcoded.
    var shortcutLetters: [Character] = ["z", "x", "c", "v"]

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var layoutObserver: NSObjectProtocol?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    /// Runs only while a modifier is shown as held. See `syncModifiers`.
    @ObservationIgnored private var staleModifierTimer: Timer?

    /// Called for each key press that types a character, before the HUD updates.
    /// Return `true` to swallow the event (so the window does not beep).
    @ObservationIgnored var onCharacter: ((Character, UInt16, TimeInterval) -> Bool)?

    /// Called for Backspace (`true` = Option-Backspace, delete a word).
    /// Return `true` to swallow the event.
    @ObservationIgnored var onBackspace: ((Bool) -> Bool)?

    /// Called when the active input source changes to a different layout.
    @ObservationIgnored var onLayoutChange: ((KeyboardLayout?) -> Void)?

    init() {
        reloadLayout()

        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadLayout() }
        }

        // Key-up events can go missing (e.g. during Command shortcuts or app
        // switches), so clear everything when the app loses focus.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneReleasedModifiers() }
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let passThrough = MainActor.assumeIsolated { self?.handle(event) ?? true }
            return passThrough ? event : nil
        }
    }

    func reloadLayout() {
        let new = KeyboardLayout.current()
        let changed = new?.id != layout?.id
        layout = new
        if changed {
            Log.success("Keyboard layout: \(new?.name ?? "none")")
            onLayoutChange?(new)
        }
    }

    // MARK: - Derived

    var shortcutKeyCodes: Set<UInt16> {
        guard let layout else { return [] }
        return Set(shortcutLetters.compactMap(layout.commandKeyCode(for:)))
    }

    func keyCode(for character: Character) -> UInt16? {
        character == " " ? 49 : layout?.keyCode(for: character)
    }

    /// `true` if typing `character` needs Shift on the active layout.
    func needsShift(for character: Character) -> Bool {
        guard character != " ", let layout else { return false }
        let string = String(character)
        return !layout.plain.values.contains(string) && layout.shifted.values.contains(string)
    }

    // MARK: - Events

    /// Key events from other apps (system-wide highlighting). Only lights keys
    /// up; never types into practice.
    func handleExternal(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            syncModifiers(event.modifierFlags)
            pressed.insert(event.keyCode)
        case .keyUp:
            syncModifiers(event.modifierFlags)
            pressed.remove(event.keyCode)
        case .flagsChanged:
            syncModifiers(event.modifierFlags, changedKey: event.keyCode)
        default:
            break
        }
    }

    /// Returns `false` to swallow the event.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            syncModifiers(event.modifierFlags)
            pressed.insert(event.keyCode)
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            // Backspace (51), plain or with Option. Repeats are fine here.
            if event.keyCode == 51, modifiers.subtracting(.option).isEmpty,
               onBackspace?(modifiers.contains(.option)) == true {
                return false
            }
            guard modifiers.isEmpty, !event.isARepeat,
                  let character = event.characters?.first,
                  character == " " || !(character.isWhitespace || character.isNewline),
                  character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
            else { return true }
            let swallow = onCharacter?(character, event.keyCode, event.timestamp) ?? false
            return !swallow

        case .keyUp:
            syncModifiers(event.modifierFlags)
            pressed.remove(event.keyCode)
            return true

        case .flagsChanged:
            syncModifiers(event.modifierFlags, changedKey: event.keyCode)
            return true

        default:
            return true
        }
    }

    /// Device-dependent flag bits (IOKit `NX_DEVICE*KEYMASK`) that tell left and
    /// right modifiers apart.
    private static let modifierBits: [(code: UInt16, bit: UInt, flag: NSEvent.ModifierFlags)] = [
        (56, 0x0002, .shift), (60, 0x0004, .shift),
        (59, 0x0001, .control), (62, 0x2000, .control),
        (58, 0x0020, .option), (61, 0x0040, .option),
        (55, 0x0008, .command), (54, 0x0010, .command),
    ]

    /// Sets which modifier keys are lit from the actual modifier state, instead
    /// of toggling on each event. If an event goes missing (e.g. the screenshot
    /// tool grabs the keyboard during Cmd-Shift-5), the next sync corrects it.
    ///
    /// - Parameter changedKey: Keycode of a flagsChanged event, used for Fn,
    ///   which has no left/right bit.
    private func syncModifiers(_ flags: NSEvent.ModifierFlags, changedKey: UInt16? = nil) {
        var held = Set<UInt16>()
        for (code, bit, _) in Self.modifierBits where flags.rawValue & bit != 0 {
            held.insert(code)
        }
        // Some events carry only the generic flag; fall back to the left key.
        for (flag, leftCode) in [(NSEvent.ModifierFlags.shift, UInt16(56)), (.control, 59), (.option, 58), (.command, 55)]
        where flags.contains(flag) && !Self.modifierBits.contains(where: { $0.flag == flag && held.contains($0.code) }) {
            held.insert(leftCode)
        }
        if flags.contains(.capsLock) { held.insert(57) }
        if flags.contains(.function), changedKey == 63 || pressed.contains(63) { held.insert(63) }

        let wasCommand = commandHeld
        let newPressed = pressed.subtracting(KeyboardGeometry.modifierCodes).union(held)
        if newPressed != pressed { pressed = newPressed }
        commandHeld = flags.contains(.command)

        // Key-ups during Command chords often never arrive. Reset on release.
        if wasCommand && !commandHeld {
            pressed = pressed.filter { KeyboardGeometry.modifierCodes.contains($0) }
        }
        updateStaleModifierTimer()
    }

    /// Clears lit modifiers whose flag is no longer set, using the live state
    /// from `NSEvent.modifierFlags`. Only removes, never adds: the live state may
    /// not say left vs right, and events handle adding.
    private func pruneReleasedModifiers() {
        let flags = NSEvent.modifierFlags
        var stillHeld = pressed.intersection(KeyboardGeometry.modifierCodes)
        for (code, _, flag) in Self.modifierBits where !flags.contains(flag) { stillHeld.remove(code) }
        if !flags.contains(.capsLock) { stillHeld.remove(57) }
        if !flags.contains(.function) { stillHeld.remove(63) }

        let wasCommand = commandHeld
        let newPressed = pressed.subtracting(KeyboardGeometry.modifierCodes).union(stillHeld)
        if newPressed != pressed { pressed = newPressed }
        if !flags.contains(.command) { commandHeld = false }
        if wasCommand && !commandHeld {
            pressed = pressed.filter { KeyboardGeometry.modifierCodes.contains($0) }
        }
        updateStaleModifierTimer()
    }

    /// While any modifier is lit, re-check the real modifier state a few times a
    /// second, so a release that happened outside the app is noticed quickly.
    private func updateStaleModifierTimer() {
        let anyHeld = commandHeld || !pressed.isDisjoint(with: KeyboardGeometry.modifierCodes.subtracting([57]))
        if anyHeld, staleModifierTimer == nil {
            staleModifierTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pruneReleasedModifiers() }
            }
        } else if !anyHeld {
            staleModifierTimer?.invalidate()
            staleModifierTimer = nil
        }
    }

    private func releaseAll() {
        pressed = []
        commandHeld = false
        updateStaleModifierTimer()
    }
}

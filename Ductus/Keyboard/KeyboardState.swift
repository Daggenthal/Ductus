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
    private(set) var pressed: Set<UInt16> = []
    private(set) var commandHeld = false

    /// Keys that glow while Command is held. Found by asking the layout which
    /// key types each of these with Command, so positions are never hardcoded.
    var shortcutLetters: [Character] = ["z", "x", "c", "v"]

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var layoutObserver: NSObjectProtocol?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    /// Called for each key press that types a character, before the HUD updates.
    /// Return `true` to swallow the event (so the window does not beep).
    @ObservationIgnored var onCharacter: ((Character, UInt16, TimeInterval) -> Bool)?

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

    // MARK: - Events

    /// Returns `false` to swallow the event.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            pressed.insert(event.keyCode)
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty, !event.isARepeat,
                  let character = event.characters?.first,
                  character == " " || !(character.isWhitespace || character.isNewline),
                  character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
            else { return true }
            let swallow = onCharacter?(character, event.keyCode, event.timestamp) ?? false
            return !swallow

        case .keyUp:
            pressed.remove(event.keyCode)
            return true

        case .flagsChanged:
            let wasCommand = commandHeld
            commandHeld = event.modifierFlags.contains(.command)
            if KeyboardGeometry.modifierCodes.contains(event.keyCode) {
                if pressed.contains(event.keyCode) { pressed.remove(event.keyCode) } else { pressed.insert(event.keyCode) }
            }
            // Key-ups during Command chords often never arrive. Reset on release.
            if wasCommand && !commandHeld { pressed = pressed.filter { KeyboardGeometry.modifierCodes.contains($0) } }
            if !event.modifierFlags.contains(.command) { pressed.subtract(KeyboardGeometry.commandCodes) }
            return true

        default:
            return true
        }
    }

    private func releaseAll() {
        pressed = []
        commandHeld = false
    }
}

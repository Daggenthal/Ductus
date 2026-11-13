import AppKit
import DuctusLog
import SwiftUI

@main
struct DuctusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        Window("Ductus", id: "practice") {
            PracticeView()
                .environment(app.practice)
                .environment(app.keyboard)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Practice") {
                Button("Next Drill") { app.practice.nextDrill() }
                    .keyboardShortcut("n")
                Divider()
                Button("Show or Hide Keyboard") { app.toggleHUD() }
                    .keyboardShortcut("k")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

enum SettingsKey {
    static let showHUD = "showKeyboardHUD"
    static let hudOpacity = "keyboardHUDOpacity"
    static let hudClickThrough = "keyboardHUDClickThrough"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let keyboard = KeyboardState()
    let practice = PracticeModel()
    private var hud: KeyboardHUD?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            SettingsKey.showHUD: true,
            SettingsKey.hudOpacity: 0.9,
            SettingsKey.hudClickThrough: false,
        ])
        if Log.isDebug { Log.info("Debug mode on") }

        // Typing goes to practice only when the practice window is in front
        // and no text field is being edited.
        keyboard.onCharacter = { [practice] character, keyCode, time in
            guard let window = NSApp.keyWindow, window.title == "Ductus",
                  !(window.firstResponder is NSTextView)
            else { return false }
            return practice.type(character, keyCode: keyCode, at: time)
        }

        practice.start(startingKeys: keyboard.layout?.homeRowLetters ?? [])
        keyboard.onLayoutChange = { [practice] layout in
            practice.restartIfUntouched(startingKeys: layout?.homeRowLetters ?? [])
        }

        hud = KeyboardHUD(content: HUDContent(keyboard: keyboard, practice: practice))
        applySettings()
        if UserDefaults.standard.bool(forKey: SettingsKey.showHUD) { hud?.show() }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        Log.success("Ductus ready")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func toggleHUD() {
        hud?.toggle()
        UserDefaults.standard.set(hud?.isVisible ?? false, forKey: SettingsKey.showHUD)
    }

    private func applySettings() {
        let defaults = UserDefaults.standard
        hud?.setOpacity(defaults.double(forKey: SettingsKey.hudOpacity))
        hud?.setClickThrough(defaults.bool(forKey: SettingsKey.hudClickThrough))
    }
}

/// What the HUD panel shows. Reads live state so it redraws on every key.
private struct HUDContent: View {
    let keyboard: KeyboardState
    let practice: PracticeModel

    var body: some View {
        KeyboardView(
            keyboard: keyboard,
            nextCharacter: practice.nextCharacter,
            unlockedLetters: practice.unlockedLetters
        )
    }
}

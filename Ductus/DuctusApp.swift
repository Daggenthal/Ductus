import AppKit
import DuctusLog
import SwiftUI

@main
struct DuctusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.keyboardPoppedOut) private var poppedOut = false
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true
    @AppStorage(SettingsKey.showDrillInFloating) private var showDrillInFloating = true
    @AppStorage(SettingsKey.showStatsInFloating) private var showStatsInFloating = true

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
                Toggle("Show Keyboard", isOn: $showKeyboard)
                    .keyboardShortcut("k")
                Toggle("Pop Out Keyboard", isOn: $poppedOut)
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Toggle("Show Physical Key Labels", isOn: $showPhysicalLabels)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Toggle("Show Words on Floating Keyboard", isOn: $showDrillInFloating)
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Toggle("Show Stats on Floating Keyboard", isOn: $showStatsInFloating)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

enum SettingsKey {
    static let showKeyboard = "showKeyboard"
    /// `false`: keyboard is docked in the practice window. `true`: floating panel.
    static let keyboardPoppedOut = "keyboardPoppedOut"
    static let hudOpacity = "keyboardHUDOpacity"
    static let hudClickThrough = "keyboardHUDClickThrough"
    static let showPhysicalLabels = "keyboardShowPhysicalLabels"
    static let showDrillInFloating = "keyboardShowDrillInFloating"
    static let showStatsInFloating = "keyboardShowStatsInFloating"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let keyboard = KeyboardState()
    let practice = PracticeModel()
    private var hud: KeyboardHUD?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            SettingsKey.showKeyboard: true,
            SettingsKey.keyboardPoppedOut: false,
            SettingsKey.hudOpacity: 0.9,
            SettingsKey.hudClickThrough: false,
            SettingsKey.showPhysicalLabels: true,
            SettingsKey.showDrillInFloating: true,
            SettingsKey.showStatsInFloating: true,
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

        hud = KeyboardHUD(content: FloatingKeyboard(keyboard: keyboard, practice: practice))
        applySettings()

        // Settings, the menu and the window switch all write UserDefaults;
        // the floating panel follows from here.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        Log.success("Ductus ready")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func applySettings() {
        let defaults = UserDefaults.standard
        hud?.setOpacity(defaults.double(forKey: SettingsKey.hudOpacity))
        hud?.setClickThrough(defaults.bool(forKey: SettingsKey.hudClickThrough))

        let floating = defaults.bool(forKey: SettingsKey.showKeyboard) && defaults.bool(forKey: SettingsKey.keyboardPoppedOut)
        if floating, hud?.isVisible == false { hud?.show() }
        if !floating, hud?.isVisible == true { hud?.hide() }
    }
}

/// Floating panel content: the keyboard, with the drill text above it if enabled.
private struct FloatingKeyboard: View {
    let keyboard: KeyboardState
    let practice: PracticeModel
    @AppStorage(SettingsKey.showDrillInFloating) private var showDrill = true
    @AppStorage(SettingsKey.showStatsInFloating) private var showStats = true

    var body: some View {
        PracticeKeyboard(keyboard: keyboard, practice: practice, showsDrill: showDrill, showsStats: showStats)
    }
}

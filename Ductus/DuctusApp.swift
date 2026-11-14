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
            MainView()
                .environment(app.practice)
                .environment(app.race)
                .environment(app.keyboard)
                .environment(app.ui)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // ⌘, toggles the settings panel inside the practice window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.toggleSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(before: .toolbar) {
                Button("Practice") { app.showTab(.practice) }
                    .keyboardShortcut("1")
                Button("Race") { app.showTab(.race) }
                    .keyboardShortcut("2")
                Button("History") { app.showTab(.history) }
                    .keyboardShortcut("3")
                Button("Show History") { app.showTab(.history) }
                    .keyboardShortcut("y")
                Divider()
            }
            CommandMenu("Practice") {
                Button("Next Drill or Race") { app.newDrillOrRace() }
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

    }
}

/// UI state shared between menus and views.
@MainActor
@Observable
final class AppUIState {
    /// Which tab the main window shows.
    var tab: MainTab = .practice {
        didSet { if tab != oldValue { onTabChange?() } }
    }
    @ObservationIgnored var onTabChange: (() -> Void)?

    /// The settings panel on the right side of the practice window.
    /// Change it with `setSettings(_:)` so the window size is remembered.
    var showSettings = false

    /// Practice window width before the settings panel widened it.
    @ObservationIgnored private var widthBeforeSettings: CGFloat?

    static var practiceWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Ductus" }
    }

    /// How long the panel takes to open or close. The window resize uses the same.
    static let settingsAnimation = 0.25

    func setSettings(_ show: Bool) {
        if show {
            guard !showSettings else { return }
            widthBeforeSettings = Self.practiceWindow?.frame.width
            withAnimation(.easeInOut(duration: Self.settingsAnimation)) { showSettings = true }
        } else {
            guard showSettings else { return }
            // Collapse the panel and shrink the window in one animation, so the
            // practice content keeps its width the whole way (no rubber-band).
            withAnimation(.easeInOut(duration: Self.settingsAnimation)) { showSettings = false }
            restoreWidth()
        }
    }

    /// Fallback for the panel being closed some other way (e.g. by the system).
    func settingsDidClose() {
        restoreWidth()
    }

    /// Animates the window back to the width it had before the panel opened,
    /// keeping its left edge in place.
    private func restoreWidth() {
        guard let width = widthBeforeSettings else { return }
        widthBeforeSettings = nil
        // Wait one run loop pass so SwiftUI has dropped the panel from the window's
        // minimum size. Otherwise a window the user had shrunk to its smallest
        // size gets held wider than it was.
        Task { @MainActor in
            guard let window = Self.practiceWindow, window.frame.width > width else { return }
            var frame = window.frame
            frame.size.width = width  // the user's own width; it was valid before the panel opened
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.settingsAnimation
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
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
    static let appearance = "appearance"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let keyboard = KeyboardState()
    let practice = PracticeModel()
    let panelFocus = PanelFocus()
    let ui = AppUIState()
    lazy var race = RaceModel(practice: practice)
    private let sounds = KeySounds()
    private lazy var globalMonitor = GlobalKeyMonitor { [weak self] event in
        self?.keyboard.handleExternal(event)
    }
    private var store: ProgressStore?
    /// Last seen pop-out state, to react only to changes (not at launch).
    private var lastPoppedOut: Bool?
    /// Guards against `applySettings` re-entering itself through a tab change.
    private var isApplyingSettings = false
    private var hud: KeyboardHUD?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsKey.registerPracticeDefaults()
        UserDefaults.standard.register(defaults: [
            SettingsKey.showKeyboard: true,
            SettingsKey.keyboardPoppedOut: false,
            SettingsKey.hudOpacity: 0.9,
            SettingsKey.hudClickThrough: false,
            SettingsKey.showPhysicalLabels: true,
            SettingsKey.showDrillInFloating: true,
            SettingsKey.showStatsInFloating: true,
            SettingsKey.appearance: AppearanceChoice.system.rawValue,
        ])
        if Log.isDebug { Log.info("Debug mode on") }

        // Typing goes to practice when the practice window or the floating
        // keyboard is the key window, and no text field is being edited.
        // The floating keyboard always types into practice. The main window
        // types into whichever tab is showing (History takes no typing).
        keyboard.onCharacter = { [weak self] character, keyCode, time in
            guard let self, let window = NSApp.keyWindow, !(window.firstResponder is NSTextView) else { return false }
            if window.identifier == KeyboardHUD.panelID {
                return self.practice.type(character, keyCode: keyCode, at: time)
            }
            guard window.title == "Ductus" else { return false }
            switch self.ui.tab {
            case .practice: return self.practice.type(character, keyCode: keyCode, at: time)
            case .race: return self.race.type(character, keyCode: keyCode, at: time)
            case .history: return false
            }
        }
        keyboard.onBackspace = { [weak self] word in
            guard let self, let window = NSApp.keyWindow, !(window.firstResponder is NSTextView) else { return false }
            if window.identifier == KeyboardHUD.panelID { return self.practice.backspace(word: word) }
            guard window.title == "Ductus" else { return false }
            switch self.ui.tab {
            case .practice: return self.practice.backspace(word: word)
            case .race: return self.race.backspace(word: word)
            case .history: return false
            }
        }
        // Swallow accent keys when practice or a race would take the letter.
        keyboard.onDeadKey = { [weak self] in
            guard let self, let window = NSApp.keyWindow, !(window.firstResponder is NSTextView) else { return false }
            return window.identifier == KeyboardHUD.panelID || (window.title == "Ductus" && self.ui.tab != .history)
        }
        ui.onTabChange = { [weak self] in self?.applySettings() }

        // Progress is saved per layout. Switching input source switches progress.
        practice.onKeystroke = { [sounds] correct in sounds.keystroke(correct: correct) }
        let store = ProgressStore()
        self.store = store
        practice.start(layout: keyboard.layout, store: store)
        keyboard.onLayoutChange = { [practice] layout in
            practice.switchLayout(to: layout)
        }

        hud = KeyboardHUD(
            content: FloatingKeyboard(
                keyboard: keyboard, practice: practice, focus: panelFocus,
                onDock: { [weak self] in self?.dockKeyboard() }
            ),
            focus: panelFocus
        )
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

    func applicationDidBecomeActive(_ notification: Notification) {
        practice.warmUpIfReturning()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        practice.persist()
    }

    /// Puts the keyboard back in the practice window and brings that window forward.
    func dockKeyboard() {
        UserDefaults.standard.set(false, forKey: SettingsKey.keyboardPoppedOut)
        UserDefaults.standard.set(true, forKey: SettingsKey.showKeyboard)
        focusPracticeWindow()
    }

    func showTab(_ tab: MainTab) {
        ui.tab = tab
        focusPracticeWindow()
    }

    func newDrillOrRace() {
        switch ui.tab {
        case .race: race.newRace()
        default: practice.nextDrill()
        }
    }

    /// Opens or closes the settings panel, bringing the practice window back if needed.
    func toggleSettings() {
        if !ui.showSettings { focusPracticeWindow() }
        ui.setSettings(!ui.showSettings)
    }

    private var practiceWindow: NSWindow? { AppUIState.practiceWindow }

    private func focusPracticeWindow() {
        NSApp.activate()
        guard let window = NSApp.windows.first(where: { $0.title == "Ductus" }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    private func applySettings() {
        guard !isApplyingSettings else { return }
        isApplyingSettings = true
        defer { isApplyingSettings = false }
        let defaults = UserDefaults.standard

        practice.applySettings()
        let glow = Array(defaults.string(forKey: SettingsKey.shortcutKeys) ?? SettingsKey.defaultShortcutKeys)
        if keyboard.shortcutLetters != glow { keyboard.shortcutLetters = glow }
        let shape = KeyboardGeometry.Shape(rawValue: defaults.string(forKey: SettingsKey.keyboardShape) ?? "")
        if keyboard.shapeOverride != shape { keyboard.shapeOverride = shape }
        sounds.configure(
            clicks: defaults.bool(forKey: SettingsKey.keySounds),
            mistakes: defaults.bool(forKey: SettingsKey.mistakeSound),
            volume: Float(defaults.double(forKey: SettingsKey.soundVolume))
        )
        if defaults.bool(forKey: SettingsKey.systemWideHighlighting) {
            if !globalMonitor.isRunning { globalMonitor.start() }
        } else if globalMonitor.isRunning {
            globalMonitor.stop()
        }

        // Applies to every window, including the floating keyboard.
        let appearance = AppearanceChoice(rawValue: defaults.string(forKey: SettingsKey.appearance) ?? "") ?? .system
        let target: NSAppearance? = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance?.name != target?.name { NSApp.appearance = target }

        hud?.setOpacity(defaults.double(forKey: SettingsKey.hudOpacity))
        hud?.setClickThrough(defaults.bool(forKey: SettingsKey.hudClickThrough))

        let poppedOut = defaults.bool(forKey: SettingsKey.keyboardPoppedOut)
        // The floating keyboard belongs to practice. Popping out from another tab
        // switches to practice; other tabs show the keyboard docked instead.
        if poppedOut, lastPoppedOut == false, ui.tab != .practice { ui.tab = .practice }
        let floating = defaults.bool(forKey: SettingsKey.showKeyboard) && poppedOut && ui.tab == .practice
        if floating, hud?.isVisible == false { hud?.show() }
        if !floating, hud?.isVisible == true { hud?.hide() }

        // Popping out gets the big window out of the way and hands typing to the
        // floating keyboard. Popping back in brings the window back.
        if let last = lastPoppedOut, last != poppedOut {
            if floating {
                practiceWindow?.miniaturize(nil)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))  // let the minimize animation settle
                    self?.hud?.makeKey()
                }
            } else if !poppedOut {
                focusPracticeWindow()
            }
        }
        lastPoppedOut = poppedOut
    }
}

/// Floating panel content: the keyboard, with the drill text above it if enabled.
private struct FloatingKeyboard: View {
    let keyboard: KeyboardState
    let practice: PracticeModel
    let focus: PanelFocus
    let onDock: () -> Void
    @AppStorage(SettingsKey.showDrillInFloating) private var showDrill = true
    @AppStorage(SettingsKey.showStatsInFloating) private var showStats = true

    var body: some View {
        PracticeKeyboard(
            keyboard: keyboard, practice: practice, showsDrill: showDrill, showsStats: showStats,
            controls: AnyView(DockButton(action: onDock))
        )
        .windowDraggable(focus)
            // Accent outline while this panel is taking your typing.
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(focus.isKey ? 0.8 : 0), lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.15), value: focus.isKey)
    }
}

/// Puts the floating keyboard back in the main window. Faint until hovered.
private struct DockButton: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "pip.exit")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(.primary.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Dock the keyboard back in the main window")
        .foregroundStyle(KeyboardPalette(colorScheme).text)
        .opacity(hovering ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}

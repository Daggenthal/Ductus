import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case practice, race, text, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: "Practice"
        case .race: "Race"
        case .text: "Text"
        case .history: "History"
        }
    }
}

/// The main window: Practice, Race and History tabs, with Settings as a
/// panel that slides in from the right.
struct MainView: View {
    @Environment(AppUIState.self) private var ui
    @Environment(UpdateChecker.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var ui = ui
        Group {
            switch ui.tab {
            case .practice: PracticeView()
            case .race: RaceView()
            case .text: TextPracticeView()
            case .history: HistoryView()
            }
        }
        .inspector(isPresented: $ui.showSettings) {
            SettingsView()
                .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $ui.tab) {
                    ForEach(MainTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch with ⌘1 to ⌘4")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.setSettings(!ui.showSettings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        // An automatic check that finds an update opens the Software Update window.
        .onChange(of: updater.showWindow) { _, show in
            guard show else { return }
            openWindow(id: UpdateView.windowID)
            updater.showWindow = false
        }
        .onChange(of: ui.showSettings) { _, showing in
            if !showing { ui.settingsDidClose() }
        }
    }
}

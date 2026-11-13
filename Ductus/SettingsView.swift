import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceChoice.system
    @AppStorage(SettingsKey.showKeyboard) private var showKeyboard = true
    @AppStorage(SettingsKey.keyboardPoppedOut) private var poppedOut = false
    @AppStorage(SettingsKey.hudOpacity) private var opacity = 0.9
    @AppStorage(SettingsKey.hudClickThrough) private var clickThrough = false
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true
    @AppStorage(SettingsKey.showDrillInFloating) private var showDrillInFloating = true
    @AppStorage(SettingsKey.showStatsInFloating) private var showStatsInFloating = true
    @Environment(PracticeModel.self) private var practice
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows your macOS setting. Applies to the floating keyboard too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Toggle("Show keyboard", isOn: $showKeyboard)
                Toggle("Pop out into a floating window", isOn: $poppedOut)
                Toggle("Show drill text above the floating keyboard", isOn: $showDrillInFloating)
                Text("Keeps the words and the keys close together so your eyes do not have to travel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show stats above the floating keyboard", isOn: $showStatsInFloating)
                Text("Live speed and accuracy, the last drill, your focus key and unlock progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Floating opacity") {
                    Slider(value: $opacity, in: 0.2...1)
                        .frame(width: 200)
                }
                Toggle("Show physical key labels", isOn: $showPhysicalLabels)
                Text("A faint QWERTY letter in the corner of each key, showing what is printed on your real keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Floating click-through", isOn: $clickThrough)
                Text("Clicks pass through the floating keyboard to whatever is underneath. You cannot drag it or type into it while this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Progress") {
                LabeledContent("Layout", value: practice.layoutName)
                LabeledContent("Drills completed", value: "\(practice.profile?.drills.count ?? 0)")
                if !practice.isSavingProgress {
                    Text("Progress could not be saved this session. Check the log for details.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Progress is saved on this Mac, separately for each keyboard layout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset Progress…", role: .destructive) { confirmingReset = true }
                    .disabled(practice.profile == nil)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all progress for \(practice.layoutName)?",
            isPresented: $confirmingReset
        ) {
            Button("Reset Progress", role: .destructive) { practice.resetProgress() }
        } message: {
            Text("This deletes your key stats, unlocked letters and history for this layout. It cannot be undone.")
        }
    }
}

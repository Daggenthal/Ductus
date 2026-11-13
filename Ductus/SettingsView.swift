import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.showHUD) private var showHUD = true
    @AppStorage(SettingsKey.hudOpacity) private var opacity = 0.9
    @AppStorage(SettingsKey.hudClickThrough) private var clickThrough = false
    @AppStorage(SettingsKey.showPhysicalLabels) private var showPhysicalLabels = true

    var body: some View {
        Form {
            Section("Keyboard") {
                LabeledContent("Opacity") {
                    Slider(value: $opacity, in: 0.2...1)
                        .frame(width: 200)
                }
                Toggle("Show physical key labels", isOn: $showPhysicalLabels)
                Text("A faint QWERTY letter in the corner of each key, showing what is printed on your real keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Click-through", isOn: $clickThrough)
                Text("Clicks pass through the keyboard to whatever is underneath. You cannot drag it while this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

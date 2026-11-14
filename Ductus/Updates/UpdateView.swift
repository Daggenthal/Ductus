import AppKit
import DuctusEngine
import SwiftUI

/// The Software Update window. Nothing happens without a click: Download and
/// Install fetches and checks the update, then Ductus restarts into it.
struct UpdateView: View {
    static let windowID = "updates"

    @Environment(UpdateChecker.self) private var updater
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.systemWideHighlighting) private var systemWide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            VStack(alignment: .leading, spacing: 12) {
                Text("Checking for updates…").font(.headline)
                ProgressView().progressViewStyle(.linear)
            }
        case .upToDate:
            VStack(alignment: .leading, spacing: 8) {
                Text("Ductus is up to date").font(.headline)
                Text("Version \(updater.currentVersion.description) is the newest version.")
                    .foregroundStyle(.secondary)
                buttons { Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        case .available(let release):
            available(release)
        case .downloading(let release, let progress):
            VStack(alignment: .leading, spacing: 10) {
                Text("Downloading Ductus \(release.version.description)…").font(.headline)
                ProgressView(value: progress.fraction)
                Text(Self.progressLine(progress))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                buttons { Button("Cancel") { updater.cancelDownload() }.keyboardShortcut(.cancelAction) }
            }
        case .installing(let release):
            VStack(alignment: .leading, spacing: 10) {
                Text("Installing Ductus \(release.version.description)…").font(.headline)
                ProgressView().progressViewStyle(.linear)
                Text("Ductus will close and open again in a moment. Your progress and settings are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .updated(let from):
            VStack(alignment: .leading, spacing: 8) {
                Text("Updated to Ductus \(updater.currentVersion.description)").font(.headline)
                Text("You were on \(from) before. Your progress and settings are just as you left them.")
                    .foregroundStyle(.secondary)
                if systemWide {
                    Text("Typing in other apps: macOS asks for the Input Monitoring permission again after each update, because this version of Ductus is not notarized by Apple yet. Turn Ductus back on in System Settings › Privacy & Security › Input Monitoring.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons { Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Could not finish").font(.headline)
                Text(message).foregroundStyle(.secondary)
                buttons {
                    Button("Close") { dismiss() }
                    Button("Try Again") { updater.check(userInitiated: true) }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func available(_ release: UpdateChecker.Release) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ductus \(release.version.description) is available").font(.headline)
            Text(Self.versionLine(release, current: updater.currentVersion))
                .font(.callout)
                .foregroundStyle(.secondary)
            if !release.notes.isEmpty {
                ScrollView {
                    Text(Self.markdown(release.notes))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 180)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Ductus downloads the update, checks it, then closes and opens again as the new version. Your progress and settings are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            buttons {
                Button("View on GitHub") { NSWorkspace.shared.open(release.pageURL) }
                Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Download and Install") { updater.downloadAndInstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(release.archive == nil)
            }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.top, 4)
    }

    // MARK: - Text

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    static func versionLine(_ release: UpdateChecker.Release, current: AppVersion) -> String {
        var parts = [String(localized: "You have \(current.description).")]
        if let archive = release.archive { parts.append(String(localized: "Download size: \(megabytes(archive.size)).")) }
        if let date = release.published {
            parts.append(String(localized: "Released \(date.formatted(date: .abbreviated, time: .omitted))."))
        }
        return parts.joined(separator: " ")
    }

    static func progressLine(_ progress: UpdateChecker.State.Progress) -> String {
        var line = "\(Int(progress.fraction * 100))% · "
            + String(localized: "\(megabytes(progress.received)) of \(megabytes(progress.total))")
        if progress.speed > 0 { line += " · \(megabytes(Int64(progress.speed)))/s" }
        if let left = progress.secondsLeft {
            line += " · " + (left < 60
                ? String(localized: "about \(max(1, Int(left.rounded()))) s left")
                : String(localized: "about \(Int((left / 60).rounded())) min left"))
        }
        return line
    }

    /// Release notes are Markdown; line breaks are kept.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Ductus › Check for Updates…
struct UpdateCommands: Commands {
    let updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.check(userInitiated: true)
                openWindow(id: UpdateView.windowID)
            }
        }
    }
}

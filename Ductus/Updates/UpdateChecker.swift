import AppKit
import CryptoKit
import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// Checks GitHub for a newer release and, only when the person clicks
/// Download and Install, updates Ductus.
///
/// Ductus is sandboxed and cannot replace itself, so it downloads the release
/// zip, checks it against SHA256SUMS.txt, starts the bundled DuctusUpdater
/// helper and quits. The helper swaps the new version in and reopens Ductus.
/// Network use: only GitHub, only when checking or downloading. Nothing about
/// the person is sent.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: AppVersion
        let tag: String
        let name: String
        let notes: String
        let pageURL: URL
        let published: Date?
        let diskImage: Asset?
        /// The zip the updater installs from.
        let archive: Asset?
        let checksums: Asset?

        struct Asset: Equatable {
            let name: String
            let url: URL
            let size: Int64
        }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Progress)
        /// Downloaded and checked; Ductus is quitting so the helper can install it.
        case installing(Release)
        /// Shown once after an update: the version it came from.
        case updated(from: String)
        case failed(String)

        struct Progress: Equatable {
            var received: Int64
            var total: Int64
            /// Bytes per second, averaged since the start.
            var speed: Double
            var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }
            var secondsLeft: Double? { speed > 0 && total > received ? Double(total - received) / speed : nil }
        }
    }

    private(set) var state: State = .idle
    /// Shows the update window (set by checks the person started, or by a found update).
    var showWindow = false
    private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: Keys.lastChecked) as? Date

    static let releasesAPI = URL(string: "https://api.github.com/repos/Daggenthal/Ductus/releases/latest")!

    enum Keys {
        static let automatic = "checkForUpdatesAutomatically"
        static let lastChecked = "lastUpdateCheck"
        /// Set just before handing over to the helper: the version being replaced.
        static let updatingFrom = "updatingFromVersion"
    }

    /// At launch: says how the last update went, if there was one.
    func reportLastUpdate() {
        let defaults = UserDefaults.standard
        guard let from = defaults.string(forKey: Keys.updatingFrom) else { return }
        defaults.removeObject(forKey: Keys.updatingFrom)
        if CommandLine.arguments.contains("--update-failed") {
            state = .failed(String(localized: "The update could not be installed, so your current version was kept. Details are in ~/Library/Logs/DuctusUpdater.log."))
        } else if let old = AppVersion(from), currentVersion > old {
            state = .updated(from: from)
            Log.success("Updated from \(from) to \(currentVersion)")
        } else {
            return
        }
        showWindow = true
    }

    /// The running version. `DUCTUS_PRETEND_VERSION` (debug) lets you test the update flow.
    var currentVersion: AppVersion {
        if let fake = ProcessInfo.processInfo.environment["DUCTUS_PRETEND_VERSION"], let version = AppVersion(fake) {
            return version
        }
        let text = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return AppVersion(text) ?? AppVersion("0")!
    }

    @ObservationIgnored private var download: Task<Void, Never>?

    // MARK: - Checking

    /// Asks GitHub for the latest release. `userInitiated` checks always show the
    /// window; automatic ones only show it when there is an update.
    func check(userInitiated: Bool) {
        if case .downloading = state { showWindow = true; return }
        state = .checking
        if userInitiated { showWindow = true }
        Task {
            do {
                let release = try await fetchLatest()
                lastChecked = Date()
                UserDefaults.standard.set(lastChecked, forKey: Keys.lastChecked)
                if release.version > currentVersion {
                    state = .available(release)
                    showWindow = true
                    Log.info("Update available: \(release.version) (running \(currentVersion))")
                } else {
                    state = .upToDate
                    Log.info("Ductus is up to date (\(currentVersion))")
                }
            } catch {
                state = .failed(Self.describe(error))
                Log.warning("Update check failed: \(error)")
                if !userInitiated { state = .idle }
            }
        }
    }

    /// At launch: checks once a day, only if the person turned it on.
    func checkAutomaticallyIfDue() {
        guard UserDefaults.standard.bool(forKey: Keys.automatic) else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 24 * 60 * 60 { return }
        check(userInitiated: false)
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ductus-update-check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw UpdateError.noRelease }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.server }
        let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(json.tag_name), let page = URL(string: json.html_url) else {
            throw UpdateError.unreadable
        }
        func asset(_ match: (String) -> Bool) -> Release.Asset? {
            json.assets.first { match($0.name) }.flatMap { a in
                URL(string: a.browser_download_url).map { Release.Asset(name: a.name, url: $0, size: a.size) }
            }
        }
        return Release(
            version: version, tag: json.tag_name, name: json.name ?? json.tag_name, notes: json.body ?? "",
            pageURL: page, published: json.published_at.flatMap { ISO8601DateFormatter().date(from: $0) },
            diskImage: asset { $0.hasSuffix(".dmg") }, archive: asset { $0.hasSuffix(".zip") },
            checksums: asset { $0 == "SHA256SUMS.txt" }
        )
    }

    // MARK: - Downloading

    /// Where Ductus runs from. When macOS runs an app straight from Downloads it
    /// uses a temporary read-only copy ("App Translocation"), which cannot be updated.
    var cannotUpdateInPlace: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DuctusUpdater.app")
    }

    func downloadAndInstall() {
        guard case .available(let release) = state, let archive = release.archive else { return }
        guard !cannotUpdateInPlace else {
            state = .failed(String(localized: "Move Ductus into your Applications folder first, then open it from there and try again. macOS does not let apps update themselves while they run from Downloads."))
            return
        }
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            state = .failed(String(localized: "The updater is missing from this copy of Ductus. Download the new version from GitHub instead."))
            return
        }
        state = .downloading(release, .init(received: 0, total: archive.size, speed: 0))
        download = Task {
            do {
                let file = try await fetch(archive, release: release)
                Log.success("Downloaded and checked \(archive.name)")
                state = .installing(release)
                try await install(file)
            } catch is CancellationError {
                state = .available(release)
            } catch {
                state = .failed(Self.describe(error))
                Log.error("Update download failed: \(error)")
            }
        }
    }

    /// Hands over to the helper, which waits for Ductus to quit, swaps in the
    /// new version and opens it again.
    private func install(_ archive: URL) async throws {
        UserDefaults.standard.set(currentVersion.description, forKey: Keys.updatingFrom)
        // macOS does not pass launch arguments from a sandboxed app, so the
        // details go in a request file the helper reads (and deletes).
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuctusUpdate")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let request: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "archive": archive.path,
            "target": Bundle.main.bundlePath,
        ]
        try JSONSerialization.data(withJSONObject: request).write(to: folder.appendingPathComponent("request.json"))
        let requestFile = folder.appendingPathComponent("request.json")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        // Not awaited: the helper has no window and never reports "finished
        // launching", so waiting would stall for half a minute. Instead, the helper
        // deletes the request file as soon as it has read it, which means it is running.
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
            if let error { Log.error("Could not start the updater: \(error)") }
        }
        for _ in 0..<100 {
            if !FileManager.default.fileExists(atPath: requestFile.path) {
                Log.info("Updater started, quitting so it can install")
                try? await Task.sleep(for: .milliseconds(300))  // let the window show "Installing"
                NSApp.terminate(nil)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? FileManager.default.removeItem(at: requestFile)
        UserDefaults.standard.removeObject(forKey: Keys.updatingFrom)
        throw UpdateError.helperDidNotStart
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
    }

    private func fetch(_ image: Release.Asset, release: Release) async throws -> URL {
        // The checksum list first, so a bad download is caught before it is opened.
        guard let sumsAsset = release.checksums else { throw UpdateError.noChecksums }
        let (sumsData, _) = try await URLSession.shared.data(from: sumsAsset.url)
        guard let expected = Checksums.parse(String(decoding: sumsData, as: UTF8.self))[image.name] else {
            throw UpdateError.noChecksums
        }

        // URLSession downloads to a temporary file; a small loop reads its progress
        // for the progress bar. Hashing happens off the main thread afterward.
        let watcher = DownloadWatcher()
        let start = Date()
        let progressLoop = Task { @MainActor in
            while !Task.isCancelled {
                if let task = watcher.task {
                    let received = task.countOfBytesReceived
                    let total = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : image.size
                    let speed = Double(received) / max(0.001, Date().timeIntervalSince(start))
                    state = .downloading(release, .init(received: received, total: total, speed: speed))
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { progressLoop.cancel() }
        let (downloaded, response) = try await withTaskCancellationHandler {
            try await URLSession.shared.download(from: image.url, delegate: watcher)
        } onCancel: {
            watcher.task?.cancel()
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.server }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Ductus-update-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: downloaded, to: temporary)

        let actual = try await Self.sha256(of: temporary)
        guard actual == expected else {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdateError.checksumMismatch
        }

        return temporary
    }

    /// SHA-256 of a file, read in chunks off the main thread.
    nonisolated private static func sha256(of file: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    // MARK: - Errors

    enum UpdateError: Error {
        case noRelease, server, unreadable, noChecksums, checksumMismatch, helperDidNotStart
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case UpdateError.noRelease: String(localized: "There are no releases on GitHub yet.")
        case UpdateError.server: String(localized: "GitHub did not answer as expected. Try again in a little while.")
        case UpdateError.unreadable: String(localized: "The latest release could not be read.")
        case UpdateError.noChecksums: String(localized: "The release has no checksum for the download, so it was not saved.")
        case UpdateError.checksumMismatch: String(localized: "The download did not match its checksum, so it was deleted. Try again.")
        case UpdateError.helperDidNotStart: String(localized: "The updater did not start, so nothing was changed. Try again, or download the new version from GitHub.")
        case let error as URLError where error.code == .notConnectedToInternet: String(localized: "You are not connected to the internet.")
        default: String(localized: "Could not check for updates: \(error.localizedDescription)")
        }
    }
}

/// Keeps hold of the download task so its progress can be read and it can be cancelled.
private final class DownloadWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionTask?

    var task: URLSessionTask? { lock.withLock { _task } }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _task = task }
    }
}

/// The parts of GitHub's release JSON that Ductus reads.
private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
    let assets: [GitHubAsset]
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int64
    let browser_download_url: String
}

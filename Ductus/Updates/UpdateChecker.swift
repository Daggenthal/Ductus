import AppKit
import CryptoKit
import DuctusEngine
import DuctusLog
import Foundation
import Observation

/// Checks GitHub for a newer release and, only when asked, downloads it.
///
/// The person stays in control: Ductus never installs anything. It saves the
/// disk image to Downloads, checks it against the release's SHA256SUMS.txt and
/// opens it, and the person drags the new Ductus into Applications.
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
        case downloaded(Release, file: URL)
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
            diskImage: asset { $0.hasSuffix(".dmg") }, checksums: asset { $0 == "SHA256SUMS.txt" }
        )
    }

    // MARK: - Downloading

    func startDownload() {
        guard case .available(let release) = state, let image = release.diskImage else { return }
        state = .downloading(release, .init(received: 0, total: image.size, speed: 0))
        download = Task {
            do {
                let file = try await fetch(image, release: release)
                state = .downloaded(release, file: file)
                Log.success("Downloaded \(image.name)")
                NSWorkspace.shared.open(file)
            } catch is CancellationError {
                state = .available(release)
            } catch {
                state = .failed(Self.describe(error))
                Log.error("Update download failed: \(error)")
            }
        }
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
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        try FileManager.default.moveItem(at: downloaded, to: temporary)

        let actual = try await Self.sha256(of: temporary)
        guard actual == expected else {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdateError.checksumMismatch
        }

        // Into Downloads, without overwriting anything already there.
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var destination = downloads.appendingPathComponent(image.name)
        var copy = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = (image.name as NSString).deletingPathExtension
            destination = downloads.appendingPathComponent("\(base) \(copy).dmg")
            copy += 1
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
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

    func showInFinder(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    // MARK: - Errors

    enum UpdateError: Error {
        case noRelease, server, unreadable, noChecksums, checksumMismatch
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case UpdateError.noRelease: "There are no releases on GitHub yet."
        case UpdateError.server: "GitHub did not answer as expected. Try again in a little while."
        case UpdateError.unreadable: "The latest release could not be read."
        case UpdateError.noChecksums: "The release has no checksum for the download, so it was not saved."
        case UpdateError.checksumMismatch: "The download did not match its checksum, so it was deleted. Try again."
        case let error as URLError where error.code == .notConnectedToInternet: "You are not connected to the internet."
        default: "Could not check for updates: \(error.localizedDescription)"
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

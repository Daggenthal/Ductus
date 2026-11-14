import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Log levels and their terminal colors (see CLAUDE.md conventions).
public enum LogLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case success      // green
    case warning      // yellow
    case error        // red
    case crashHeader  // bold red
    case stackFrame   // cyan

    var ansiCode: String? {
        switch self {
        case .debug, .info: nil
        case .success: "\u{1B}[32m"
        case .warning: "\u{1B}[33m"
        case .error: "\u{1B}[31m"
        case .crashHeader: "\u{1B}[1;31m"
        case .stackFrame: "\u{1B}[36m"
        }
    }
}

/// Small colored logger. Writes to stderr.
///
/// - Color is used only when stderr is a terminal and neither `DUCTUS_NO_COLOR`
///   nor `NO_COLOR` is set. Xcode's console and saved logs get plain text.
/// - Debug messages print only in debug mode (`DUCTUS_DEBUG=1`, or `Log.isDebug = true`).
public enum Log {
    private static let state = LogState()

    public static var isDebug: Bool {
        get { state.isDebug }
        set { state.isDebug = newValue }
    }

    /// `true` when `DUCTUS_DEBUG=1` was set at launch (the settings toggle cannot turn it off).
    public static let debugFromEnvironment = ProcessInfo.processInfo.environment["DUCTUS_DEBUG"] == "1"

    /// When set, every line is also appended to this file as plain text (no color).
    /// The file is started over when it grows past `maxLogFileSize`.
    public static var logFile: URL? {
        get { state.logFile }
        set { state.setLogFile(newValue) }
    }

    public static let maxLogFileSize = 5_000_000

    public static func debug(_ message: @autoclosure () -> String) {
        guard isDebug else { return }
        write(message(), level: .debug)
    }
    public static func info(_ message: String) { write(message, level: .info) }
    public static func success(_ message: String) { write(message, level: .success) }
    public static func warning(_ message: String) { write(message, level: .warning) }
    public static func error(_ message: String) { write(message, level: .error) }
    public static func crash(_ header: String, frames: [String]) {
        write(header, level: .crashHeader)
        for frame in frames { write(frame, level: .stackFrame) }
    }

    public static func write(_ message: String, level: LogLevel) {
        let line = format(message, level: level, colored: state.useColor) + "\n"
        FileHandle.standardError.write(Data(line.utf8))
        state.appendToFile(format(message, level: level, colored: false))
    }

    /// Pure formatting, exposed for tests.
    public static func format(_ message: String, level: LogLevel, colored: Bool) -> String {
        let text = level == .debug ? "[debug] \(message)" : message
        guard colored, let code = level.ansiCode else { return text }
        return code + text + "\u{1B}[0m"
    }

    static func shouldUseColor(environment: [String: String], isTTY: Bool) -> Bool {
        guard isTTY else { return false }
        return environment["DUCTUS_NO_COLOR"] == nil && environment["NO_COLOR"] == nil
    }
}

private final class LogState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isDebug: Bool
    let useColor: Bool

    init() {
        let env = ProcessInfo.processInfo.environment
        _isDebug = env["DUCTUS_DEBUG"] == "1"
        useColor = Log.shouldUseColor(environment: env, isTTY: isatty(fileno(stderr)) != 0)
    }

    var isDebug: Bool {
        get { lock.withLock { _isDebug } }
        set { lock.withLock { _isDebug = newValue } }
    }

    private var _logFile: URL?
    private var handle: FileHandle?
    private let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    var logFile: URL? { lock.withLock { _logFile } }

    func setLogFile(_ url: URL?) {
        lock.withLock {
            try? handle?.close()
            handle = nil
            _logFile = url
            guard let url else { return }
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if !manager.fileExists(atPath: url.path) || size > Log.maxLogFileSize {
                manager.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
    }

    func appendToFile(_ line: String) {
        lock.withLock {
            guard let handle else { return }
            let stamped = "\(timestamp.string(from: Date()))  \(line)\n"
            try? handle.write(contentsOf: Data(stamped.utf8))
        }
    }
}

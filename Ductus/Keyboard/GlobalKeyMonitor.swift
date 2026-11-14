import AppKit
import CoreGraphics
import DuctusLog

/// Opt-in, listen-only view of key presses in other apps, so the floating
/// keyboard can light up while you type anywhere.
///
/// Privacy: this needs the Input Monitoring permission. Only key codes and
/// modifier state are passed on, to light up keys. Nothing is stored or
/// written anywhere. macOS blocks it in password fields (secure input).
@MainActor
final class GlobalKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Receives each event while another app is active.
    private let onEvent: (NSEvent) -> Void

    init(onEvent: @escaping (NSEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { tap != nil }

    /// Whether Input Monitoring is granted. Does not prompt.
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt (first time only). Returns current access.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts listening. Returns `false` if permission is missing or the tap failed.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.hasPermission else {
            Log.warning("System-wide highlighting needs Input Monitoring permission")
            return false
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: globalKeyTapCallback, userInfo: refcon
        ) else {
            Log.error("Could not create the key event tap. Try restarting Ductus after granting permission.")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Log.success("System-wide highlighting on")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        self.source = nil
        Log.info("System-wide highlighting off")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            // Inside Ductus the normal key handling already runs.
            guard !NSApp.isActive, let nsEvent = NSEvent(cgEvent: event) else { return }
            onEvent(nsEvent)
        }
    }
}

/// C callback for the event tap. Runs on the main run loop.
private func globalKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        // The tap's run loop source is on the main run loop, so this is the main thread.
        nonisolated(unsafe) let event = event
        nonisolated(unsafe) let refcon = refcon
        MainActor.assumeIsolated {
            let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
        }
    }
    return Unmanaged.passUnretained(event)
}

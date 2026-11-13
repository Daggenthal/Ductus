import AppKit
import Observation
import SwiftUI

/// Whether the floating panel is currently the typing target. Views read this
/// to show a focus outline.
@MainActor
@Observable
final class PanelFocus {
    var isKey = false
}

/// Borderless floating panel that shows the keyboard.
///
/// Non-activating: clicking it makes it the typing target (key window) without
/// activating the app, so the main window can stay hidden behind other apps.
/// In click-through mode it never takes focus. Drag it anywhere by its background.
@MainActor
final class KeyboardHUD {
    static let panelID = NSUserInterfaceItemIdentifier("dev.daggenthal.ductus.keyboardPanel")

    private let panel: HUDPanel
    private var observers: [NSObjectProtocol] = []

    init<Content: View>(content: Content, focus: PanelFocus) {
        panel = HUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.panelID
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = DraggableHostingView(rootView: content)
        // Panel resizes itself when the content changes (e.g. drill text toggled).
        hosting.sizingOptions = [.intrinsicContentSize, .minSize, .maxSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        // Remember where the user put it. Default: bottom center of the main screen.
        if !panel.setFrameUsingName("DuctusKeyboardHUD"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 40))
        }
        panel.setFrameAutosaveName("DuctusKeyboardHUD")

        for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { focus.isKey = isKey }
            })
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    /// 0.2 to 1.
    func setOpacity(_ value: Double) { panel.alphaValue = max(0.2, min(1, value)) }

    /// When on, clicks go through to whatever is underneath. You cannot drag it
    /// or type into it then.
    func setClickThrough(_ on: Bool) {
        panel.ignoresMouseEvents = on
        if on, panel.isKeyWindow { panel.resignKey() }
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

/// Lets the user drag the borderless panel by clicking anywhere on it.
/// A click also makes it the typing target.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

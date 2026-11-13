import AppKit
import SwiftUI

/// Borderless floating panel that shows the keyboard.
///
/// Non-activating, so clicking or dragging it never takes focus away from
/// the window you are typing in. Drag it anywhere by its background.
@MainActor
final class KeyboardHUD {
    private let panel: HUDPanel

    init<Content: View>(content: Content) {
        panel = HUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = DraggableHostingView(rootView: content
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        // Remember where the user put it. Default: bottom center of the main screen.
        if !panel.setFrameUsingName("DuctusKeyboardHUD"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 40))
        }
        panel.setFrameAutosaveName("DuctusKeyboardHUD")
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggle() { isVisible ? hide() : show() }

    /// 0.2 to 1.
    func setOpacity(_ value: Double) { panel.alphaValue = max(0.2, min(1, value)) }

    /// When on, clicks go through to whatever is underneath. You cannot drag it then.
    func setClickThrough(_ on: Bool) { panel.ignoresMouseEvents = on }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the user drag the borderless panel by clicking anywhere on it.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

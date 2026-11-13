import AppKit
import Observation
import SwiftUI

/// Whether the floating panel is currently the typing target. Views read this
/// to show a focus outline.
@MainActor
@Observable
final class PanelFocus {
    var isKey = false
    /// The floating panel, so SwiftUI content can move it (see `windowDraggable`).
    @ObservationIgnored weak var window: NSWindow?
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
        focus.window = panel
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

    /// Makes the panel the typing target.
    func makeKey() {
        guard panel.isVisible, panel.canBecomeKey else { return }
        panel.makeKey()
    }

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

/// A click anywhere makes the panel the typing target. Dragging is done in
/// SwiftUI (`windowDraggable`) so buttons on the panel still get clicks.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension View {
    /// Drag the panel by this view's background. Starts only once the mouse
    /// moves, so plain clicks still reach buttons.
    func windowDraggable(_ focus: PanelFocus) -> some View {
        modifier(WindowDragModifier(focus: focus))
    }
}

private struct WindowDragModifier: ViewModifier {
    let focus: PanelFocus
    @State private var start: (mouse: NSPoint, origin: NSPoint)?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in
                        guard let window = focus.window else { return }
                        // Screen coordinates, so moving the window does not feed back into the drag.
                        let mouse = NSEvent.mouseLocation
                        let begin = start ?? (mouse, window.frame.origin)
                        start = begin
                        window.setFrameOrigin(NSPoint(
                            x: begin.origin.x + mouse.x - begin.mouse.x,
                            y: begin.origin.y + mouse.y - begin.mouse.y
                        ))
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

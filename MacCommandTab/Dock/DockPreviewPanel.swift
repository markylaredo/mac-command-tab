import AppKit
import SwiftUI

/// The Dock preview popup.
///
/// A non-activating panel, like `SwitcherPanel`: it accepts mouse input, floats
/// above ordinary windows, and never becomes key or main, so clicking a preview
/// cannot pull keyboard focus away from whatever the user was typing in.
@MainActor
final class DockPreviewPanel: NSPanel {
    private let model: DockPreviewViewModel
    private var onDidHide: (() -> Void)?

    init(
        livePreviewCoordinator: LivePreviewCoordinator,
        onSelect: @escaping (WindowID) -> Void,
        onClose: @escaping (WindowID) -> Void,
        onPointerEntered: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onHover: @escaping (WindowID, Bool) -> Void = { _, _ in }
    ) {
        model = DockPreviewViewModel()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // Excluded from screen capture so the popup never appears inside its own
        // previews, or inside the switcher's previews.
        sharingType = .none

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let visualEffectView = NSVisualEffectView(frame: .zero)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        container.addSubview(visualEffectView)

        let hostingView = NSHostingView(
            rootView: DockPreviewView(
                model: model,
                onSelect: onSelect,
                onClose: onClose,
                onHover: onHover,
                onPointerEntered: onPointerEntered,
                onPointerExited: onPointerExited,
                livePreviewCoordinator: livePreviewCoordinator
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Previews are transient; they should never be restorable or appear in the
    /// window menu.
    override var isRestorable: Bool {
        get { false }
        set {}
    }

    func update(
        applicationName: String,
        applicationIcon: NSImage?,
        cards: [DockPreviewCard],
        layout: DockPreviewLayout
    ) {
        model.applicationName = applicationName
        model.applicationIcon = applicationIcon
        model.cards = cards
        model.layout = layout
    }

    func updatePreview(_ preview: WindowPreview, for windowID: WindowID) {
        guard let index = model.cards.firstIndex(where: { $0.id == windowID }) else { return }
        let existing = model.cards[index]
        // Skip identical frames so SwiftUI is not invalidated needlessly.
        guard existing.preview?.id != preview.id else { return }
        model.cards[index] = DockPreviewCard(
            window: existing.window,
            preview: preview,
            canClose: existing.canClose
        )
    }

    var displayedWindowIDs: [WindowID] { model.cards.map(\.id) }
    var currentLayout: DockPreviewLayout { model.layout }

    /// The frame already on screen for a window, so a list update can keep it
    /// instead of flashing a placeholder.
    func currentPreview(for windowID: WindowID) -> WindowPreview? {
        model.cards.first { $0.id == windowID }?.preview
    }

    func present(at origin: CGPoint, size: CGSize, animated: Bool) {
        let target = NSRect(origin: origin, size: size)
        let isFirstPresentation = !isVisible
        if isFirstPresentation {
            setFrame(target.insetBy(dx: size.width * 0.02, dy: size.height * 0.02), display: false)
            alphaValue = 0
            orderFrontRegardless()
        } else {
            setFrame(target, display: true)
        }

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            alphaValue = 1
            setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            // Short and small: the popup should feel attached to the Dock icon,
            // not fly in.
            context.duration = isFirstPresentation ? 0.14 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    func dismiss(animated: Bool) {
        guard isVisible else {
            onDidHide?()
            return
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.alphaValue = 1
            }
        })
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible { onDidHide?() }
    }

    func setDidHideHandler(_ handler: @escaping () -> Void) {
        onDidHide = handler
    }

    /// Whether `screenPoint` is inside the panel's current frame.
    func contains(_ screenPoint: CGPoint) -> Bool {
        isVisible && frame.insetBy(dx: -2, dy: -2).contains(screenPoint)
    }
}

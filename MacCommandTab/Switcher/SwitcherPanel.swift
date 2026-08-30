import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
    private let model = SwitcherViewModel()
    private var finalFrame = NSRect.zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 226),
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
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = NSHostingView(rootView: SwitcherView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(windows: [WindowInfo], selectedIndex: Int) {
        guard !windows.isEmpty else { return }
        model.windows = windows
        model.selectedIndex = min(max(selectedIndex, 0), windows.count - 1)

        let screen = screenContainingMouse() ?? NSScreen.main
        let availableWidth = max(360, (screen?.visibleFrame.width ?? 900) - 80)
        let preset = model.preset
        let contentWidth: CGFloat
        switch preset {
        case .circle:
            contentWidth = 680
        case .tile:
            let columns = (windows.count + 1) / 2
            contentWidth = CGFloat(columns) * preset.cardWidth
                + CGFloat(max(columns - 1, 0)) * preset.cardSpacing
                + 28
        case .carousel:
            contentWidth = CGFloat(windows.count) * preset.cardWidth
                + CGFloat(max(windows.count - 1, 0)) * preset.cardSpacing
                + 26
        }
        let minimumWidth: CGFloat = preset == .circle ? 520 : 292
        let panelWidth = min(max(minimumWidth, contentWidth), min(1_100, availableWidth))
        let panelSize = NSSize(width: panelWidth, height: preset.panelHeight)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        finalFrame = NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        let initialFrame = finalFrame.insetBy(dx: panelSize.width * 0.01, dy: panelSize.height * 0.01)
        setFrame(initialFrame, display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(finalFrame, display: true)
        }
    }

    func select(_ index: Int) {
        guard model.windows.indices.contains(index) else { return }
        model.selectedIndex = index
    }

    func updatePreviews(_ previews: [WindowID: WindowPreview]) {
        model.previews = previews
    }

    func setPreset(_ preset: SwitcherPreset) {
        model.preset = preset
    }

    func setTheme(_ theme: SwitcherTheme) {
        model.theme = theme
    }

    func setGlassEnabled(_ enabled: Bool) {
        model.glassEnabled = enabled
    }

    func setSelectionEffect(_ effect: SwitcherSelectionEffect) {
        model.selectionEffect = effect
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.alphaValue = 1
            }
        })
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

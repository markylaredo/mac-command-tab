import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
    private let model = SwitcherViewModel()
    private let layoutCalculator = SwitcherLayoutCalculator()
    private var finalFrame = NSRect.zero
    private weak var targetScreen: NSScreen?

    init(livePreviewCoordinator: LivePreviewCoordinator) {
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
        contentView = NSHostingView(
            rootView: AdaptiveSwitcherView(
                model: model,
                livePreviewCoordinator: livePreviewCoordinator
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var currentPreviewSize: CGSize { model.layout.previewSize }
    var targetDisplayScale: CGFloat { targetScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    @discardableResult
    func show(windows: [WindowInfo], selectedIndex: Int) -> SwitcherLayout {
        guard !windows.isEmpty else { return .empty }
        model.windows = windows
        model.selectedIndex = min(max(selectedIndex, 0), windows.count - 1)
        model.searchQuery = ""

        let screen = screenContainingMouse() ?? NSScreen.main
        targetScreen = screen
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let layout = layoutCalculator.calculateLayout(
            itemCount: windows.count,
            availableSize: visibleFrame.size,
            appearance: model.appearance
        )
        model.layout = layout
        finalFrame = centeredFrame(size: layout.panelSize, in: visibleFrame)
        let initialFrame = finalFrame.insetBy(dx: layout.panelSize.width * 0.01, dy: layout.panelSize.height * 0.01)
        setFrame(initialFrame, display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(finalFrame, display: true)
        }
        return layout
    }

    @discardableResult
    func update(
        windows: [WindowInfo],
        selectedIndex: Int?,
        query: String,
        animated: Bool
    ) -> SwitcherLayout {
        model.windows = windows
        model.selectedIndex = selectedIndex ?? -1
        model.searchQuery = query
        let visibleFrame = targetScreen?.visibleFrame
            ?? screenContainingMouse()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let layout = layoutCalculator.calculateLayout(
            itemCount: windows.count,
            availableSize: visibleFrame.size,
            appearance: model.appearance
        )
        model.layout = layout
        finalFrame = centeredFrame(size: layout.panelSize, in: visibleFrame)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(finalFrame, display: true)
            }
        } else {
            setFrame(finalFrame, display: true)
        }
        return layout
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

    func setAppearance(_ appearance: SwitcherAppearance) {
        model.appearance = appearance
        guard isVisible else { return }
        _ = update(
            windows: model.windows,
            selectedIndex: model.selectedIndex,
            query: model.searchQuery,
            animated: true
        )
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

    private func centeredFrame(size: CGSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

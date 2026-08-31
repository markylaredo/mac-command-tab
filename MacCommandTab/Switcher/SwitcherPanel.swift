import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
    private let model = SwitcherViewModel()
    private let layoutCalculator = SwitcherLayoutCalculator()
    private var finalFrame = NSRect.zero
    private weak var targetScreen: NSScreen?
    private weak var visualEffectView: NSVisualEffectView?
    private let onDidHide: () -> Void

    init(
        livePreviewCoordinator: LivePreviewCoordinator,
        onHoverSelection: @escaping (Int) -> Void,
        onClickSelection: @escaping (Int) -> Void,
        onDidHide: @escaping () -> Void
    ) {
        self.onDidHide = onDidHide
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
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let visualEffectView = NSVisualEffectView(frame: .zero)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        container.addSubview(visualEffectView)
        self.visualEffectView = visualEffectView

        let hostingView = NSHostingView(
            rootView: AdaptiveSwitcherView(
                model: model,
                livePreviewCoordinator: livePreviewCoordinator,
                onHoverSelection: onHoverSelection,
                onClickSelection: onClickSelection
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

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible { onDidHide() }
    }

    @discardableResult
    func show(windows: [WindowInfo], selectedIndex: Int) -> SwitcherLayout {
        updateVisualEffectVisibility()
        let activeWindowIDs = Set(windows.map(\.id))
        model.previews = model.previews.filter { activeWindowIDs.contains($0.key) }
        model.windows = windows
        model.selectedIndex = windows.isEmpty ? -1 : min(max(selectedIndex, 0), windows.count - 1)
        model.searchQuery = ""

        let screen = screenContainingMouse() ?? NSScreen.main
        targetScreen = screen
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let layout = layoutCalculator.calculateLayout(
            itemCount: windows.count,
            availableSize: layoutAvailableSize(in: visibleFrame),
            appearance: model.appearance,
            searchActive: false
        )
        model.layout = layout
        finalFrame = positionedFrame(size: layout.panelSize, in: visibleFrame)
        let initialFrame = finalFrame.insetBy(dx: layout.panelSize.width * 0.01, dy: layout.panelSize.height * 0.01)
        setFrame(initialFrame, display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 0.16
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
            availableSize: layoutAvailableSize(in: visibleFrame),
            appearance: model.appearance,
            searchActive: !query.isEmpty
        )
        model.layout = layout
        finalFrame = positionedFrame(size: layout.panelSize, in: visibleFrame)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
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

    func keepVisibleAbovePreview() {
        guard isVisible else { return }
        orderFrontRegardless()
    }

    func updatePreview(_ preview: WindowPreview, for windowID: WindowID) {
        model.previews[windowID] = preview
    }

    var currentPreviewSize: CGSize { model.layout.previewSize }
    var targetDisplayScale: CGFloat {
        targetScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
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
        updateVisualEffectVisibility()
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

    private func layoutAvailableSize(in visibleFrame: NSRect) -> CGSize {
        CGSize(width: visibleFrame.width, height: visibleFrame.height * 0.46)
    }

    private func positionedFrame(size: CGSize, in visibleFrame: NSRect) -> NSRect {
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + min(24, visibleFrame.height * 0.025),
            width: size.width,
            height: size.height
        )
    }

    private func updateVisualEffectVisibility() {
        visualEffectView?.isHidden = !model.glassEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

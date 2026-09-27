@preconcurrency import AppKit
import CoreGraphics
import Foundation

/// Drives the Dock hover previews: pointer monitoring, application resolution,
/// window selection, preview pipelines, and activation.
///
/// This is the Dock feature's equivalent of `SwitcherCoordinator`. It owns the
/// interaction but not the machinery: windows come from `WindowTracker`,
/// previews from `LivePreviewCoordinator`, and activation from `WindowActivator`.
@MainActor
final class DockWindowPreviewController {
    private let diagnostics = DockHoverDiagnostics()
    private let resolver: DockApplicationResolving
    private let tracker: WindowTracker
    private let activator: WindowActivator
    private let closer = WindowCloser()
    private let layoutCalculator = DockPreviewLayoutCalculator()
    private let previewService: WindowPreviewService
    private let livePreviewCoordinator: LivePreviewCoordinator
    private let monitor: DockHoverMonitor
    private var stateMachine = DockHoverStateMachine()

    private lazy var panel = DockPreviewPanel(
        livePreviewCoordinator: livePreviewCoordinator,
        onSelect: { [weak self] windowID in self?.handleSelection(windowID) },
        onClose: { [weak self] windowID in self?.handleClose(windowID) },
        onPointerEntered: { [weak self] in self?.handlePreviewPointerEntered() },
        onPointerExited: { [weak self] in self?.handlePreviewPointerExited() },
        onHover: { [weak self] id, hovering in self?.handleCardHover(id, hovering: hovering) }
    )

    private var originalWindow: WindowInfo?
    private var hoveredWindowID: WindowID?
    private var cardHoverTask: Task<Void, Never>?
    private let hoverActivator = WindowActivator()

    private var hoverTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var changeObserverToken: UUID?
    private var activeApplication: NSRunningApplication?
    private var activeDockFrame: CGRect?
    /// The tile the pointer is currently on, which is not necessarily the one the
    /// visible panel belongs to. Committed to `activeApplication` only when a
    /// preview is actually presented.
    private var pendingApplication: NSRunningApplication?
    private var pendingDockFrame: CGRect?
    private var presentedWindowIDs: [WindowID] = []
    private var isEnabled = DockPreviewPreference.isEnabled
    private var hoverDelay = DockPreviewPreference.hoverDelay

    /// Why the feature can or cannot currently run. Surfaced in the menu bar so a
    /// missing permission or a changed Dock hierarchy is diagnosable without
    /// attaching a debugger.
    private(set) var availability: DockPreviewAvailability = .ready
    var onAvailabilityChanged: ((DockPreviewAvailability) -> Void)?
    private var accessibilityGranted = AccessibilityPermission.isGranted

    /// Consulted before presenting. An open switcher always wins, because both
    /// features drive the same preview machinery and only one may be active.
    var isSwitcherSessionActive: () -> Bool = { false }

    /// The preview style to use, supplied by the coordinator that owns the
    /// setting. Read at presentation time rather than held from launch, so a
    /// change made in Settings applies to the next hover. Taken as a closure so
    /// there is exactly one source of truth rather than a copy that can drift.
    var previewMode: () -> PreviewMode = { PreviewMode.saved }

    init(
        resolver: DockApplicationResolving,
        tracker: WindowTracker,
        activator: WindowActivator,
        livePreviewCoordinator: LivePreviewCoordinator,
        previewService: WindowPreviewService,
        monitor: DockHoverMonitor
    ) {
        self.resolver = resolver
        self.tracker = tracker
        self.activator = activator
        self.livePreviewCoordinator = livePreviewCoordinator
        self.previewService = previewService
        self.monitor = monitor
    }

    // MARK: - Lifecycle

    func start() {
        livePreviewCoordinator.onPreviewUpdated = { [weak self] windowID, preview in
            self?.panel.updatePreview(preview, for: windowID)
        }
        panel.setDidHideHandler { [weak self] in
            self?.handlePanelHidden()
        }
        changeObserverToken = tracker.addChangeObserver { [weak self] _ in
            self?.refreshPresentedWindows()
        }
        // The active zone spans both halves of the interaction, so the monitor
        // keeps reporting while the pointer crosses from the Dock into the panel.
        monitor.activeZoneProbe = { [weak self] screenPoint in
            guard let self else { return false }
            return self.resolver.isWithinDockRegion(screenPoint)
                || self.panel.contains(screenPoint)
        }
        monitor.onPointerMoved = { [weak self] screenPoint in
            self?.handlePointerMoved(to: screenPoint)
        }
        monitor.start()
        applyEnabledState()
        DockHoverTrace.shared.startIfRequested()
        diagnostics.log("Dock hover previews started enabled=\(isEnabled)")
    }

    func stop() {
        finishHoverPreview()
        monitor.stop()
        monitor.onPointerMoved = nil
        cancelTimers()
        if let changeObserverToken {
            tracker.removeChangeObserver(changeObserverToken)
            self.changeObserverToken = nil
        }
        livePreviewCoordinator.onPreviewUpdated = nil
        livePreviewCoordinator.stopSession()
        panel.dismiss(animated: false)
        panel.orderOut(nil)
        stateMachine.reset()
        activeApplication = nil
        activeDockFrame = nil
        pendingApplication = nil
        pendingDockFrame = nil
        presentedWindowIDs = []
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        DockPreviewPreference.save(enabled: enabled)
        applyEnabledState()
    }

    func setHoverDelay(milliseconds: Int) {
        hoverDelay = .milliseconds(DockHoverStateMachine.clampedHoverDelay(milliseconds: milliseconds))
        DockPreviewPreference.save(hoverDelayMilliseconds: milliseconds)
    }

    /// Called when Accessibility permission changes. Previews cannot resolve a
    /// Dock application without it, and any visible popup must go.
    func applyAccessibilityPermission(granted: Bool) {
        accessibilityGranted = granted
        guard granted else {
            updateAvailability(.needsAccessibilityPermission)
            apply(stateMachine.permissionsRevoked())
            return
        }
        applyEnabledState()
    }

    private func applyEnabledState() {
        if !isEnabled {
            monitor.stop()
            updateAvailability(.disabled)
            apply(stateMachine.dismissImmediately())
        } else if !accessibilityGranted {
            monitor.stop()
            updateAvailability(.needsAccessibilityPermission)
        } else {
            monitor.start()
            updateAvailability(.ready)
        }
    }

    private func updateAvailability(_ availability: DockPreviewAvailability) {
        guard availability != self.availability else { return }
        self.availability = availability
        onAvailabilityChanged?(availability)
    }

    // MARK: - Pointer handling

    /// Deduplicates pointer diagnostics so a moving pointer produces one line per
    /// state change rather than one per sample.
    private var pointerOutcomeLog = DockHoverChangeLog<String>()

    private func logPointerOutcome(_ outcome: String) {
        DockHoverTrace.shared.record("pointer: \(outcome)")
        guard pointerOutcomeLog.shouldLog(outcome) else { return }
        diagnostics.log("pointer outcome: \(outcome)")
    }

    private func handlePointerMoved(to screenPoint: CGPoint) {
        guard isEnabled else {
            logPointerOutcome("disabled")
            return
        }
        guard AccessibilityPermission.isGranted else {
            logPointerOutcome("no-accessibility")
            return
        }
        // Never compete with an open switcher.
        guard !isSwitcherSessionActive() else {
            if stateMachine.isPreviewVisible {
                apply(stateMachine.dismissImmediately())
            }
            logPointerOutcome("switcher-active")
            return
        }

        let isInDockRegion = resolver.isWithinDockRegion(screenPoint)
        let resolved = resolver.application(at: screenPoint)
        let application = resolved.map {
            DockResolvedApplication(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }

        // Recorded only when it changes. This one line distinguishes the three
        // ways the feature can fail to appear: the pointer never reaching the
        // Dock, reaching it but resolving no tile, or resolving a tile with no
        // switchable windows.
        logPointerOutcome(
            application.map { "resolved:\($0.localizedName ?? "?")" }
                ?? (isInDockRegion ? "over-dock-no-app-tile" : "not-near-dock")
        )

        // The tile under the pointer is recorded as *pending*, not active. While
        // a preview for the previous application is still on screen, the panel
        // must keep showing that application's windows until the new one is
        // ready to replace them.
        if application != nil, let resolved {
            pendingDockFrame = dockFrame(for: resolved, at: screenPoint)
            pendingApplication = resolved
        }

        // The panel is part of the interaction region, so a pointer inside it
        // must never be treated as having left.
        if panel.contains(screenPoint) {
            apply(stateMachine.pointerEnteredPreviewPanel())
            return
        }
        apply(stateMachine.pointerExitedPreviewPanel())

        apply(stateMachine.pointerMoved(to: application, isWithinDockRegion: isInDockRegion))
    }

    /// The Dock tile frame for a resolved application, used to anchor the panel.
    /// Read from the resolver's current layout rather than re-queried: the tile
    /// the pointer is on is the tile containing the point.
    private func dockFrame(for application: NSRunningApplication, at screenPoint: CGPoint) -> CGRect {
        // Prefer the tile the pointer is actually inside. Falling back to a
        // point-sized anchor keeps positioning sane if the layout changed
        // between the region check and this call.
        resolver.dockItemFrame(at: screenPoint) ?? CGRect(origin: screenPoint, size: .zero)
    }

    private func handlePreviewPointerEntered() {
        apply(stateMachine.pointerEnteredPreviewPanel())
    }

    private func handlePreviewPointerExited() {
        apply(stateMachine.pointerExitedPreviewPanel())
    }

    // MARK: - Effects

    private func apply(_ effects: [DockHoverEffect]) {
        for effect in effects {
            switch effect {
            case let .scheduleShow(application):
                scheduleShow(for: application)
            case .cancelScheduledShow:
                hoverTask?.cancel()
                hoverTask = nil
            case let .present(application):
                present(application)
            case .scheduleDismiss:
                scheduleDismiss()
            case .cancelScheduledDismiss:
                dismissTask?.cancel()
                dismissTask = nil
            case .dismiss:
                dismiss()
            }
        }
    }

    private func scheduleShow(for application: DockResolvedApplication) {
        hoverTask?.cancel()
        let delay = hoverDelay
        hoverTask = Task { @MainActor [weak self] in
            // Cancellation is the debounce: every new candidate cancels the
            // previous wait, so the request only fires once the pointer settles.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.apply(self.stateMachine.hoverDelayElapsed(for: application))
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let grace = DockHoverStateMachine.defaultDismissGracePeriod
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self else { return }
            self.dismissTask = nil
            self.apply(self.stateMachine.dismissGracePeriodElapsed())
        }
    }

    private func cancelTimers() {
        hoverTask?.cancel()
        hoverTask = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    // MARK: - Presentation

    private func present(_ application: DockResolvedApplication) {
        guard let running = NSRunningApplication(processIdentifier: application.processIdentifier) else {
            diagnostics.log("Dock application disappeared before presentation")
            apply(stateMachine.dismissImmediately())
            return
        }

        let windows = tracker.windows(for: application.processIdentifier)
        guard !windows.isEmpty else {
            // An application with no usable windows gets no popup at all.
            DockHoverTrace.shared.record(
                "zero windows for \(running.localizedName ?? "?") pid=\(application.processIdentifier)"
            )
            diagnostics.log("Dock application had zero switchable windows pid=\(application.processIdentifier)")
            apply(stateMachine.dismissImmediately())
            return
        }

        DockHoverTrace.shared.record(
            "presented: \(running.localizedName ?? "?") windows=\(windows.count)"
        )
        diagnostics.log("Dock preview requested name=\(running.localizedName ?? "?") windows=\(windows.count)")
        // The window list and the panel are replaced together, so the content and
        // the tile it is anchored to always describe the same application.
        if activeApplication?.processIdentifier != running.processIdentifier { finishHoverPreview() }
        activeApplication = running
        activeDockFrame = pendingDockFrame ?? activeDockFrame
        presentPanel(for: running, windows: windows)
    }

    private func presentPanel(for application: NSRunningApplication, windows: [WindowInfo]) {
        let screen = screen(containing: activeDockFrame ?? CGRect(origin: .zero, size: .zero))
            ?? screen(containingPoint: NSEvent.mouseLocation)
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let dockEdge = DockScreenEdge.current

        let layout = layoutCalculator.calculateLayout(
            itemCount: windows.count,
            availableSize: visibleFrame.size,
            dockEdge: dockEdge,
            displayScale: screen?.backingScaleFactor ?? 2,
            preferredItemWidth: CGFloat(DockPreviewPreference.thumbnailWidth)
        )

        let cards = windows.map { window in
            DockPreviewCard(window: window, preview: nil, canClose: closer.canClose(window))
        }
        panel.update(
            applicationName: application.localizedName ?? "Application",
            applicationIcon: windows.first?.icon,
            cards: cards,
            layout: layout
        )

        let origin = layoutCalculator.panelOrigin(
            panelSize: layout.panelSize,
            dockFrame: activeDockFrame,
            dockEdge: dockEdge,
            visibleFrame: visibleFrame
        )
        panel.present(at: origin, size: layout.panelSize, animated: true)

        presentedWindowIDs = windows.map(\.id)
        startPreviewSession(for: windows, layout: layout, screen: screen)
    }

    private func startPreviewSession(
        for windows: [WindowInfo],
        layout: DockPreviewLayout,
        screen: NSScreen?
    ) {
        // The same coordinator the switcher uses, so capture lifecycle, stream
        // accounting, and teardown behave identically. A session is only ever
        // started for the windows currently on screen.
        livePreviewCoordinator.beginSession(
            mode: previewMode(),
            allWindows: windows,
            visibleWindows: windows,
            selectedID: windows.first?.id,
            previewSize: layout.previewSize,
            displayScale: screen?.backingScaleFactor ?? 2
        )

        // Seed any already-cached frames immediately so cards are never blank
        // while fresh captures are produced.
        Task { @MainActor [weak self, previewService] in
            guard let self else { return }
            let cached = await previewService.cachedPreviews(for: windows)
            guard self.stateMachine.isPreviewVisible else { return }
            for (windowID, preview) in cached {
                self.panel.updatePreview(preview, for: windowID)
            }
        }
    }

    private func dismiss() {
        finishHoverPreview()
        guard panel.isVisible || !presentedWindowIDs.isEmpty else { return }
        diagnostics.log("Dock preview dismissed")
        livePreviewCoordinator.stopSession()
        presentedWindowIDs = []
        activeDockFrame = nil
        pendingDockFrame = nil
        pendingApplication = nil
        panel.dismiss(animated: true)
    }

    /// The panel hid itself or was dismissed. Capture must be released here too,
    /// so a popup that disappears for any reason cannot leave a stream running.
    private func handlePanelHidden() {
        finishHoverPreview()
        livePreviewCoordinator.stopSession()
        presentedWindowIDs = []
        activeApplication = nil
        activeDockFrame = nil
        pendingApplication = nil
        pendingDockFrame = nil
        cancelTimers()
        stateMachine.reset()
        livePreviewCoordinator.verifyIdleAfterPanelClosed()
    }

    // MARK: - Window list changes

    /// Keeps the visible cards in step with the tracked window list, so a window
    /// that closes or opens while the popup is up is reflected — and a popup with
    /// nothing left to show disappears.
    private func refreshPresentedWindows() {
        guard stateMachine.isPreviewVisible,
              let application = activeApplication,
              panel.isVisible else { return }

        // Raising a window updates MRU order; keep cards still under the pointer.
        let currentWindows = tracker.windows(for: application.processIdentifier)
        let windowsByID = Dictionary(uniqueKeysWithValues: currentWindows.map { ($0.id, $0) })
        let existingIDs = Set(presentedWindowIDs)
        let windows = presentedWindowIDs.compactMap { windowsByID[$0] }
            + currentWindows.filter { !existingIDs.contains($0.id) }
        if let hoveredWindowID, windowsByID[hoveredWindowID] == nil {
            cardHoverTask?.cancel()
            self.hoveredWindowID = nil
            hoverActivator.preview(nil)
        }
        guard !windows.isEmpty else {
            apply(stateMachine.dismissImmediately())
            return
        }
        guard windows.map(\.id) != presentedWindowIDs else { return }

        let screen = screen(containing: activeDockFrame ?? .zero)
            ?? screen(containingPoint: NSEvent.mouseLocation)
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let dockEdge = DockScreenEdge.current
        let layout = layoutCalculator.calculateLayout(
            itemCount: windows.count,
            availableSize: visibleFrame.size,
            dockEdge: dockEdge,
            displayScale: screen?.backingScaleFactor ?? 2,
            preferredItemWidth: CGFloat(DockPreviewPreference.thumbnailWidth)
        )
        let previousPreviews = Dictionary(
            uniqueKeysWithValues: panel.displayedWindowIDs.compactMap { id in
                // Preserve the frame already on screen for windows that remain.
                panel.currentPreview(for: id).map { (id, $0) }
            }
        )
        panel.update(
            applicationName: application.localizedName ?? "Application",
            applicationIcon: windows.first?.icon,
            cards: windows.map { window in
                DockPreviewCard(
                    window: window,
                    preview: previousPreviews[window.id],
                    canClose: closer.canClose(window)
                )
            },
            layout: layout
        )
        let origin = layoutCalculator.panelOrigin(
            panelSize: layout.panelSize,
            dockFrame: activeDockFrame,
            dockEdge: dockEdge,
            visibleFrame: visibleFrame
        )
        panel.present(at: origin, size: layout.panelSize, animated: true)

        presentedWindowIDs = windows.map(\.id)
        startPreviewSession(for: windows, layout: layout, screen: screen)
    }

    // MARK: - Interaction

    func dismissForSwitcher() {
        finishHoverPreview()
        apply(stateMachine.dismissImmediately())
    }

    private func handleCardHover(_ windowID: WindowID, hovering: Bool) {
        if !hovering {
            guard hoveredWindowID == windowID else { return }
            cardHoverTask?.cancel()
            hoveredWindowID = nil
            hoverActivator.preview(nil)
            return
        }
        cardHoverTask?.cancel()
        hoveredWindowID = windowID
        livePreviewCoordinator.updateSelection(windowID)
        guard DockPreviewPreference.focusOnHover else { return }
        cardHoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self,
                  self.hoveredWindowID == windowID,
                  self.panel.isVisible,
                  !self.isSwitcherSessionActive(),
                  let window = self.presentedWindow()?.first(where: { $0.id == windowID }),
                  !window.isMinimized, !window.isApplicationHidden, !window.isFullscreen else { return }
            if self.originalWindow == nil, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                let windows = self.tracker.windows(for: pid)
                self.originalWindow = windows.first(where: { $0.isFocused }) ?? windows.first
            }
            self.hoverActivator.preview(window) { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.panel.orderFrontRegardless()
            }
        }
    }

    private func finishHoverPreview(restoring: Bool = true) {
        cardHoverTask?.cancel()
        cardHoverTask = nil
        hoveredWindowID = nil
        hoverActivator.preview(nil)
        if restoring, let originalWindow,
           tracker.windows.contains(where: { $0.id == originalWindow.id }),
           AccessibilityPermission.isGranted {
            hoverActivator.restore(originalWindow)
        }
        originalWindow = nil
    }

    private func handleSelection(_ windowID: WindowID) {
        // Only act on a card that is actually on screen. The tracker can report a
        // window disappearing between the click and this call, and activating a
        // window the user can no longer see would be surprising.
        guard presentedWindowIDs.contains(windowID),
              let window = presentedWindow()?.first(where: { $0.id == windowID }) else { return }
        diagnostics.log("Dock preview activated window=\(windowID.rawValue)")
        // Dismiss first so the popup is gone before the window is raised, exactly
        // as a switcher commit does.
        finishHoverPreview(restoring: false)
        apply(stateMachine.dismissImmediately())
        activator.activate(window)
    }

    private func handleClose(_ windowID: WindowID) {
        guard presentedWindowIDs.contains(windowID),
              let window = presentedWindow()?.first(where: { $0.id == windowID }) else { return }
        diagnostics.log("Dock preview close requested window=\(windowID.rawValue)")
        closer.close(window, queue: closeQueue) { [weak self] _ in
            guard let self else { return }
            // The tracker will report the new window list; refresh explicitly so
            // the card disappears without waiting for the next discovery pass.
            self.tracker.refresh { [weak self] in
                self?.refreshPresentedWindows()
            }
        }
    }

    private let closeQueue = DispatchQueue(
        label: "com.maccommandtab.dock-preview.close",
        qos: .userInitiated
    )

    private func presentedWindow() -> [WindowInfo]? {
        guard let application = activeApplication else { return nil }
        let windows = tracker.windows(for: application.processIdentifier)
        return windows.isEmpty ? nil : windows
    }

    // MARK: - Geometry

    private func screen(containing appKitRect: CGRect) -> NSScreen? {
        guard appKitRect.width > 0 || appKitRect.height > 0 else { return nil }
        let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { lhs, rhs in
                lhs.frame.intersection(appKitRect).area < rhs.frame.intersection(appKitRect).area
            }
    }

    private func screen(containingPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

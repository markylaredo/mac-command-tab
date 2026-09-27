import AppKit

@MainActor
final class SwitcherCoordinator {
    private enum SelectionInputMode {
        case keyboard
        case pointer
    }

    private let tracker = WindowTracker()
    private let hotkeyMonitor = GlobalHotkeyMonitor()
    private let snapshotService: WindowSnapshotService
    private let previewService: WindowPreviewService
    private let livePreviewCoordinator: LivePreviewCoordinator
    private lazy var panel = SwitcherPanel(
        livePreviewCoordinator: livePreviewCoordinator,
        onHoverSelection: { [weak self] index in self?.handleHoverSelection(index) },
        onClickSelection: { [weak self] index in self?.handleClickSelection(index) },
        onDidHide: { [weak self] in self?.handlePanelHidden() }
    )
    private let activator = WindowActivator()
    private let permissionWindow = PermissionsWindowController()
    private lazy var dockPreview: DockWindowPreviewController = {
        // A second preview service and coordinator, so Dock previews keep their
        // own session accounting without ever sharing a session with the
        // switcher. Only one of the two is ever active; the switcher wins.
        let dockSnapshotService = WindowSnapshotService()
        let dockPreviewService = WindowPreviewService(snapshotService: dockSnapshotService)
        return DockWindowPreviewController(
            resolver: DockAccessibilityApplicationResolver(),
            tracker: tracker,
            activator: activator,
            livePreviewCoordinator: LivePreviewCoordinator(previewService: dockPreviewService),
            previewService: dockPreviewService,
            monitor: DockHoverMonitor()
        )
    }()
    private var permissionTimer: Timer?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var sessionWindows: [WindowInfo] = []
    private var visibleSessionWindows: [WindowInfo] = []
    private var sessionPreviewMode: PreviewMode?
    private var originalWindow: WindowInfo?
    private var searchQuery = ""
    private var selectionInputMode = SelectionInputMode.keyboard
    private var lastSelectionPointerLocation = NSEvent.mouseLocation
    private var accessibilityPermissionGranted = false
    private var screenCapturePermissionGranted = false
    private(set) var currentPreset = SwitcherPreset.saved
    private(set) var currentTheme = SwitcherTheme.saved
    private(set) var isGlassEnabled = SwitcherGlassPreference.saved
    private(set) var currentSelectionEffect = SwitcherSelectionEffect.saved
    private(set) var currentAppearance = SwitcherAppearance.saved
    private(set) var currentPreviewMode = PreviewMode.saved
    /// Whether a switcher session is open.
    ///
    /// The switcher and the Dock hover previews both drive the preview pipelines,
    /// so they must never be active at once. An open switcher always wins.
    var isSwitcherSessionActive: Bool { !sessionWindows.isEmpty }
    var onAccessibilityPermissionStatusChanged: ((Bool) -> Void)?
    var onScreenCapturePermissionStatusChanged: ((Bool) -> Void)?
    var onShortcutStatusChanged: ((Bool) -> Void)?
    var onWindowCountChanged: ((Int) -> Void)?
    var onPresetChanged: ((SwitcherPreset) -> Void)?
    var onThemeChanged: ((SwitcherTheme) -> Void)?
    var onGlassEnabledChanged: ((Bool) -> Void)?
    var onSelectionEffectChanged: ((SwitcherSelectionEffect) -> Void)?
    var onAppearanceChanged: ((SwitcherAppearance) -> Void)?
    var onPreviewModeChanged: ((PreviewMode) -> Void)?
    var onDockPreviewEnabledChanged: ((Bool) -> Void)?
    var onDockPreviewHoverDelayChanged: ((Int) -> Void)?
    var onDockPreviewAvailabilityChanged: ((DockPreviewAvailability) -> Void)?

    init() {
        let snapshotService = WindowSnapshotService()
        self.snapshotService = snapshotService
        let previewService = WindowPreviewService(snapshotService: snapshotService)
        self.previewService = previewService
        livePreviewCoordinator = LivePreviewCoordinator(previewService: previewService)

        panel.setPreset(currentPreset)
        panel.setTheme(currentTheme)
        panel.setGlassEnabled(isGlassEnabled)
        panel.setSelectionEffect(currentSelectionEffect)
        panel.setAppearance(currentAppearance)
        permissionWindow.setPreviewMode(currentPreviewMode)
        hotkeyMonitor.updateNavigationLayout(currentPreset.navigationLayout)
        tracker.addChangeObserver { [weak self] windows in
            guard let self else { return }
            if self.sessionWindows.isEmpty {
                self.hotkeyMonitor.updateItemCount(windows.count)
            } else {
                self.reconcileOpenSession(with: windows)
            }
            self.onWindowCountChanged?(windows.count)
        }
        hotkeyMonitor.onAction = { [weak self] action in self?.handle(action) }
        permissionWindow.onAccessibilityPermissionChanged = { [weak self] granted in
            self?.applyAccessibilityPermission(granted)
        }
        permissionWindow.onScreenCapturePermissionChanged = { [weak self] granted in
            self?.applyScreenCapturePermission(granted)
        }
        permissionWindow.onPreviewModeChanged = { [weak self] mode in
            self?.setPreviewMode(mode)
        }
        permissionWindow.onDockPreviewEnabledChanged = { [weak self] enabled in
            self?.setDockPreviewEnabled(enabled)
        }
        permissionWindow.onDockPreviewHoverDelayChanged = { [weak self] milliseconds in
            self?.setDockPreviewHoverDelay(milliseconds: milliseconds)
        }
        permissionWindow.onDockPreviewAvailabilityRefreshRequested = { [weak self] in
            guard let self else { return }
            self.permissionWindow.setDockPreviewAvailability(self.dockPreview.availability)
        }
        livePreviewCoordinator.onPreviewUpdated = { [weak self] windowID, preview in
            self?.panel.updatePreview(preview, for: windowID)
        }
    }

    func start() {
        applyAccessibilityPermission(AccessibilityPermission.isGranted)
        applyScreenCapturePermission(ScreenCapturePermission.isGranted)
        startDockPreviews()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyAccessibilityPermission(AccessibilityPermission.isGranted)
                self?.applyScreenCapturePermission(ScreenCapturePermission.isGranted)
            }
        }
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionStatus()
            }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endSwitcherSession(restoringOriginalWindow: true)
            }
        }

        // Launch quietly. Permission setup remains available from the menu bar.
        // Permission is usually already granted when the app is launched, in
        // which case the change handler above never fires and no report would be
        // written. Producing one at startup makes the Dock hierarchy checkable
        // without needing to toggle anything.
        DockAccessibilityProbe.writeReport()
    }

    private func refreshPermissionStatus() {
        applyAccessibilityPermission(AccessibilityPermission.isGranted)
        applyScreenCapturePermission(ScreenCapturePermission.isGranted)
        permissionWindow.updateStatus(notify: false)
    }

    // MARK: - Dock hover previews

    private func startDockPreviews() {
        dockPreview.isSwitcherSessionActive = { [weak self] in
            self?.isSwitcherSessionActive ?? false
        }
        // The preview style is read from the coordinator that owns it, so the
        // Dock previews always follow the setting the switcher uses. Reading the
        // stored default directly would be a second source of truth that could
        // disagree with a change made in Settings.
        dockPreview.previewMode = { [weak self] in
            self?.currentPreviewMode ?? PreviewMode.saved
        }
        dockPreview.onAvailabilityChanged = { [weak self] availability in
            self?.onDockPreviewAvailabilityChanged?(availability)
            self?.permissionWindow.setDockPreviewAvailability(availability)
        }
        dockPreview.start()
    }

    func setDockPreviewEnabled(_ enabled: Bool) {
        dockPreview.setEnabled(enabled)
        onDockPreviewEnabledChanged?(enabled)
        onDockPreviewAvailabilityChanged?(dockPreview.availability)
    }

    func setDockPreviewHoverDelay(milliseconds: Int) {
        dockPreview.setHoverDelay(milliseconds: milliseconds)
        onDockPreviewHoverDelayChanged?(milliseconds)
    }

    var isDockPreviewEnabled: Bool { DockPreviewPreference.isEnabled }
    var dockPreviewHoverDelayMilliseconds: Int { DockPreviewPreference.hoverDelayMilliseconds }
    var dockPreviewAvailability: DockPreviewAvailability { dockPreview.availability }

    /// Pushes current Dock preview availability into the Settings window.
    func syncPermissionWindowDockAvailability() {
        permissionWindow.setDockPreviewAvailability(dockPreview.availability)
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    func shutdown() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            self.appDidBecomeActiveObserver = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        endSwitcherSession(dismissPanel: false)
        panel.orderOut(nil)
        dockPreview.stop()
    }

    func refreshWindows() {
        guard accessibilityPermissionGranted else {
            permissionWindow.show()
            return
        }
        tracker.refresh()
    }

    func setPreset(_ preset: SwitcherPreset) {
        guard preset != currentPreset else { return }
        currentPreset = preset
        preset.save()
        panel.setPreset(preset)
        hotkeyMonitor.updateNavigationLayout(preset.navigationLayout)
        onPresetChanged?(preset)
    }

    func setTheme(_ theme: SwitcherTheme) {
        guard theme != currentTheme else { return }
        currentTheme = theme
        theme.save()
        panel.setTheme(theme)
        onThemeChanged?(theme)
    }

    func setGlassEnabled(_ enabled: Bool) {
        guard enabled != isGlassEnabled else { return }
        isGlassEnabled = enabled
        SwitcherGlassPreference.save(enabled)
        panel.setGlassEnabled(enabled)
        onGlassEnabledChanged?(enabled)
    }

    func setSelectionEffect(_ effect: SwitcherSelectionEffect) {
        guard effect != currentSelectionEffect else { return }
        currentSelectionEffect = effect
        effect.save()
        panel.setSelectionEffect(effect)
        onSelectionEffectChanged?(effect)
    }

    func setAppearance(_ appearance: SwitcherAppearance) {
        guard appearance != currentAppearance else { return }
        currentAppearance = appearance
        appearance.save()
        panel.setAppearance(appearance)
        if !sessionWindows.isEmpty {
            if appearance == .thumbnails {
                startPreviewSession()
            } else {
                stopPreviewSession()
            }
        }
        onAppearanceChanged?(appearance)
    }

    func setPreviewMode(_ mode: PreviewMode) {
        guard mode != currentPreviewMode else { return }
        currentPreviewMode = mode
        mode.save()
        permissionWindow.setPreviewMode(mode)
        onPreviewModeChanged?(mode)
    }

    private func applyAccessibilityPermission(_ granted: Bool) {
        guard granted != accessibilityPermissionGranted else {
            onAccessibilityPermissionStatusChanged?(granted)
            if granted, !hotkeyMonitor.isRunning {
                onShortcutStatusChanged?(hotkeyMonitor.start())
            }
            return
        }
        accessibilityPermissionGranted = granted
        onAccessibilityPermissionStatusChanged?(granted)
        permissionWindow.updateStatus(notify: false)
        dockPreview.applyAccessibilityPermission(granted: granted)
        if granted {
            tracker.start()
            onShortcutStatusChanged?(hotkeyMonitor.start())
            DockAccessibilityProbe.writeReport()
        } else {
            endSwitcherSession(restoringOriginalWindow: true)
            hotkeyMonitor.stop()
            tracker.stop()
            onShortcutStatusChanged?(false)
        }
    }

    private func applyScreenCapturePermission(_ granted: Bool) {
        guard granted != screenCapturePermissionGranted else {
            onScreenCapturePermissionStatusChanged?(granted)
            return
        }
        screenCapturePermissionGranted = granted
        onScreenCapturePermissionStatusChanged?(granted)
        permissionWindow.updateStatus(notify: false)

        if granted, !sessionWindows.isEmpty, currentAppearance == .thumbnails {
            startPreviewSession()
        } else if !granted {
            stopPreviewSession()
        }
    }

    private func handle(_ action: SwitcherAction) {
        switch action {
        case let .opened(selection):
            dockPreview.dismissForSwitcher()
            let windows = tracker.windows
            sessionWindows = windows
            visibleSessionWindows = windows
            sessionPreviewMode = currentPreviewMode
            originalWindow = originalFocusedWindow(in: windows)
            searchQuery = ""
            let selectedIndex = windows.isEmpty ? nil : min(selection, windows.count - 1)
            noteKeyboardSelection()
            let layout = panel.show(windows: windows, selectedIndex: selectedIndex ?? 0)
            hotkeyMonitor.updateActiveSession(
                itemCount: windows.count,
                selectedIndex: selectedIndex,
                columns: layout.columns,
                queryIsEmpty: true
            )
            if currentAppearance == .thumbnails { startPreviewSession() }
            if let selectedIndex { previewSelection(at: selectedIndex) }
        case let .selectionChanged(index):
            noteKeyboardSelection()
            panel.select(index)
            previewSelection(at: index)
        case let .searchCharacter(characters):
            noteKeyboardSelection()
            searchQuery.append(contentsOf: characters)
            updateSearchResults()
        case .searchBackspace:
            noteKeyboardSelection()
            searchQuery = WindowSearch.deletingLastCharacter(from: searchQuery)
            updateSearchResults()
        case .searchCleared:
            noteKeyboardSelection()
            searchQuery = ""
            updateSearchResults()
        case .cancelled:
            endSwitcherSession(restoringOriginalWindow: true)
        case let .committed(selection):
            commitSelection(selection)
        }
    }

    private func updateSearchResults() {
        let previousSelectedID = hotkeyMonitor.selectedIndex.flatMap { index in
            visibleSessionWindows.indices.contains(index) ? visibleSessionWindows[index].id : nil
        }
        let filtered = WindowSearch.filter(sessionWindows, query: searchQuery)
        let selectedIndex = WindowSearch.selectionIndex(
            preserving: previousSelectedID,
            visibleIDs: filtered.map(\.id)
        )
        visibleSessionWindows = filtered
        let layout = panel.update(
            windows: filtered,
            selectedIndex: selectedIndex,
            query: searchQuery,
            animated: true
        )
        hotkeyMonitor.updateActiveSession(
            itemCount: filtered.count,
            selectedIndex: selectedIndex,
            columns: layout.columns,
            queryIsEmpty: searchQuery.isEmpty
        )
        if let selectedIndex { previewSelection(at: selectedIndex) }
        if currentAppearance == .thumbnails {
            let selectedID = selectedIndex.flatMap { index in
                filtered.indices.contains(index) ? filtered[index].id : nil
            }
            livePreviewCoordinator.updateVisibleWindows(
                filtered,
                selectedID: selectedID,
                previewSize: layout.previewSize,
                displayScale: panel.targetDisplayScale
            )
        }
    }

    private func handleHoverSelection(_ index: Int) {
        guard panel.isVisible, visibleSessionWindows.indices.contains(index) else { return }
        let pointerLocation = NSEvent.mouseLocation
        let distance = hypot(
            pointerLocation.x - lastSelectionPointerLocation.x,
            pointerLocation.y - lastSelectionPointerLocation.y
        )
        let movementThreshold: CGFloat = selectionInputMode == .keyboard ? 5 : 0.5
        guard distance >= movementThreshold else { return }
        selectionInputMode = .pointer
        lastSelectionPointerLocation = pointerLocation
        hotkeyMonitor.synchronizeSelection(index)
        panel.select(index)
        previewSelection(at: index)
    }

    private func handleClickSelection(_ index: Int) {
        guard panel.isVisible, visibleSessionWindows.indices.contains(index) else { return }
        selectionInputMode = .pointer
        hotkeyMonitor.synchronizeSelection(index)
        panel.select(index)
        commitSelection(index)
    }

    private func noteKeyboardSelection() {
        selectionInputMode = .keyboard
        lastSelectionPointerLocation = NSEvent.mouseLocation
    }

    private func commitSelection(_ index: Int) {
        let windows = visibleSessionWindows
        endSwitcherSession()
        guard windows.indices.contains(index) else { return }
        let window = windows[index]
        activator.activate(window)
    }

    private func previewSelection(at index: Int) {
        guard visibleSessionWindows.indices.contains(index) else { return }
        let window = visibleSessionWindows[index]
        livePreviewCoordinator.updateSelection(window.id)
        activator.preview(window) { [weak self] in
            self?.panel.keepVisibleAbovePreview()
        }
    }

    private func startPreviewSession() {
        guard screenCapturePermissionGranted,
              currentAppearance == .thumbnails,
              !sessionWindows.isEmpty else { return }
        let selectedID = hotkeyMonitor.selectedIndex.flatMap { index in
            visibleSessionWindows.indices.contains(index) ? visibleSessionWindows[index].id : nil
        }
        livePreviewCoordinator.beginSession(
            mode: sessionPreviewMode ?? currentPreviewMode,
            allWindows: sessionWindows,
            visibleWindows: visibleSessionWindows,
            selectedID: selectedID,
            previewSize: panel.currentPreviewSize,
            displayScale: panel.targetDisplayScale
        )
    }

    private func stopPreviewSession() {
        livePreviewCoordinator.stopSession()
    }

    private func endSwitcherSession(
        restoringOriginalWindow: Bool = false,
        dismissPanel: Bool = true
    ) {
        if restoringOriginalWindow { activator.restore(originalWindow) }
        stopPreviewSession()
        if dismissPanel, panel.isVisible { panel.dismiss() }
        sessionWindows = []
        visibleSessionWindows = []
        sessionPreviewMode = nil
        originalWindow = nil
        searchQuery = ""
        hotkeyMonitor.updateItemCount(tracker.windows.count)
        if !dismissPanel || !panel.isVisible {
            livePreviewCoordinator.verifyIdleAfterPanelClosed()
        }
    }

    private func handlePanelHidden() {
        let wasActive = !sessionWindows.isEmpty
        endSwitcherSession(
            restoringOriginalWindow: wasActive,
            dismissPanel: false
        )
    }

    private func reconcileOpenSession(with latestWindows: [WindowInfo]) {
        let latestByID = Dictionary(uniqueKeysWithValues: latestWindows.map { ($0.id, $0) })
        let remainingWindows = sessionWindows.compactMap { latestByID[$0.id] }
        guard remainingWindows.count != sessionWindows.count else { return }

        sessionWindows = remainingWindows
        guard !sessionWindows.isEmpty else {
            endSwitcherSession(restoringOriginalWindow: true)
            return
        }
        updateSearchResults()
    }

    private func originalFocusedWindow(in windows: [WindowInfo]) -> WindowInfo? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return windows.first { $0.pid == frontmostPID && $0.isFocused }
            ?? windows.first { $0.pid == frontmostPID }
    }
}

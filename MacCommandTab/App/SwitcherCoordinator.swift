import AppKit

@MainActor
final class SwitcherCoordinator {
    private let tracker = WindowTracker()
    private let hotkeyMonitor = GlobalHotkeyMonitor()
    private let panel = SwitcherPanel()
    private let activator = WindowActivator()
    private let snapshotService: WindowSnapshotService
    private let previewService: WindowPreviewService
    private let effectEngine: EffectEngine
    private let permissionWindow = PermissionsWindowController()
    private var permissionTimer: Timer?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var previewTask: Task<Void, Never>?
    private var sessionWindows: [WindowInfo] = []
    private var visibleSessionWindows: [WindowInfo] = []
    private var searchQuery = ""
    private var accessibilityPermissionGranted = false
    private var screenCapturePermissionGranted = false
    private(set) var currentPreset = SwitcherPreset.saved
    private(set) var currentTheme = SwitcherTheme.saved
    private(set) var isGlassEnabled = SwitcherGlassPreference.saved
    private(set) var currentSelectionEffect = SwitcherSelectionEffect.saved
    private(set) var currentWindowEffect = WindowEffect.saved
    private(set) var currentAppearance = SwitcherAppearance.saved
    var onAccessibilityPermissionStatusChanged: ((Bool) -> Void)?
    var onScreenCapturePermissionStatusChanged: ((Bool) -> Void)?
    var onShortcutStatusChanged: ((Bool) -> Void)?
    var onWindowCountChanged: ((Int) -> Void)?
    var onPresetChanged: ((SwitcherPreset) -> Void)?
    var onThemeChanged: ((SwitcherTheme) -> Void)?
    var onGlassEnabledChanged: ((Bool) -> Void)?
    var onSelectionEffectChanged: ((SwitcherSelectionEffect) -> Void)?
    var onWindowEffectChanged: ((WindowEffect) -> Void)?
    var onAppearanceChanged: ((SwitcherAppearance) -> Void)?

    init() {
        let snapshotService = WindowSnapshotService()
        self.snapshotService = snapshotService
        previewService = WindowPreviewService(snapshotService: snapshotService)
        effectEngine = EffectEngine()
        panel.setPreset(currentPreset)
        panel.setTheme(currentTheme)
        panel.setGlassEnabled(isGlassEnabled)
        panel.setSelectionEffect(currentSelectionEffect)
        panel.setAppearance(currentAppearance)
        hotkeyMonitor.updateNavigationLayout(currentPreset.navigationLayout)
        tracker.onWindowsChanged = { [weak self] windows in
            guard let self else { return }
            if self.sessionWindows.isEmpty {
                self.hotkeyMonitor.updateItemCount(windows.count)
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
        permissionWindow.onPreviewEffect = { [weak self] effect in
            self?.previewWindowEffect(effect) ?? false
        }
    }

    func start() {
        applyAccessibilityPermission(AccessibilityPermission.isGranted)
        applyScreenCapturePermission(ScreenCapturePermission.isGranted)
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

        if !accessibilityPermissionGranted { AccessibilityPermission.request() }
        permissionWindow.show()
    }

    private func refreshPermissionStatus() {
        applyAccessibilityPermission(AccessibilityPermission.isGranted)
        applyScreenCapturePermission(ScreenCapturePermission.isGranted)
        permissionWindow.updateStatus(notify: false)
    }

    func showPermissionWindow() {
        permissionWindow.show()
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

    func setWindowEffect(_ effect: WindowEffect) {
        guard effect != currentWindowEffect else { return }
        currentWindowEffect = effect
        effect.save()
        onWindowEffectChanged?(effect)
    }

    func setAppearance(_ appearance: SwitcherAppearance) {
        guard appearance != currentAppearance else { return }
        currentAppearance = appearance
        appearance.save()
        panel.setAppearance(appearance)
        onAppearanceChanged?(appearance)
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
        if granted {
            tracker.start()
            onShortcutStatusChanged?(hotkeyMonitor.start())
        } else {
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
        if granted, !sessionWindows.isEmpty {
            startPreviewRefresh(for: sessionWindows)
        }
        if !granted {
            stopPreviewRefresh()
            panel.updatePreviews([:])
            Task { await previewService.clear() }
        }
    }

    private func handle(_ action: SwitcherAction) {
        switch action {
        case let .opened(selection):
            let windows = tracker.windows
            guard !windows.isEmpty else { return }
            sessionWindows = windows
            visibleSessionWindows = windows
            searchQuery = ""
            let selectedIndex = min(selection, windows.count - 1)
            let layout = panel.show(windows: windows, selectedIndex: selectedIndex)
            hotkeyMonitor.updateActiveSession(
                itemCount: windows.count,
                selectedIndex: selectedIndex,
                columns: layout.columns,
                queryIsEmpty: true
            )
            if currentAppearance == .thumbnails {
                startPreviewRefresh(for: windows)
            }
        case let .selectionChanged(index):
            panel.select(index)
        case let .searchCharacter(characters):
            searchQuery.append(contentsOf: characters)
            updateSearchResults()
        case .searchBackspace:
            searchQuery = WindowSearch.deletingLastCharacter(from: searchQuery)
            updateSearchResults()
        case .searchCleared:
            searchQuery = ""
            updateSearchResults()
        case .cancelled:
            stopPreviewRefresh()
            panel.dismiss()
            sessionWindows = []
            visibleSessionWindows = []
            searchQuery = ""
            hotkeyMonitor.updateItemCount(tracker.windows.count)
        case let .committed(selection):
            let windows = visibleSessionWindows
            stopPreviewRefresh()
            panel.dismiss()
            sessionWindows = []
            visibleSessionWindows = []
            searchQuery = ""
            hotkeyMonitor.updateItemCount(tracker.windows.count)
            guard windows.indices.contains(selection) else { return }
            let window = windows[selection]
            activator.activate(window)
            playRestoreEffectIfAvailable(for: window)
        }
    }

    private func updateSearchResults() {
        let selectedID = hotkeyMonitor.selectedIndex.flatMap { index in
            visibleSessionWindows.indices.contains(index) ? visibleSessionWindows[index].id : nil
        }
        let filtered = WindowSearch.filter(sessionWindows, query: searchQuery)
        let selectedIndex = WindowSearch.selectionIndex(
            preserving: selectedID,
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
    }

    private func playRestoreEffectIfAvailable(for window: WindowInfo) {
        let effect = currentWindowEffect
        guard effect != .none else { return }

        Task { @MainActor [weak self] in
            guard let self,
                  let snapshot = await self.snapshotService.cachedSnapshot(for: window.id) else { return }
            self.effectEngine.play(
                effect: effect,
                snapshot: snapshot,
                frame: window.frame,
                direction: .opening,
                duration: effect.defaultDuration
            )
        }
    }

    private func previewWindowEffect(_ effect: WindowEffect) -> Bool {
        guard effect != .none,
              let snapshot = EffectPreviewSnapshotFactory.makeSnapshot() else { return false }
        let sampleSize = CGSize(width: 640, height: 360)
        let referenceFrame = permissionWindow.window?.frame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        let frame = CGRect(
            x: referenceFrame.midX - sampleSize.width / 2,
            y: referenceFrame.midY - sampleSize.height / 2,
            width: sampleSize.width,
            height: sampleSize.height
        )
        return effectEngine.playPreview(
            effect: effect,
            snapshot: snapshot,
            appKitFrame: frame,
            direction: .closing,
            duration: effect.defaultDuration
        ) != nil
    }

    private func startPreviewRefresh(for windows: [WindowInfo]) {
        stopPreviewRefresh()
        panel.updatePreviews([:])
        guard screenCapturePermissionGranted else { return }
        previewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.previewService.prepareSession(for: windows)
            while !Task.isCancelled {
                let previews = await self.previewService.capturePreviews(for: windows)
                guard !Task.isCancelled else { return }
                self.panel.updatePreviews(previews)
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }

    private func stopPreviewRefresh() {
        previewTask?.cancel()
        previewTask = nil
    }
}

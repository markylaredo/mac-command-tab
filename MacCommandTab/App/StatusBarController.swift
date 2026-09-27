import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: SwitcherCoordinator
    private let shortcutItem = NSMenuItem(title: "Shortcut: Checking…", action: nil, keyEquivalent: "")
    private let windowCountItem = NSMenuItem(title: "Detected Windows: —", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Accessibility: Checking…", action: nil, keyEquivalent: "")
    private let previewPermissionItem = NSMenuItem(title: "Window Previews: Checking…", action: nil, keyEquivalent: "")
    private let glassItem = NSMenuItem(title: "Glass Background", action: #selector(toggleGlass(_:)), keyEquivalent: "")
    private let dockPreviewToggleItem = NSMenuItem(
        title: "Dock Hover Previews",
        action: #selector(toggleDockPreviews(_:)),
        keyEquivalent: ""
    )
    private let dockPreviewStatusItem = NSMenuItem(
        title: "Dock Previews: Checking…",
        action: nil,
        keyEquivalent: ""
    )
    /// Runs the Dock accessibility report on demand. Diagnostic for checking
    /// whether the Dock's hierarchy can still be resolved, including after a macOS
    /// update. Writing a file when the user explicitly asks for it is harmless in
    /// a release build, and gating it on `DEBUG` would mean it is never available
    /// in this project, which does not define that condition.
    private let dockDiagnosticsItem = NSMenuItem(
        title: "Write Dock Accessibility Report",
        action: #selector(writeDockDiagnostics),
        keyEquivalent: ""
    )
    private var presetItems: [SwitcherPreset: NSMenuItem] = [:]
    private var appearanceItems: [SwitcherAppearance: NSMenuItem] = [:]
    private var themeItems: [SwitcherTheme: NSMenuItem] = [:]
    private var selectionEffectItems: [SwitcherSelectionEffect: NSMenuItem] = [:]

    init(coordinator: SwitcherCoordinator) {
        self.coordinator = coordinator
        super.init()
        configureStatusItem()
        coordinator.onAccessibilityPermissionStatusChanged = { [weak self] granted in
            self?.permissionItem.title = granted ? "Accessibility: Granted" : "Accessibility: Required"
        }
        coordinator.onScreenCapturePermissionStatusChanged = { [weak self] granted in
            self?.previewPermissionItem.title = granted
                ? "Window Previews: Enabled"
                : "Window Previews: Permission Required"
        }
        coordinator.onShortcutStatusChanged = { [weak self] active in
            self?.shortcutItem.title = active ? "Shortcut: Option–Tab Active" : "Shortcut: Unavailable"
        }
        coordinator.onWindowCountChanged = { [weak self] count in
            self?.windowCountItem.title = "Detected Windows: \(count)"
        }
        coordinator.onPresetChanged = { [weak self] preset in
            self?.updatePresetSelection(preset)
        }
        coordinator.onThemeChanged = { [weak self] theme in
            self?.updateThemeSelection(theme)
        }
        coordinator.onGlassEnabledChanged = { [weak self] enabled in
            self?.glassItem.state = enabled ? .on : .off
        }
        coordinator.onSelectionEffectChanged = { [weak self] effect in
            self?.updateSelectionEffect(effect)
        }
        coordinator.onAppearanceChanged = { [weak self] appearance in
            self?.updateAppearanceSelection(appearance)
        }
        coordinator.onDockPreviewAvailabilityChanged = { [weak self] availability in
            self?.dockPreviewStatusItem.title = availability.menuTitle
        }
        coordinator.onDockPreviewEnabledChanged = { [weak self] enabled in
            self?.dockPreviewToggleItem.state = enabled ? .on : .off
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.imagePosition = .imageLeading
            button.title = "MCT"
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            button.toolTip = "MacCommandTab — Option–Tab window switcher"
            button.setAccessibilityLabel("MacCommandTab")
        }
        statusItem.isVisible = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open MacCommandTab…", action: #selector(openMacCommandTab), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Window List", action: #selector(refreshWindows), keyEquivalent: "r")
        menu.addItem(makeAppearanceMenu())
        menu.addItem(makeThemeMenu())
        configureGlassItem()
        menu.addItem(glassItem)
        configureDockPreviewItems()
        menu.addItem(dockPreviewToggleItem)
        menu.addItem(dockPreviewStatusItem)
        dockDiagnosticsItem.target = self
        menu.addItem(dockDiagnosticsItem)
        menu.addItem(makeSelectionEffectMenu())
        menu.addItem(.separator())

        [shortcutItem, windowCountItem, permissionItem, previewPermissionItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openPermissions), keyEquivalent: "")
        menu.addItem(withTitle: "About MacCommandTab", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacCommandTab", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func makePresetMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Switcher Layout", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Switcher Layout")

        for preset in SwitcherPreset.allCases {
            let presetItem = NSMenuItem(title: preset.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            presetItem.toolTip = preset.subtitle
            presetItem.representedObject = preset.rawValue
            presetItem.target = self
            presetItems[preset] = presetItem
            submenu.addItem(presetItem)
        }

        item.submenu = submenu
        updatePresetSelection(coordinator.currentPreset)
        return item
    }

    private func updatePresetSelection(_ selectedPreset: SwitcherPreset) {
        for (preset, item) in presetItems {
            item.state = preset == selectedPreset ? .on : .off
        }
    }

    private func makeAppearanceMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Switcher Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Switcher Appearance")

        for appearance in SwitcherAppearance.allCases {
            let appearanceItem = NSMenuItem(
                title: appearance.title,
                action: #selector(selectAppearance(_:)),
                keyEquivalent: ""
            )
            appearanceItem.toolTip = appearance.subtitle
            appearanceItem.representedObject = appearance.rawValue
            appearanceItem.target = self
            appearanceItems[appearance] = appearanceItem
            submenu.addItem(appearanceItem)
        }

        item.submenu = submenu
        updateAppearanceSelection(coordinator.currentAppearance)
        return item
    }

    private func updateAppearanceSelection(_ selectedAppearance: SwitcherAppearance) {
        for (appearance, item) in appearanceItems {
            item.state = appearance == selectedAppearance ? .on : .off
        }
    }

    private func makeThemeMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Switcher Theme", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Switcher Theme")

        for theme in SwitcherTheme.allCases {
            let themeItem = NSMenuItem(title: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            themeItem.toolTip = theme.subtitle
            themeItem.representedObject = theme.rawValue
            themeItem.target = self
            themeItems[theme] = themeItem
            submenu.addItem(themeItem)
        }

        item.submenu = submenu
        updateThemeSelection(coordinator.currentTheme)
        return item
    }

    private func updateThemeSelection(_ selectedTheme: SwitcherTheme) {
        for (theme, item) in themeItems {
            item.state = theme == selectedTheme ? .on : .off
        }
    }

    private func configureGlassItem() {
        glassItem.target = self
        glassItem.state = coordinator.isGlassEnabled ? .on : .off
        glassItem.toolTip = "Use native macOS translucency behind the switcher"
    }

    private func configureDockPreviewItems() {
        dockPreviewToggleItem.target = self
        dockPreviewToggleItem.state = coordinator.isDockPreviewEnabled ? .on : .off
        dockPreviewToggleItem.toolTip =
            "Preview an application's windows by hovering over its Dock icon"
        dockPreviewStatusItem.isEnabled = false
        dockPreviewStatusItem.title = coordinator.dockPreviewAvailability.menuTitle
        // Seed the Settings window's status row too, so both surfaces agree from
        // the first launch rather than only after the first change.
        coordinator.syncPermissionWindowDockAvailability()
    }

    private func makeSelectionEffectMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Selection Effect", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Selection Effect")

        for effect in SwitcherSelectionEffect.allCases {
            let effectItem = NSMenuItem(title: effect.title, action: #selector(selectSelectionEffect(_:)), keyEquivalent: "")
            effectItem.toolTip = effect.subtitle
            effectItem.representedObject = effect.rawValue
            effectItem.target = self
            selectionEffectItems[effect] = effectItem
            submenu.addItem(effectItem)
        }

        item.submenu = submenu
        updateSelectionEffect(coordinator.currentSelectionEffect)
        return item
    }

    private func updateSelectionEffect(_ selectedEffect: SwitcherSelectionEffect) {
        for (effect, item) in selectionEffectItems {
            item.state = effect == selectedEffect ? .on : .off
        }
    }

    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()

            let backWindow = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 7, width: 10, height: 7.5), xRadius: 1.4, yRadius: 1.4)
            backWindow.lineWidth = 1.5
            backWindow.stroke()

            let frontWindow = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 10, height: 7.5), xRadius: 1.4, yRadius: 1.4)
            frontWindow.lineWidth = 1.5
            frontWindow.stroke()

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.5
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 5, y: 7.25))
            arrow.line(to: NSPoint(x: 10, y: 7.25))
            arrow.move(to: NSPoint(x: 8.25, y: 9))
            arrow.line(to: NSPoint(x: 10, y: 7.25))
            arrow.line(to: NSPoint(x: 8.25, y: 5.5))
            arrow.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacCommandTab"
        return image
    }

    @objc private func openMacCommandTab() { coordinator.showPermissionWindow() }
    @objc private func refreshWindows() { coordinator.refreshWindows() }
    @objc private func openPermissions() { coordinator.showPermissionWindow() }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = SwitcherPreset(rawValue: rawValue) else { return }
        coordinator.setPreset(preset)
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let appearance = SwitcherAppearance(rawValue: rawValue) else { return }
        coordinator.setAppearance(appearance)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = SwitcherTheme(rawValue: rawValue) else { return }
        coordinator.setTheme(theme)
    }

    @objc private func toggleGlass(_ sender: NSMenuItem) {
        coordinator.setGlassEnabled(sender.state != .on)
    }

    @objc private func toggleDockPreviews(_ sender: NSMenuItem) {
        coordinator.setDockPreviewEnabled(sender.state != .on)
    }

    @objc private func writeDockDiagnostics() {
        DockAccessibilityProbe.writeReport()
        let wasTracing = isDockTraceArmed
        if wasTracing {
            DockHoverTrace.shared.end()
        } else {
            DockHoverTrace.shared.begin()
        }
        isDockTraceArmed = !wasTracing

        // An explicit user action from the menu, so reporting the result here is
        // appropriate. Nothing in the hover path ever shows an alert.
        let alert = NSAlert()
        alert.messageText = "Dock Accessibility Report"
        if !AccessibilityPermission.isGranted {
            alert.informativeText = "Accessibility is not granted, so the Dock cannot be read."
        } else if isDockTraceArmed {
            alert.informativeText = """
                Report written to:
                \(DockAccessibilityProbe.outputURL.path)

                Hover trace armed. Hover a few Dock icons, then run this command \
                again to stop tracing and read the result.
                """
        } else {
            alert.informativeText = """
                Report written to:
                \(DockAccessibilityProbe.outputURL.path)

                Hover trace stopped. Trace written to:
                \(DockHoverTrace.outputURL.path)
                """
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var isDockTraceArmed = false

    @objc private func selectSelectionEffect(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let effect = SwitcherSelectionEffect(rawValue: rawValue) else { return }
        coordinator.setSelectionEffect(effect)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

import AppKit
import ServiceManagement

@MainActor
final class PermissionsWindowController: NSWindowController {
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenCaptureStatusLabel = NSTextField(labelWithString: "")
    private let screenCaptureIdentityLabel = NSTextField(wrappingLabelWithString: "")
    private let previewModeControl = NSSegmentedControl()
    private let previewModeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let accessibilityActionButton = NSButton(title: "Open System Settings…", target: nil, action: nil)
    private let screenCaptureActionButton = NSButton(title: "Allow Window Previews", target: nil, action: nil)
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let startAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Start MacCommandTab at login",
        target: nil,
        action: nil
    )
    private let loginItemStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let dockPreviewCheckbox = NSButton(
        checkboxWithTitle: "Show window previews when hovering over Dock apps",
        target: nil,
        action: nil
    )
    private let thumbnailSizeControl = NSSegmentedControl()
    private let focusOnHoverCheckbox = NSButton(checkboxWithTitle: "Show the real window on hover", target: nil, action: nil)
    private static let thumbnailWidths = [180, 240, 300]
    private let dockPreviewDelayControl = NSSegmentedControl()
    private let dockPreviewDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let dockPreviewStatusLabel = NSTextField(labelWithString: "")
    private var accessibilityCheckTask: Task<Void, Never>?
    private var screenCaptureRepairTask: Task<Void, Never>?
    var onAccessibilityPermissionChanged: ((Bool) -> Void)?
    var onScreenCapturePermissionChanged: ((Bool) -> Void)?
    var onPreviewModeChanged: ((PreviewMode) -> Void)?
    var onDockPreviewEnabledChanged: ((Bool) -> Void)?
    var onDockPreviewHoverDelayChanged: ((Int) -> Void)?
    /// Asks the coordinator to re-report Dock preview availability, so the status
    /// row is current whenever the window is opened.
    var onDockPreviewAvailabilityRefreshRequested: (() -> Void)?

    /// The hover delays offered in Settings. The default sits in the middle.
    private static let dockHoverDelayOptions = [250, 300, 400]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(ScreenCapturePermission.applicationName) Settings"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        accessibilityCheckTask?.cancel()
        screenCaptureRepairTask?.cancel()
    }

    func show() {
        updateStatus()
        onDockPreviewAvailabilityRefreshRequested?()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatus(notify: Bool = true) {
        let granted = AccessibilityPermission.isGranted
        configureStatus(granted: granted)
        let screenCaptureGranted = ScreenCapturePermission.isGranted
        configureScreenCaptureStatus(granted: screenCaptureGranted)
        configureLoginItemStatus()
        if notify {
            onAccessibilityPermissionChanged?(granted)
            onScreenCapturePermissionChanged?(screenCaptureGranted)
        }
    }
    func setPreviewMode(_ mode: PreviewMode) {
        guard let index = PreviewMode.allCases.firstIndex(of: mode) else { return }
        previewModeControl.selectedSegment = index
        previewModeDescriptionLabel.stringValue = mode.description
    }

    private func makeContentView() -> NSView {
        let title = NSTextField(labelWithString: ScreenCapturePermission.applicationName)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center

        let message = NSTextField(
            wrappingLabelWithString: "Your windows, within reach."
        )
        message.font = .systemFont(ofSize: 14)
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3

        let generalHeading = NSTextField(labelWithString: "General")
        generalHeading.font = .systemFont(ofSize: 15, weight: .semibold)

        startAtLoginCheckbox.target = self
        startAtLoginCheckbox.action = #selector(toggleStartAtLogin)
        startAtLoginCheckbox.setAccessibilityHelp(
            "Open MacCommandTab automatically after you sign in to your Mac."
        )

        let loginItemSettingsButton = NSButton(
            title: "Login Items…",
            target: self,
            action: #selector(openLoginItemSettings)
        )
        loginItemSettingsButton.bezelStyle = .rounded

        let loginItemRow = NSStackView(
            views: [startAtLoginCheckbox, NSView(), loginItemSettingsButton]
        )
        loginItemRow.orientation = .horizontal
        loginItemRow.spacing = 10
        loginItemRow.alignment = .centerY

        loginItemStatusLabel.font = .systemFont(ofSize: 11.5)
        loginItemStatusLabel.textColor = .secondaryLabelColor
        loginItemStatusLabel.maximumNumberOfLines = 2

        let generalSection = NSStackView(
            views: [generalHeading, loginItemRow, loginItemStatusLabel]
        )
        generalSection.orientation = .vertical
        generalSection.spacing = 8
        generalSection.alignment = .leading
        generalSection.widthAnchor.constraint(equalToConstant: 434).isActive = true
        loginItemRow.widthAnchor.constraint(equalTo: generalSection.widthAnchor).isActive = true
        configureLoginItemStatus()

        let heading = NSTextField(labelWithString: "Accessibility")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        accessibilityStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let accessibilityHelp = NSTextField(
            wrappingLabelWithString: "Required to discover and activate the window you select."
        )
        accessibilityHelp.font = .systemFont(ofSize: 11.5)
        accessibilityHelp.textColor = .secondaryLabelColor
        accessibilityHelp.maximumNumberOfLines = 2

        let labels = NSStackView(views: [heading, accessibilityHelp, accessibilityStatusLabel])
        labels.orientation = .vertical
        labels.spacing = 3
        labels.alignment = .leading

        accessibilityActionButton.target = self
        accessibilityActionButton.action = #selector(openAccessibilitySettings)
        accessibilityActionButton.bezelStyle = .rounded

        let permissionRow = NSStackView(views: [labels, NSView(), accessibilityActionButton])
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10
        permissionRow.alignment = .centerY
        permissionRow.widthAnchor.constraint(equalToConstant: 434).isActive = true

        let previewSectionHeading = NSTextField(labelWithString: "Window Preview")
        previewSectionHeading.font = .systemFont(ofSize: 15, weight: .semibold)

        let previewModeHeading = NSTextField(labelWithString: "Preview style")
        previewModeHeading.font = .systemFont(ofSize: 13, weight: .medium)
        let previewModeHelp = NSTextField(
            labelWithString: "Choose between efficient snapshots and real-time window updates."
        )
        previewModeHelp.font = .systemFont(ofSize: 11.5)
        previewModeHelp.textColor = .secondaryLabelColor

        previewModeControl.segmentCount = PreviewMode.allCases.count
        for (index, mode) in PreviewMode.allCases.enumerated() {
            previewModeControl.setLabel(mode.title, forSegment: index)
            previewModeControl.setWidth(150, forSegment: index)
        }
        previewModeControl.trackingMode = .selectOne
        previewModeControl.segmentStyle = .rounded
        previewModeControl.target = self
        previewModeControl.action = #selector(changePreviewMode)
        previewModeControl.setAccessibilityLabel("Preview Mode")
        setPreviewMode(PreviewMode.saved)

        previewModeDescriptionLabel.font = .systemFont(ofSize: 11.5)
        previewModeDescriptionLabel.textColor = .secondaryLabelColor
        previewModeDescriptionLabel.maximumNumberOfLines = 2

        let previewHeading = NSTextField(labelWithString: "Window previews")
        previewHeading.font = .systemFont(ofSize: 13, weight: .medium)
        screenCaptureStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        screenCaptureIdentityLabel.font = .systemFont(ofSize: 10.5)
        screenCaptureIdentityLabel.textColor = .tertiaryLabelColor
        screenCaptureIdentityLabel.maximumNumberOfLines = 3
        let screenCaptureHelp = NSTextField(
            wrappingLabelWithString: "Show window contents in the switcher and Dock previews. Frames stay on this Mac."
        )
        screenCaptureHelp.font = .systemFont(ofSize: 11.5)
        screenCaptureHelp.textColor = .secondaryLabelColor
        let previewLabels = NSStackView(
            views: [
                previewHeading,
                screenCaptureHelp,
                screenCaptureStatusLabel,
                screenCaptureIdentityLabel
            ]
        )
        previewLabels.orientation = .vertical
        previewLabels.spacing = 3
        previewLabels.alignment = .leading

        screenCaptureActionButton.target = self
        screenCaptureActionButton.action = #selector(requestScreenCapturePermission)
        screenCaptureActionButton.bezelStyle = .rounded
        let previewPermissionRow = NSStackView(
            views: [previewLabels, NSView(), screenCaptureActionButton]
        )
        previewPermissionRow.orientation = .horizontal
        previewPermissionRow.spacing = 10
        previewPermissionRow.alignment = .centerY
        previewPermissionRow.widthAnchor.constraint(equalToConstant: 434).isActive = true

        let previewSection = NSStackView(
            views: [
                previewSectionHeading,
                previewModeHeading,
                previewModeHelp,
                previewModeControl,
                previewModeDescriptionLabel
            ]
        )
        previewSection.orientation = .vertical
        previewSection.spacing = 8
        previewSection.alignment = .leading
        previewSection.widthAnchor.constraint(equalToConstant: 434).isActive = true

        let permissionsHeading = NSTextField(labelWithString: "Permissions")
        permissionsHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let permissionsHelp = NSTextField(
            wrappingLabelWithString: "MacCommandTab needs access to switch windows and display their previews."
        )
        permissionsHelp.font = .systemFont(ofSize: 11.5)
        permissionsHelp.textColor = .secondaryLabelColor
        let permissionsSection = NSStackView(
            views: [permissionsHeading, permissionsHelp, permissionRow, previewPermissionRow]
        )
        permissionsSection.orientation = .vertical
        permissionsSection.spacing = 10
        permissionsSection.alignment = .leading
        permissionsSection.setCustomSpacing(14, after: permissionsHelp)
        permissionsSection.widthAnchor.constraint(equalToConstant: 434).isActive = true

        feedbackLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        feedbackLabel.textColor = .systemGreen
        feedbackLabel.alignment = .center

        let dockPreviewsSection = makeDockPreviewsSection()

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.tabViewType = .topTabsBezelBorder
        let startupHelp = NSTextField(wrappingLabelWithString: "Starts quietly in the menu bar. Open Settings whenever you need them.")
        startupHelp.font = .systemFont(ofSize: 12)
        startupHelp.textColor = .secondaryLabelColor
        let shortcutHelp = NSTextField(wrappingLabelWithString: "Hold Option and press Tab to switch windows. Type to search; press Escape to cancel.")
        shortcutHelp.font = .systemFont(ofSize: 12)
        shortcutHelp.textColor = .secondaryLabelColor
        for (name, sections) in [
            ("General", [generalSection, startupHelp, shortcutHelp]),
            ("Previews", [previewSection, dockPreviewsSection]),
            ("Permissions", [permissionsSection])
        ] as [(String, [NSView])] {
            let item = NSTabViewItem(identifier: name)
            item.label = name
            item.view = settingsPage(sections)
            tabs.addTabViewItem(item)
        }
        let header = NSStackView(views: [title, message])
        header.orientation = .vertical
        header.spacing = 6
        header.alignment = .centerX
        let stack = NSStackView(views: [header, tabs, feedbackLabel])
        stack.orientation = .vertical
        stack.spacing = 20
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.stringValue = "Changes are saved automatically"
        feedbackLabel.textColor = .secondaryLabelColor

        let effect = NSVisualEffectView()
        effect.material = .windowBackground
        effect.state = .active
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -18),
            tabs.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return effect
    }

    private func settingsPage(_ sections: [NSView]) -> NSView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 434),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        for section in sections {
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return scroll
    }

    /// Dock hover previews. Kept to two controls: whether the feature runs, and
    /// how long the pointer must rest before it appears. The preview style is
    /// deliberately not duplicated — the feature reuses the setting above.
    private func makeDockPreviewsSection() -> NSStackView {
        let heading = NSTextField(labelWithString: "Dock previews")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let help = NSTextField(
            wrappingLabelWithString: "Rest the pointer on an application's Dock icon to preview its open windows and switch to one directly."
        )
        help.font = .systemFont(ofSize: 11.5)
        help.textColor = .secondaryLabelColor
        help.maximumNumberOfLines = 2
        help.preferredMaxLayoutWidth = 434

        dockPreviewCheckbox.target = self
        dockPreviewCheckbox.action = #selector(toggleDockPreviews)
        dockPreviewCheckbox.state = DockPreviewPreference.isEnabled ? .on : .off
        dockPreviewCheckbox.setAccessibilityHelp(
            "Shows a preview of an application's open windows when you hover over its Dock icon."
        )

        let delayHeading = NSTextField(labelWithString: "Hover delay")
        delayHeading.font = .systemFont(ofSize: 13, weight: .medium)

        dockPreviewDelayControl.segmentCount = Self.dockHoverDelayOptions.count
        for (index, milliseconds) in Self.dockHoverDelayOptions.enumerated() {
            dockPreviewDelayControl.setLabel("\(milliseconds) ms", forSegment: index)
            dockPreviewDelayControl.setWidth(88, forSegment: index)
        }
        dockPreviewDelayControl.trackingMode = .selectOne
        dockPreviewDelayControl.segmentStyle = .rounded
        dockPreviewDelayControl.target = self
        dockPreviewDelayControl.action = #selector(changeDockPreviewDelay)
        dockPreviewDelayControl.setAccessibilityLabel("Dock preview hover delay")
        dockPreviewDelayControl.isEnabled = DockPreviewPreference.isEnabled
        selectDockPreviewDelay(DockPreviewPreference.hoverDelayMilliseconds)

        dockPreviewDescriptionLabel.font = .systemFont(ofSize: 11.5)
        dockPreviewDescriptionLabel.textColor = .secondaryLabelColor
        dockPreviewDescriptionLabel.maximumNumberOfLines = 3
        dockPreviewDescriptionLabel.preferredMaxLayoutWidth = 434
        updateDockPreviewDescription()

        dockPreviewStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        thumbnailSizeControl.segmentCount = Self.thumbnailWidths.count
        for (index, label) in ["Small", "Medium", "Large"].enumerated() {
            thumbnailSizeControl.setLabel(label, forSegment: index)
            thumbnailSizeControl.setWidth(88, forSegment: index)
        }
        thumbnailSizeControl.selectedSegment = Self.thumbnailWidths.enumerated().min {
            abs($0.element - DockPreviewPreference.thumbnailWidth) < abs($1.element - DockPreviewPreference.thumbnailWidth)
        }?.offset ?? 1
        thumbnailSizeControl.target = self
        thumbnailSizeControl.action = #selector(changeThumbnailSize)
        thumbnailSizeControl.setAccessibilityLabel("Dock thumbnail size")
        let sizeHeading = NSTextField(labelWithString: "Thumbnail size")
        sizeHeading.font = .systemFont(ofSize: 13, weight: .medium)
        let sizeHelp = NSTextField(wrappingLabelWithString: "Automatically shrinks for larger groups. Scroll to see additional windows.")
        sizeHelp.font = .systemFont(ofSize: 11.5)
        sizeHelp.textColor = .secondaryLabelColor
        sizeHelp.preferredMaxLayoutWidth = 434
        focusOnHoverCheckbox.state = DockPreviewPreference.focusOnHover ? .on : .off
        focusOnHoverCheckbox.target = self
        focusOnHoverCheckbox.action = #selector(changeFocusOnHover)
        let focusHelp = NSTextField(wrappingLabelWithString: "Hover to look, click to switch. Leaving restores your original window. Minimized and full-screen windows open only when clicked.")
        focusHelp.font = .systemFont(ofSize: 11.5)
        focusHelp.textColor = .secondaryLabelColor
        focusHelp.preferredMaxLayoutWidth = 434

        let section = NSStackView(
            views: [
                heading,
                help,
                dockPreviewCheckbox,
                delayHeading,
                dockPreviewDelayControl,
                dockPreviewDescriptionLabel,
                sizeHeading,
                thumbnailSizeControl,
                sizeHelp,
                focusOnHoverCheckbox,
                focusHelp,
                dockPreviewStatusLabel
            ]
        )
        section.orientation = .vertical
        section.spacing = 8
        section.alignment = .leading
        section.setCustomSpacing(12, after: help)
        section.setCustomSpacing(12, after: dockPreviewCheckbox)
        section.widthAnchor.constraint(equalToConstant: 434).isActive = true
        return section
    }

    private func selectDockPreviewDelay(_ milliseconds: Int) {
        let clamped = DockHoverStateMachine.clampedHoverDelay(milliseconds: milliseconds)
        if let exact = Self.dockHoverDelayOptions.firstIndex(of: clamped) {
            dockPreviewDelayControl.selectedSegment = exact
            return
        }
        // A stored value outside the offered options still needs a sensible
        // selection; the nearest option is shown.
        let nearest = Self.dockHoverDelayOptions.enumerated().min { lhs, rhs in
            abs(lhs.element - clamped) < abs(rhs.element - clamped)
        }
        dockPreviewDelayControl.selectedSegment = nearest?.offset ?? 0
    }

    private func updateDockPreviewDescription() {
        let enabled = DockPreviewPreference.isEnabled
        dockPreviewDelayControl.isEnabled = enabled
        thumbnailSizeControl.isEnabled = enabled
        focusOnHoverCheckbox.isEnabled = enabled
        dockPreviewDescriptionLabel.stringValue = enabled
            ? "Uses the preview style selected above. Requires Accessibility access."
            : "Dock previews are off. The switcher is unaffected."
    }

    /// Reflects why Dock previews can or cannot run. Shown here as well as in the
    /// menu bar, because a silent no-op with no explanation is the worst outcome
    /// for a feature that depends on Accessibility access.
    func setDockPreviewAvailability(_ availability: DockPreviewAvailability) {
        switch availability {
        case .ready:
            dockPreviewStatusLabel.stringValue = "✓ Ready"
            dockPreviewStatusLabel.textColor = .systemGreen
        case .disabled:
            dockPreviewStatusLabel.stringValue = "Off"
            dockPreviewStatusLabel.textColor = .secondaryLabelColor
        case .needsAccessibilityPermission:
            dockPreviewStatusLabel.stringValue = "Requires Accessibility access"
            dockPreviewStatusLabel.textColor = .systemOrange
        }
    }

    private func configureStatus(granted: Bool) {        accessibilityStatusLabel.stringValue = granted ? "✓ Granted" : "Required"
        accessibilityStatusLabel.textColor = granted ? .systemGreen : .secondaryLabelColor
        accessibilityActionButton.title = granted ? "Open System Settings…" : "Grant Access…"
        accessibilityStatusLabel.toolTip = granted
            ? nil
            : "If MacCommandTab is already enabled, repair its stale development-build entry in System Settings."
    }

    private func configureScreenCaptureStatus(granted: Bool) {
        if granted {
            screenCaptureStatusLabel.stringValue = "✓ Granted"
            screenCaptureStatusLabel.textColor = .systemGreen
            screenCaptureIdentityLabel.stringValue = ""
            screenCaptureActionButton.title = "Open System Settings…"
            return
        }

        let setupState = ScreenCapturePermission.setupState
        screenCaptureStatusLabel.textColor = setupState == .notRequested
            ? .secondaryLabelColor
            : .systemOrange
        screenCaptureActionButton.title = setupState.actionTitle
        switch setupState {
        case .notRequested:
            screenCaptureStatusLabel.stringValue = "Required for window previews"
            screenCaptureIdentityLabel.stringValue = ScreenCapturePermission.identityHelp
        case .waitingForRelaunch:
            screenCaptureStatusLabel.stringValue = "Enable this build in System Settings, then relaunch"
            screenCaptureIdentityLabel.stringValue = runningBuildDescription
        case .repairAvailable:
            screenCaptureStatusLabel.stringValue = "Permission is attached to an older build"
            screenCaptureIdentityLabel.stringValue = "Resetting affects only \(ScreenCapturePermission.applicationName). \(runningBuildDescription)"
        }
    }

    private func configureLoginItemStatus(error: Error? = nil) {
        let status = SMAppService.mainApp.status
        startAtLoginCheckbox.state = status == .enabled || status == .requiresApproval ? .on : .off

        if let error, status != .requiresApproval {
            loginItemStatusLabel.stringValue = "Couldn’t update Start at Login: \(error.localizedDescription)"
            loginItemStatusLabel.textColor = .systemRed
            return
        }

        loginItemStatusLabel.textColor = .secondaryLabelColor
        switch status {
        case .enabled:
            loginItemStatusLabel.stringValue = "MacCommandTab will open automatically when you sign in."
        case .requiresApproval:
            loginItemStatusLabel.stringValue = "Approval required in System Settings → Login Items."
            loginItemStatusLabel.textColor = .systemOrange
        case .notRegistered:
            loginItemStatusLabel.stringValue = "Keep the window switcher ready after every sign-in."
        case .notFound:
            loginItemStatusLabel.stringValue = "Start at Login is unavailable for this app build."
        @unknown default:
            loginItemStatusLabel.stringValue = "Start at Login status is unavailable."
        }
    }

    @objc private func changePreviewMode() {
        let index = previewModeControl.selectedSegment
        guard PreviewMode.allCases.indices.contains(index) else { return }
        let mode = PreviewMode.allCases[index]
        previewModeDescriptionLabel.stringValue = mode.description
        onPreviewModeChanged?(mode)
        showFeedback("Preview mode changed to \(mode.title)")
    }

    @objc private func toggleDockPreviews() {
        let enabled = dockPreviewCheckbox.state == .on
        DockPreviewPreference.save(enabled: enabled)
        updateDockPreviewDescription()
        onDockPreviewEnabledChanged?(enabled)
        showFeedback(enabled ? "✓ Dock previews enabled" : "Dock previews disabled")
    }

    @objc private func changeThumbnailSize() {
        let index = thumbnailSizeControl.selectedSegment
        guard Self.thumbnailWidths.indices.contains(index) else { return }
        DockPreviewPreference.save(thumbnailWidth: Self.thumbnailWidths[index])
        showFeedback("Thumbnail size saved · applies on your next Dock hover")
    }

    @objc private func changeFocusOnHover() {
        DockPreviewPreference.save(focusOnHover: focusOnHoverCheckbox.state == .on)
        showFeedback("Hover behavior saved")
    }

    @objc private func changeDockPreviewDelay() {
        let index = dockPreviewDelayControl.selectedSegment
        guard Self.dockHoverDelayOptions.indices.contains(index) else { return }
        let milliseconds = Self.dockHoverDelayOptions[index]
        DockPreviewPreference.save(hoverDelayMilliseconds: milliseconds)
        onDockPreviewHoverDelayChanged?(milliseconds)
        showFeedback("Dock hover delay set to \(milliseconds) ms")
    }

    @objc private func toggleStartAtLogin() {        let service = SMAppService.mainApp
        do {
            if startAtLoginCheckbox.state == .on {
                if service.status == .notRegistered || service.status == .notFound {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            configureLoginItemStatus()
            showFeedback(
                startAtLoginCheckbox.state == .on
                    ? "✓ Launch at Login enabled"
                    : "Launch at Login disabled"
            )
        } catch {
            configureLoginItemStatus(error: error)
        }
    }

    @objc private func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func requestScreenCapturePermission() {
        if ScreenCapturePermission.isGranted {
            ScreenCapturePermission.openSystemSettings()
            return
        }

        switch ScreenCapturePermission.setupState {
        case .notRequested:
            if ScreenCapturePermission.request() {
                showFeedback("✓ Window previews enabled")
                updateStatus()
            } else {
                ScreenCapturePermission.openSystemSettings()
                configureScreenCaptureStatus(granted: false)
            }
        case .waitingForRelaunch:
            ScreenCapturePermission.relaunch()
        case .repairAvailable:
            repairScreenCapturePermission()
        }
    }

    @objc private func openScreenCaptureSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    @objc private func checkAccessibilityPermission() {
        accessibilityCheckTask?.cancel()
        guard !AccessibilityPermission.isGranted else {
            updateStatus()
            return
        }

        accessibilityStatusLabel.stringValue = "Waiting for approval…"
        accessibilityStatusLabel.textColor = .systemOrange
        AccessibilityPermission.request()
        accessibilityCheckTask = Task { @MainActor [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                if AccessibilityPermission.isGranted {
                    self?.updateStatus()
                    return
                }
            }
            self?.updateStatus()
        }
    }

    @objc private func openAccessibilitySettings() {
        if !AccessibilityPermission.isGranted { AccessibilityPermission.request() }
        AccessibilityPermission.openSystemSettings()
        checkAccessibilityPermission()
    }

    private func repairAccessibilityPermission() {
        accessibilityCheckTask?.cancel()
        accessibilityStatusLabel.stringValue = "Resetting stale entry…"
        accessibilityStatusLabel.textColor = .systemOrange

        accessibilityCheckTask = Task { @MainActor [weak self] in
            let resetSucceeded = await AccessibilityPermission.resetStaleEntry()
            guard let self, !Task.isCancelled else { return }
            guard resetSucceeded else {
                accessibilityStatusLabel.stringValue = "Reset failed — open settings"
                accessibilityStatusLabel.textColor = .systemRed
                AccessibilityPermission.openSystemSettings()
                return
            }

            AccessibilityPermission.request()
            AccessibilityPermission.openSystemSettings()
            accessibilityStatusLabel.stringValue = "Approve the fresh entry…"
            accessibilityStatusLabel.textColor = .systemOrange
        }
    }

    private func repairScreenCapturePermission() {
        screenCaptureRepairTask?.cancel()
        screenCaptureStatusLabel.stringValue = "Resetting this build’s permission…"
        screenCaptureStatusLabel.textColor = .systemOrange
        screenCaptureActionButton.isEnabled = false

        screenCaptureRepairTask = Task { @MainActor [weak self] in
            let resetSucceeded = await ScreenCapturePermission.resetStaleEntry()
            guard let self, !Task.isCancelled else { return }
            screenCaptureActionButton.isEnabled = true
            guard resetSucceeded else {
                screenCaptureStatusLabel.stringValue = "Couldn’t reset permission"
                screenCaptureStatusLabel.textColor = .systemRed
                showFeedback("Open System Settings and remove the stale MacCommandTab entry.")
                return
            }

            ScreenCapturePermission.setupState = .notRequested
            if ScreenCapturePermission.request() {
                showFeedback("✓ Window previews enabled")
                updateStatus()
            } else {
                configureScreenCaptureStatus(granted: false)
                ScreenCapturePermission.openSystemSettings()
            }
        }
    }

    private var runningBuildDescription: String {
        "Current build: \(ScreenCapturePermission.bundleIdentifier) at \(ScreenCapturePermission.applicationPath)"
    }

    private func showFeedback(_ message: String) {
        feedbackLabel.stringValue = message
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

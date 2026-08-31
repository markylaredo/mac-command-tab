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
    private var accessibilityCheckTask: Task<Void, Never>?
    private var screenCaptureRepairTask: Task<Void, Never>?
    var onAccessibilityPermissionChanged: ((Bool) -> Void)?
    var onScreenCapturePermissionChanged: ((Bool) -> Void)?
    var onPreviewModeChanged: ((PreviewMode) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(ScreenCapturePermission.applicationName) Settings"
        window.isReleasedWhenClosed = false
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
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center

        let message = NSTextField(
            wrappingLabelWithString: "Fast window switching, configured for this Mac."
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
        permissionRow.widthAnchor.constraint(equalToConstant: 414).isActive = true

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
            wrappingLabelWithString: "Screen Recording permission is used only to show open windows inside the switcher."
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

        let stack = NSStackView(
            views: [title, message, generalSection, previewSection, permissionsSection, feedbackLabel]
        )
        stack.orientation = .vertical
        stack.spacing = 20
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .contentBackground
        effect.state = .active
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 38),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -38),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        return effect
    }

    private func configureStatus(granted: Bool) {
        accessibilityStatusLabel.stringValue = granted ? "✓ Granted" : "Required"
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

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
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

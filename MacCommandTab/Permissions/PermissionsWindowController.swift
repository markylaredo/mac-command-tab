import AppKit

@MainActor
final class PermissionsWindowController: NSWindowController {
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenCaptureStatusLabel = NSTextField(labelWithString: "")
    private let effectsPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let effectsStatusLabel = NSTextField(labelWithString: "Ready")
    var onAccessibilityPermissionChanged: ((Bool) -> Void)?
    var onScreenCapturePermissionChanged: ((Bool) -> Void)?
    var onPreviewEffect: ((WindowEffect) -> Bool)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacCommandTab Permissions"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        updateStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatus(notify: Bool = true) {
        let accessibilityGranted = AccessibilityPermission.isGranted
        let screenCaptureGranted = ScreenCapturePermission.isGranted
        configure(accessibilityStatusLabel, granted: accessibilityGranted)
        configure(screenCaptureStatusLabel, granted: screenCaptureGranted)
        if notify {
            onAccessibilityPermissionChanged?(accessibilityGranted)
            onScreenCapturePermissionChanged?(screenCaptureGranted)
        }
    }

    private func makeContentView() -> NSView {
        let title = NSTextField(labelWithString: "Switch windows at a glance")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center

        let message = NSTextField(wrappingLabelWithString: "Accessibility enables Option+Tab and exact window activation. Screen Recording adds live window previews.")
        message.font = .systemFont(ofSize: 14)
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3

        let accessibilityRow = permissionRow(
            title: "Accessibility",
            statusLabel: accessibilityStatusLabel,
            actionTitle: "Check Permission",
            action: #selector(checkAccessibilityPermission),
            settingsAction: #selector(openAccessibilitySettings)
        )
        let screenCaptureRow = permissionRow(
            title: "Window Previews",
            statusLabel: screenCaptureStatusLabel,
            actionTitle: "Enable Previews",
            action: #selector(requestScreenCapturePermission),
            settingsAction: #selector(openScreenCaptureSettings)
        )
        let effectsPreview = effectsPreviewSection()

        let stack = NSStackView(views: [title, message, accessibilityRow, screenCaptureRow, effectsPreview])
        stack.orientation = .vertical
        stack.spacing = 18
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

    private func effectsPreviewSection() -> NSView {
        let heading = NSTextField(labelWithString: "WINDOW EFFECTS LAB")
        heading.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        heading.textColor = .systemCyan

        let caption = NSTextField(labelWithString: "Preview the GPU transition on a sample window. No application window is changed.")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2

        for effect in WindowEffect.allCases where effect != .none {
            effectsPopUp.addItem(withTitle: effect.title)
            effectsPopUp.lastItem?.representedObject = effect.rawValue
        }
        effectsPopUp.selectItem(withTitle: WindowEffect.glide.title)

        let previewButton = NSButton(title: "Preview Effect", target: self, action: #selector(previewSelectedEffect))
        previewButton.bezelStyle = .rounded
        previewButton.keyEquivalent = ""

        effectsStatusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        effectsStatusLabel.textColor = .tertiaryLabelColor

        let controls = NSStackView(views: [effectsPopUp, previewButton, NSView(), effectsStatusLabel])
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.alignment = .centerY

        let stack = NSStackView(views: [heading, caption, controls])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = 12
        box.borderWidth = 1
        box.borderColor = NSColor.systemCyan.withAlphaComponent(0.24)
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        box.widthAnchor.constraint(equalToConstant: 444).isActive = true
        box.heightAnchor.constraint(equalToConstant: 120).isActive = true
        box.contentView?.addSubview(stack)
        if let contentView = box.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        return box
    }

    private func permissionRow(
        title: String,
        statusLabel: NSTextField,
        actionTitle: String,
        action: Selector,
        settingsAction: Selector
    ) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let labels = NSStackView(views: [heading, statusLabel])
        labels.orientation = .vertical
        labels.spacing = 3
        labels.alignment = .leading

        let actionButton = NSButton(title: actionTitle, target: self, action: action)
        actionButton.bezelStyle = .rounded
        let settingsButton = NSButton(title: "System Settings…", target: self, action: settingsAction)
        settingsButton.bezelStyle = .rounded

        let row = NSStackView(views: [labels, NSView(), actionButton, settingsButton])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return row
    }

    private func configure(_ label: NSTextField, granted: Bool) {
        label.stringValue = granted ? "Granted" : "Permission required"
        label.textColor = granted ? .systemGreen : .secondaryLabelColor
    }

    @objc private func checkAccessibilityPermission() {
        if !AccessibilityPermission.isGranted { AccessibilityPermission.request() }
        updateStatus()
    }

    @objc private func requestScreenCapturePermission() {
        if !ScreenCapturePermission.isGranted { ScreenCapturePermission.request() }
        updateStatus()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func openScreenCaptureSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    @objc private func previewSelectedEffect() {
        guard let rawValue = effectsPopUp.selectedItem?.representedObject as? String,
              let effect = WindowEffect(rawValue: rawValue) else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            effectsStatusLabel.stringValue = "Reduce Motion is on"
            return
        }

        let started = onPreviewEffect?(effect) ?? false
        effectsStatusLabel.stringValue = started ? "Playing \(effect.title)…" : "Preview unavailable"
        effectsStatusLabel.textColor = started ? .systemCyan : .systemOrange

        guard started else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + effect.defaultDuration + 0.18) { [weak self] in
            self?.effectsStatusLabel.stringValue = "Ready"
            self?.effectsStatusLabel.textColor = .tertiaryLabelColor
        }
    }
}

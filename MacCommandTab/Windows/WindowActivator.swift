@preconcurrency import AppKit
@preconcurrency import ApplicationServices

final class WindowActivator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.maccommandtab.window-activation", qos: .userInitiated)
    private var pendingPreviewTask: Task<Void, Never>?

    @MainActor
    func preview(
        _ window: WindowInfo?,
        onPresented: (@MainActor @Sendable () -> Void)? = nil
    ) {
        pendingPreviewTask?.cancel()
        guard let window,
              !window.isMinimized,
              !window.isApplicationHidden,
              !window.isFullscreen else { return }

        pendingPreviewTask = Task { [queue] in
            // Coalesce fast key repeat so stale windows are never queued for
            // presentation. Selection UI still updates synchronously.
            try? await Task.sleep(for: .milliseconds(24))
            guard !Task.isCancelled else { return }

            // AX raise is sufficient within the foreground application. A
            // background app needs this narrowly scoped public activation
            // fallback before its real window can appear above other apps.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
                NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            }

            queue.async {
                let application = AXUIElementCreateApplication(window.pid)
                AXUIElementSetAttributeValue(
                    application,
                    kAXFocusedWindowAttribute as CFString,
                    window.accessibilityElement
                )
                AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString)
            }
            onPresented?()
        }
    }

    @MainActor
    func restore(_ window: WindowInfo?) {
        pendingPreviewTask?.cancel()
        guard let window else { return }

        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        queue.async {
            let application = AXUIElementCreateApplication(window.pid)
            AXUIElementSetAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                window.accessibilityElement
            )
            AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString)
        }
    }

    @MainActor
    func activate(_ window: WindowInfo) {
        pendingPreviewTask?.cancel()
        if let application = NSRunningApplication(processIdentifier: window.pid) {
            if application.isHidden { application.unhide() }
            application.activate(options: [])
        }
        queue.async {
            if window.isMinimized {
                AXUIElementSetAttributeValue(window.accessibilityElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            let application = AXUIElementCreateApplication(window.pid)
            AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, window.accessibilityElement)
            AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString)
        }
    }
}

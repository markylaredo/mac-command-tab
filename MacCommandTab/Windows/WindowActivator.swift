@preconcurrency import AppKit
@preconcurrency import ApplicationServices

final class WindowActivator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.maccommandtab.window-activation", qos: .userInitiated)

    @MainActor
    func activate(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
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

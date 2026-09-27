@preconcurrency import ApplicationServices
import Foundation

/// Closes a specific window through the accessibility API.
///
/// Uses the standard `AXCloseButton` — the same control the window's own close
/// button drives — so applications receive a normal close request. It never
/// terminates an application, and it reports whether closing is supported so the
/// UI can omit the control entirely rather than offering a button that does
/// nothing.
struct WindowCloser: Sendable {
    /// Whether this window exposes a usable close control, so the UI can omit the
    /// control rather than offering a button that does nothing.
    ///
    /// One attribute lookup per card. Element references are stable, so this is
    /// cheap enough to evaluate while building the preview list.
    @MainActor
    func canClose(_ window: WindowInfo) -> Bool {
        Self.closeButton(of: window.accessibilityElement) != nil
    }

    /// Requests that `window` close. `completion` runs on the main actor with the
    /// result, so the caller can refresh its list.
    @MainActor
    func close(
        _ window: WindowInfo,
        queue: DispatchQueue,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        let element = window.accessibilityElement
        queue.async {
            let closed = Self.performClose(on: element)
            if let completion {
                Task { @MainActor in completion(closed) }
            }
        }
    }

    nonisolated private static func performClose(on element: AXUIElement) -> Bool {
        if let button = closeButton(of: element) {
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
        // Windows that expose no close button are rare. The close action is the
        // same one the standard control performs. Its constant is not published
        // in the SDK headers, so the string is used directly.
        return AXUIElementPerformAction(element, "AXClose" as CFString) == .success
    }

    nonisolated private static func closeButton(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

@preconcurrency import ApplicationServices
import Foundation

final class WindowDiscovery: @unchecked Sendable {
    func discover(applications: [ApplicationSnapshot]) -> [WindowInfo] {
        applications.flatMap(discoverWindows)
    }

    func describeWindow(
        _ element: AXUIElement,
        application: ApplicationSnapshot,
        focusedWindow: AXUIElement? = nil
    ) -> WindowInfo? {
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == (kAXWindowRole as String) else {
            return nil
        }

        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
        let allowedSubroles = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]
        if let subrole, !allowedSubroles.contains(subrole) {
            return nil
        }

        guard let size = sizeAttribute(kAXSizeAttribute as CFString, from: element), size.width > 0, size.height > 0 else {
            return nil
        }
        let position = pointAttribute(kAXPositionAttribute as CFString, from: element) ?? .zero

        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimized = boolAttribute(kAXMinimizedAttribute as CFString, from: element) ?? false
        let fullscreen = boolAttribute("AXFullScreen" as CFString, from: element) ?? false
        let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window"

        return WindowInfo(
            id: WindowID(rawValue: "\(application.pid):\(CFHash(element))"),
            pid: application.pid,
            title: displayTitle,
            applicationName: application.name,
            bundleIdentifier: application.bundleIdentifier,
            icon: application.icon,
            accessibilityElement: element,
            isMinimized: minimized,
            isFullscreen: fullscreen,
            isApplicationHidden: application.isHidden,
            isFocused: focusedWindow.map { CFEqual($0, element) } ?? false,
            frame: CGRect(origin: position, size: size)
        )
    }

    private func discoverWindows(for application: ApplicationSnapshot) -> [WindowInfo] {
        let appElement = AXUIElementCreateApplication(application.pid)
        guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: appElement) else {
            return []
        }
        let focusedWindow: AXUIElement? = attribute(kAXFocusedWindowAttribute as CFString, from: appElement)
        return windows.compactMap {
            describeWindow($0, application: application, focusedWindow: focusedWindow)
        }
    }

    private func attribute<T>(_ name: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? T
    }

    private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String? {
        attribute(name, from: element)
    }

    private func boolAttribute(_ name: CFString, from element: AXUIElement) -> Bool? {
        (attribute(name, from: element) as NSNumber?)?.boolValue
    }

    private func sizeAttribute(_ name: CFString, from element: AXUIElement) -> CGSize? {
        guard let value: AXValue = attribute(name, from: element), AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func pointAttribute(_ name: CFString, from element: AXUIElement) -> CGPoint? {
        guard let value: AXValue = attribute(name, from: element), AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }
}

import AppKit
import ApplicationServices

struct WindowID: Hashable, Sendable {
    let rawValue: String
}

struct WindowInfo: Identifiable, @unchecked Sendable {
    let id: WindowID
    let pid: pid_t
    let title: String
    let applicationName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let accessibilityElement: AXUIElement
    let isMinimized: Bool
    let isFullscreen: Bool
    let isApplicationHidden: Bool
    let isFocused: Bool
    let frame: CGRect
}

struct ApplicationSnapshot: @unchecked Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let isHidden: Bool
}

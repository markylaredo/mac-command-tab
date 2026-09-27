import Foundation

/// Whether the Dock hover previews can currently run, and why not when they
/// cannot.
///
/// The feature is entirely best-effort, so this is diagnostic only: it never
/// gates the switcher, and no other part of MacCommandTab consults it.
enum DockPreviewAvailability: Equatable, Sendable {
    case ready
    case disabled
    case needsAccessibilityPermission

    var menuTitle: String {
        switch self {
        case .ready: "Dock Previews: Active"
        case .disabled: "Dock Previews: Off"
        case .needsAccessibilityPermission: "Dock Previews: Accessibility Required"
        }
    }
}

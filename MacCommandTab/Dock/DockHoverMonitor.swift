import AppKit
import Foundation

/// Watches global pointer movement while the user is elsewhere.
///
/// A passive `NSEvent` global monitor rather than an event tap: the feature only
/// needs to observe, never consume or alter input, so it must not sit in the path
/// of the user's keystrokes and clicks the way `GlobalHotkeyMonitor` does. That
/// distinction is what keeps Option–Tab and ordinary typing unaffected.
///
/// The monitor owns no Dock knowledge. It asks its `activeZoneProbe` whether a
/// position is worth acting on, and `DockHoverPointerGate` decides which samples
/// to pass on.
@MainActor
final class DockHoverMonitor {
    /// Called for pointer positions inside the active zone, and once when the
    /// pointer leaves it.
    var onPointerMoved: ((CGPoint) -> Void)?

    /// Whether a position is inside the region the feature cares about. Supplied
    /// by the caller so this type stays free of Dock specifics.
    var activeZoneProbe: ((CGPoint) -> Bool)?

    private var state = DockHoverPointerGate()
    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    /// Exposed for diagnostics: whether the pointer is currently considered to be
    /// inside the Dock or preview panel.
    var isTrackingInsideZone: Bool { state.isTrackingInsideZone }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            // `NSEvent.mouseLocation` rather than the event, so the coordinate
            // space is the same one the Dock's accessibility frames use.
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.handle(location: location)
            }
        }
        state.reset()
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        state.reset()
    }

    private func handle(location: CGPoint) {
        let isInsideZone = activeZoneProbe?(location) ?? false
        guard state.shouldReport(isInsideZone: isInsideZone, at: CACurrentMediaTime()) else { return }
        onPointerMoved?(location)
    }
}

import CoreGraphics
import Foundation

/// Decides which pointer samples the Dock hover feature should act on.
///
/// Split out of `DockHoverMonitor` so the rule that matters most can be tested
/// directly, without a run loop, a global event monitor, or a Dock. The rule is:
/// samples inside the active zone are throttled, but the transition *out* of the
/// zone is always delivered.
///
/// That trailing sample is what starts the dismissal grace period. Suppressing it
/// as "outside the zone, therefore uninteresting" would leave a preview on screen
/// indefinitely, so it is handled explicitly rather than falling out of the
/// throttle.
struct DockHoverPointerGate: Sendable {
    /// Sample rate cap. Pointer events arrive far faster than the interaction
    /// needs, and Dock hit testing is not free.
    let minimumInterval: CFTimeInterval

    private var lastReportedTime: CFTimeInterval = 0
    private var isInsideActiveZone = false
    private var hasReported = false

    init(minimumInterval: CFTimeInterval = 1.0 / 30.0) {
        self.minimumInterval = minimumInterval
    }

    var isTrackingInsideZone: Bool { isInsideActiveZone }

    /// Returns true when the caller should process this sample.
    ///
    /// - Parameter isInsideZone: whether the sample falls inside the Dock or the
    ///   preview panel.
    mutating func shouldReport(isInsideZone: Bool, at time: CFTimeInterval) -> Bool {
        // Leaving the zone is always reported, exactly once, and is never
        // throttled: it is the only sample that can begin a dismissal.
        if isInsideActiveZone && !isInsideZone {
            isInsideActiveZone = false
            hasReported = false
            lastReportedTime = time
            return true
        }

        // Wholly outside the zone and already outside it. This is the common case
        // while the user works elsewhere, and it costs one rectangle test.
        guard isInsideZone else {
            isInsideActiveZone = false
            return false
        }

        isInsideActiveZone = true

        // The first sample of an entry is always reported, so neither a pointer
        // that starts on the Dock nor one that returns to it is held back by the
        // throttle. A returning pointer is what cancels a pending dismissal, so
        // delaying it would let a preview disappear under the cursor.
        guard hasReported else {
            hasReported = true
            lastReportedTime = time
            return true
        }

        guard time - lastReportedTime >= minimumInterval else { return false }
        lastReportedTime = time
        return true
    }

    mutating func reset() {
        lastReportedTime = 0
        isInsideActiveZone = false
        hasReported = false
    }
}

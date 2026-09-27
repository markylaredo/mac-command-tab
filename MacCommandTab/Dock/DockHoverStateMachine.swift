import Foundation

/// What the Dock hover feature should do in response to a state change.
enum DockHoverEffect: Equatable, Sendable {
    /// Arm the hover delay for `application`.
    case scheduleShow(application: DockResolvedApplication)
    /// Cancel an armed hover delay.
    case cancelScheduledShow
    /// The application's tiles should become visible.
    case present(application: DockResolvedApplication)
    /// Arm the dismissal grace period.
    case scheduleDismiss
    /// Cancel an armed dismissal.
    case cancelScheduledDismiss
    /// Hide the previews now.
    case dismiss
}

/// A resolved Dock application, reduced to what the hover logic needs. Carrying
/// this instead of `NSRunningApplication` keeps the state machine pure and
/// directly testable.
struct DockResolvedApplication: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
}

/// Where the pointer is relative to the two regions that make up one interaction:
/// the Dock tile being hovered, and the preview panel itself.
enum DockHoverPointerRegion: Equatable, Sendable {
    /// Over the Dock tile that owns the current preview.
    case hoveredItem
    /// Over the Dock, but not over that tile or the panel.
    case dockElsewhere
    /// Over the preview panel.
    case previewPanel
    /// Over neither. The pointer has genuinely left the interaction.
    case outside
}

/// Decides when to show and hide Dock window previews.
///
/// The whole feature's timing behaviour lives here, as a pure value type with no
/// clock, no timers, and no AppKit. The controller owns the timers and feeds
/// elapsed time in; that keeps every transition directly testable.
///
/// The visible/hidden decision rests on one idea: the Dock tile and the preview
/// panel form a single interaction region. Leaving the tile for the panel must
/// not dismiss anything, and leaving both must not dismiss instantly, because the
/// pointer is almost always travelling between them.
struct DockHoverStateMachine: Sendable {
    /// How long the pointer must rest on a Dock tile before previews appear.
    static let defaultHoverDelay: Duration = .milliseconds(300)
    /// How long the pointer may be outside both regions before dismissing.
    static let defaultDismissGracePeriod: Duration = .milliseconds(200)

    /// The accepted range for the configurable hover delay.
    static let hoverDelayRange: ClosedRange<Int> = 200...800

    static func clampedHoverDelay(milliseconds: Int) -> Int {
        min(max(milliseconds, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }

    private(set) var hoveredApplication: DockResolvedApplication?
    private(set) var visibleApplication: DockResolvedApplication?

    private var hoverDelayTaskArmed = false
    private var dismissTaskArmed = false
    private var pointerIsInDockRegion = false
    private var pointerIsOverPreviewPanel = false

    var isPreviewVisible: Bool { visibleApplication != nil }
    var hasScheduledShow: Bool { hoverDelayTaskArmed }
    var hasScheduledDismiss: Bool { dismissTaskArmed }

    /// The pointer moved. `application` is the Dock tile under it, or nil when the
    /// pointer is over the Dock but not over an application tile, or not over the
    /// Dock at all.
    mutating func pointerMoved(
        to application: DockResolvedApplication?,
        isWithinDockRegion: Bool
    ) -> [DockHoverEffect] {
        pointerIsInDockRegion = isWithinDockRegion

        guard let application else {
            // Not over an application tile. Anything pending for a different
            // tile is no longer relevant.
            var effects: [DockHoverEffect] = []
            hoveredApplication = nil
            if hoverDelayTaskArmed {
                hoverDelayTaskArmed = false
                effects.append(.cancelScheduledShow)
            }
            effects.append(contentsOf: evaluateDismissal())
            return effects
        }

        guard application != visibleApplication else {
            // Still on the tile that owns the visible preview. Any pending
            // dismissal is cancelled: the pointer is demonstrably back.
            var effects: [DockHoverEffect] = []
            hoveredApplication = application
            if hoverDelayTaskArmed {
                hoverDelayTaskArmed = false
                effects.append(.cancelScheduledShow)
            }
            if dismissTaskArmed {
                dismissTaskArmed = false
                effects.append(.cancelScheduledDismiss)
            }
            return effects
        }

        guard application != hoveredApplication else {
            // Resting on a tile whose delay is already armed. Re-scheduling here
            // would restart the timer on every pointer sample and the preview
            // would never appear.
            return []
        }

        // A different tile. Any preview for the previous application stays up
        // until the new one is ready, so the panel updates in place instead of
        // being destroyed and recreated.
        var effects: [DockHoverEffect] = []
        if hoverDelayTaskArmed {
            hoverDelayTaskArmed = false
            effects.append(.cancelScheduledShow)
        }
        if dismissTaskArmed {
            dismissTaskArmed = false
            effects.append(.cancelScheduledDismiss)
        }
        hoveredApplication = application
        hoverDelayTaskArmed = true
        effects.append(.scheduleShow(application: application))
        return effects
    }

    /// The hover delay elapsed.
    mutating func hoverDelayElapsed(for application: DockResolvedApplication) -> [DockHoverEffect] {
        guard hoverDelayTaskArmed,
              hoveredApplication == application,
              visibleApplication != application else {
            return []
        }
        hoverDelayTaskArmed = false
        visibleApplication = application
        return [.present(application: application)]
    }

    /// The dismissal grace period elapsed.
    mutating func dismissGracePeriodElapsed() -> [DockHoverEffect] {
        guard dismissTaskArmed else { return [] }
        return finishDismissal()
    }

    /// The pointer entered or left the preview panel.
    ///
    /// `isWithinDockRegion` reflects the most recent pointer sample, so leaving
    /// the panel always arms the dismissal grace period rather than deciding
    /// outright: the pointer has that window to return to the Dock or the panel.
    /// A pointer that comes straight back cancels the dismissal on the next
    /// sample, so this cannot strand a preview on screen.
    mutating func pointerEnteredPreviewPanel() -> [DockHoverEffect] {
        pointerIsOverPreviewPanel = true
        guard dismissTaskArmed else { return [] }
        dismissTaskArmed = false
        return [.cancelScheduledDismiss]
    }

    mutating func pointerExitedPreviewPanel() -> [DockHoverEffect] {
        // Dock movement also reports that the pointer is outside the panel.
        // Only an actual exit may affect an in-flight hover timer.
        guard pointerIsOverPreviewPanel else { return [] }
        pointerIsOverPreviewPanel = false
        return evaluateDismissal()
    }

    /// Dismiss immediately, for example after a preview was clicked, the feature
    /// was switched off, or the application lost all of its windows.
    mutating func dismissImmediately() -> [DockHoverEffect] {
        guard visibleApplication != nil || hoverDelayTaskArmed || dismissTaskArmed else { return [] }
        return finishDismissal()
    }

    /// Accessibility permission was revoked, so nothing can be resolved.
    mutating func permissionsRevoked() -> [DockHoverEffect] {
        dismissImmediately()
    }

    mutating func reset() {
        hoveredApplication = nil
        visibleApplication = nil
        hoverDelayTaskArmed = false
        dismissTaskArmed = false
        pointerIsInDockRegion = false
        pointerIsOverPreviewPanel = false
    }

    // MARK: - Private

    /// Decides whether the interaction has been abandoned. The panel is kept only
    /// while the pointer could plausibly still be moving towards it.
    private mutating func evaluateDismissal() -> [DockHoverEffect] {
        guard visibleApplication != nil else {
            // Nothing on screen. A pending delay for a tile the pointer has left
            // is simply abandoned.
            guard hoverDelayTaskArmed else { return [] }
            hoverDelayTaskArmed = false
            hoveredApplication = nil
            return [.cancelScheduledShow]
        }

        // Still inside the interaction region. This is the Dock-to-panel
        // transition, and it must never dismiss.
        if pointerIsOverPreviewPanel || pointerIsInDockRegion {
            guard dismissTaskArmed else { return [] }
            dismissTaskArmed = false
            return [.cancelScheduledDismiss]
        }

        guard !dismissTaskArmed else { return [] }
        dismissTaskArmed = true
        return [.scheduleDismiss]
    }

    private mutating func finishDismissal() -> [DockHoverEffect] {
        hoveredApplication = nil
        visibleApplication = nil
        hoverDelayTaskArmed = false
        dismissTaskArmed = false
        return [.dismiss]
    }
}

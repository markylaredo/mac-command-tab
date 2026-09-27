import XCTest
@testable import MacCommandTab

/// Cooperative-verification tests for the Dock hover interaction.
///
/// The state machine is a pure value type with no clock, so every timing and
/// transition rule is exercised directly, without the real Dock and without
/// waiting on wall-clock delays.
final class DockHoverStateMachineTests: XCTestCase {
    private let safari = DockResolvedApplication(
        processIdentifier: 100,
        bundleIdentifier: "com.apple.Safari",
        localizedName: "Safari"
    )
    private let rider = DockResolvedApplication(
        processIdentifier: 200,
        bundleIdentifier: "com.jetbrains.rider",
        localizedName: "Rider"
    )

    // MARK: - Hover delay

    func testHoverBeginsThenDelayExpiryPresents() {
        var machine = DockHoverStateMachine()

        XCTAssertEqual(
            machine.pointerMoved(to: safari, isWithinDockRegion: true),
            [.scheduleShow(application: safari)]
        )
        XCTAssertFalse(machine.isPreviewVisible)
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [.present(application: safari)])
        XCTAssertTrue(machine.isPreviewVisible)
    }

    func testHoverCancelledBeforeDelayDoesNotPresent() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)

        // The pointer left the Dock entirely.
        let effects = machine.pointerMoved(to: nil, isWithinDockRegion: false)

        XCTAssertEqual(effects, [.cancelScheduledShow])
        XCTAssertFalse(machine.isPreviewVisible)
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [])
    }

    func testRepeatedMovesOverSameTileDoNotReschedule() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)

        // A pointer resting on a tile still emits movement samples. Restarting
        // the delay for each one would mean the preview never appears.
        XCTAssertEqual(machine.pointerMoved(to: safari, isWithinDockRegion: true), [])
        XCTAssertEqual(machine.pointerMoved(to: safari, isWithinDockRegion: true), [])
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [.present(application: safari)])
    }

    func testLateDelayCallbackForSupersededTileIsIgnored() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.pointerMoved(to: rider, isWithinDockRegion: true)

        // Safari's timer fired after the pointer had already moved on.
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [])
        XCTAssertFalse(machine.isPreviewVisible)
        XCTAssertEqual(machine.hoverDelayElapsed(for: rider), [.present(application: rider)])
    }

    // MARK: - Dock to panel travel

    func testDockMovementOutsidePanelDoesNotCancelHover() {
        var machine = DockHoverStateMachine()
        // Replay the controller's exit check followed by the Dock sample.
        for _ in 0..<3 {
            XCTAssertEqual(machine.pointerExitedPreviewPanel(), [])
            _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        }
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [.present(application: safari)])
    }

    func testReturningToTileAfterCancelledHoverRestartsDelay() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.pointerMoved(to: nil, isWithinDockRegion: false)

        XCTAssertEqual(machine.pointerMoved(to: safari, isWithinDockRegion: true), [.scheduleShow(application: safari)])
        XCTAssertEqual(machine.hoverDelayElapsed(for: safari), [.present(application: safari)])
    }

    func testReturningToVisibleTileCancelsOtherApplicationPreview() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)
        _ = machine.pointerMoved(to: rider, isWithinDockRegion: true)

        XCTAssertEqual(machine.pointerMoved(to: safari, isWithinDockRegion: true), [.cancelScheduledShow])
        XCTAssertEqual(machine.hoverDelayElapsed(for: rider), [])
        XCTAssertEqual(machine.visibleApplication, safari)
        XCTAssertEqual(machine.pointerMoved(to: rider, isWithinDockRegion: true), [.scheduleShow(application: rider)])
    }

    func testPointerTravelFromDockIntoPanelKeepsPreviewOpen() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        // The pointer leaves the tile but is still over the Dock.
        XCTAssertEqual(machine.pointerMoved(to: nil, isWithinDockRegion: true), [])
        XCTAssertTrue(machine.isPreviewVisible)

        // It crosses the gap between the Dock and the panel. The Dock region
        // test is false here, which is exactly the moment a naive
        // implementation dismisses the preview.
        XCTAssertEqual(machine.pointerMoved(to: nil, isWithinDockRegion: false), [.scheduleDismiss])
        XCTAssertTrue(machine.isPreviewVisible)

        // It arrives on the panel.
        XCTAssertEqual(machine.pointerEnteredPreviewPanel(), [.cancelScheduledDismiss])
        XCTAssertTrue(machine.isPreviewVisible)
    }

    func testLeavingBothRegionsDismissesAfterGracePeriod() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        let effects = machine.pointerMoved(to: nil, isWithinDockRegion: false)

        XCTAssertEqual(effects, [.scheduleDismiss])
        XCTAssertTrue(machine.isPreviewVisible, "the preview must survive the grace period")
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [.dismiss])
        XCTAssertFalse(machine.isPreviewVisible)
    }

    func testReenteringDockDuringGracePeriodCancelsDismissal() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)
        _ = machine.pointerMoved(to: nil, isWithinDockRegion: false)

        // Back onto the same tile before the grace period expires.
        let effects = machine.pointerMoved(to: safari, isWithinDockRegion: true)

        XCTAssertEqual(effects, [.cancelScheduledDismiss])
        XCTAssertTrue(machine.isPreviewVisible)
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [])
    }

    func testLeavingPanelWhileStillOnDockKeepsPreviewOpen() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        // The pointer dipped off the tile but stayed on the Dock, then entered
        // and left the panel. Because the most recent position was still on the
        // Dock, leaving the panel does not end the interaction.
        _ = machine.pointerMoved(to: nil, isWithinDockRegion: true)
        _ = machine.pointerEnteredPreviewPanel()
        XCTAssertEqual(machine.pointerExitedPreviewPanel(), [])

        XCTAssertTrue(machine.isPreviewVisible)
        XCTAssertFalse(machine.hasScheduledDismiss)
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [])
    }

    func testFullExitSequenceDismissesOnlyAfterTheGracePeriod() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        // The pointer left the Dock, crossing the gap towards the panel. The
        // grace period starts here.
        XCTAssertEqual(machine.pointerMoved(to: nil, isWithinDockRegion: false), [.scheduleDismiss])
        XCTAssertTrue(machine.isPreviewVisible)

        // Arriving on the panel rescues it.
        XCTAssertEqual(machine.pointerEnteredPreviewPanel(), [.cancelScheduledDismiss])

        // Leaving the panel now really is leaving the whole interaction.
        XCTAssertEqual(machine.pointerExitedPreviewPanel(), [.scheduleDismiss])
        XCTAssertTrue(machine.isPreviewVisible)
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [.dismiss])
        XCTAssertFalse(machine.isPreviewVisible)
    }

    func testGracePeriodIsTheSameWhicheverRegionWasLeftLast() {
        // Leaving the Dock and leaving the panel must both start the same timer,
        // and neither may dismiss outright while the pointer could still return.
        var leftDock = DockHoverStateMachine()
        _ = leftDock.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = leftDock.hoverDelayElapsed(for: safari)
        XCTAssertEqual(leftDock.pointerMoved(to: nil, isWithinDockRegion: false), [.scheduleDismiss])

        var leftPanel = DockHoverStateMachine()
        _ = leftPanel.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = leftPanel.hoverDelayElapsed(for: safari)
        _ = leftPanel.pointerMoved(to: nil, isWithinDockRegion: false)
        _ = leftPanel.pointerEnteredPreviewPanel()
        XCTAssertEqual(leftPanel.pointerExitedPreviewPanel(), [.scheduleDismiss])

        XCTAssertTrue(leftDock.isPreviewVisible)
        XCTAssertTrue(leftPanel.isPreviewVisible)
    }

    func testReturningToThePanelAfterLeavingItCancelsDismissal() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)
        _ = machine.pointerMoved(to: nil, isWithinDockRegion: false)
        _ = machine.pointerEnteredPreviewPanel()
        _ = machine.pointerExitedPreviewPanel()

        // The pointer came straight back onto the panel.
        XCTAssertEqual(machine.pointerEnteredPreviewPanel(), [.cancelScheduledDismiss])
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [])
        XCTAssertTrue(machine.isPreviewVisible)
    }

    // MARK: - Switching applications

    func testMovingToAnotherDockAppSchedulesNewPreviewAndKeepsOldVisible() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        let effects = machine.pointerMoved(to: rider, isWithinDockRegion: true)

        XCTAssertEqual(effects, [.scheduleShow(application: rider)])
        // The Safari preview stays up until the Rider one is ready, so the panel
        // is updated in place rather than disappearing and reappearing.
        XCTAssertEqual(machine.visibleApplication, safari)
        XCTAssertEqual(machine.hoverDelayElapsed(for: rider), [.present(application: rider)])
        XCTAssertEqual(machine.visibleApplication, rider)
    }

    func testMovingAcrossNonApplicationTilesCancelsThePendingShow() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)

        // Over the Trash, which is on the Dock but is not an application.
        let effects = machine.pointerMoved(to: nil, isWithinDockRegion: true)

        XCTAssertEqual(effects, [.cancelScheduledShow])
        XCTAssertFalse(machine.isPreviewVisible)
    }

    // MARK: - Explicit dismissal

    func testDismissImmediatelyClearsEverything() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)
        _ = machine.pointerEnteredPreviewPanel()

        XCTAssertEqual(machine.dismissImmediately(), [.dismiss])
        XCTAssertFalse(machine.isPreviewVisible)
        XCTAssertNil(machine.hoveredApplication)
        XCTAssertFalse(machine.hasScheduledDismiss)
    }

    func testDismissImmediatelyIsIdleWhenNothingIsShowing() {
        var machine = DockHoverStateMachine()
        XCTAssertEqual(machine.dismissImmediately(), [])
    }

    func testPermissionsRevokedDismissesVisiblePreview() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)

        XCTAssertEqual(machine.permissionsRevoked(), [.dismiss])
        XCTAssertFalse(machine.isPreviewVisible)
    }

    func testLateGracePeriodCallbackAfterReentryIsIgnored() {
        var machine = DockHoverStateMachine()
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)
        _ = machine.hoverDelayElapsed(for: safari)
        _ = machine.pointerMoved(to: nil, isWithinDockRegion: false)
        _ = machine.pointerMoved(to: safari, isWithinDockRegion: true)

        // The dismissal timer fired after the pointer had already come back.
        XCTAssertEqual(machine.dismissGracePeriodElapsed(), [])
        XCTAssertTrue(machine.isPreviewVisible)
    }

    // MARK: - Delay clamping

    func testHoverDelayIsClampedToTheSupportedRange() {
        XCTAssertEqual(DockHoverStateMachine.clampedHoverDelay(milliseconds: 10), 200)
        XCTAssertEqual(DockHoverStateMachine.clampedHoverDelay(milliseconds: 300), 300)
        XCTAssertEqual(DockHoverStateMachine.clampedHoverDelay(milliseconds: 5_000), 800)
    }

    func testDefaultHoverDelayIsWithinTheDocumentedRange() {
        let milliseconds = Int(DockHoverStateMachine.defaultHoverDelay.components.seconds * 1_000)
            + Int(DockHoverStateMachine.defaultHoverDelay.components.attoseconds / 1_000_000_000_000_000)
        XCTAssertEqual(milliseconds, 300)
        XCTAssertTrue(DockHoverStateMachine.hoverDelayRange.contains(milliseconds))
    }
}

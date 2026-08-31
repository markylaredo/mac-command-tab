import CoreGraphics
import XCTest
@testable import MacCommandTab

final class WindowPreviewMatcherTests: XCTestCase {
    func testMatchesOnlyWithinOwningProcess() {
        let target = makeTarget(pid: 10, title: "Document", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates = [
            makeCandidate(id: 1, pid: 11, title: "Document", frame: target.frame),
            makeCandidate(id: 2, pid: 10, title: "Document", frame: target.frame)
        ]
        XCTAssertEqual(WindowPreviewMatcher().match(target: target, candidates: candidates)?.windowID, 2)
    }

    func testUsesFrameToDisambiguateDuplicateTitles() {
        let target = makeTarget(pid: 10, title: "Document", frame: CGRect(x: 500, y: 100, width: 900, height: 700))
        let candidates = [
            makeCandidate(id: 1, pid: 10, title: "Document", frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            makeCandidate(id: 2, pid: 10, title: "Document", frame: target.frame)
        ]
        XCTAssertEqual(WindowPreviewMatcher().match(target: target, candidates: candidates)?.windowID, 2)
    }

    func testUsesFrameForUntitledWindows() {
        let target = makeTarget(pid: 10, title: "Untitled Window", frame: CGRect(x: 40, y: 50, width: 700, height: 500))
        let candidates = [
            makeCandidate(id: 1, pid: 10, title: "", frame: CGRect(x: 800, y: 50, width: 700, height: 500)),
            makeCandidate(id: 2, pid: 10, title: "", frame: target.frame)
        ]
        XCTAssertEqual(WindowPreviewMatcher().match(target: target, candidates: candidates)?.windowID, 2)
    }

    func testReturnsNilWhenNoProcessMatches() {
        let target = makeTarget(pid: 10, title: "Document", frame: .zero)
        XCTAssertNil(WindowPreviewMatcher().match(
            target: target,
            candidates: [makeCandidate(id: 1, pid: 11, title: "Document", frame: .zero)]
        ))
    }

    private func makeTarget(pid: pid_t, title: String, frame: CGRect) -> WindowPreviewTarget {
        WindowPreviewTarget(id: WindowID(rawValue: "test"), pid: pid, title: title, frame: frame)
    }

    private func makeCandidate(id: CGWindowID, pid: pid_t, title: String, frame: CGRect) -> WindowPreviewCandidate {
        WindowPreviewCandidate(windowID: id, pid: pid, title: title, frame: frame)
    }
}

final class LivePreviewPolicyTests: XCTestCase {
    func testRapidOpenCloseReturnsLifecycleToIdle() {
        var lifecycle = LivePreviewSessionLifecycle()
        let sessionID = UUID()

        lifecycle.begin(sessionID: sessionID)
        XCTAssertEqual(lifecycle.state, .starting)
        XCTAssertEqual(lifecycle.invalidate(), sessionID)
        XCTAssertTrue(lifecycle.finishStopping())
        XCTAssertEqual(lifecycle, LivePreviewSessionLifecycle())
    }

    func testOpenCancelOpenRejectsOldSessionCallbacks() {
        var lifecycle = LivePreviewSessionLifecycle()
        let oldSessionID = UUID()
        let newSessionID = UUID()

        lifecycle.begin(sessionID: oldSessionID)
        XCTAssertTrue(lifecycle.activate(sessionID: oldSessionID))
        lifecycle.invalidate()
        lifecycle.begin(sessionID: newSessionID)

        XCTAssertFalse(lifecycle.allowsCapture(sessionID: oldSessionID))
        XCTAssertFalse(lifecycle.finishStopping())
        XCTAssertTrue(lifecycle.activate(sessionID: newSessionID))
        XCTAssertTrue(lifecycle.allowsCapture(sessionID: newSessionID))
    }

    func testDuplicateLifecycleStopIsHarmless() {
        var lifecycle = LivePreviewSessionLifecycle()
        let sessionID = lifecycle.begin()
        XCTAssertTrue(lifecycle.activate(sessionID: sessionID))

        XCTAssertEqual(lifecycle.invalidate(), sessionID)
        XCTAssertNil(lifecycle.invalidate())
        XCTAssertTrue(lifecycle.finishStopping())
        XCTAssertFalse(lifecycle.finishStopping())
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testDelayedSourceStartCannotBecomeActiveAfterInvalidation() {
        var lifecycle = LivePreviewSessionLifecycle()
        let sessionID = lifecycle.begin()
        XCTAssertTrue(lifecycle.activate(sessionID: sessionID))

        lifecycle.invalidate()

        XCTAssertFalse(lifecycle.allowsCapture(sessionID: sessionID))
    }

    func testWindowDisappearanceStopsOnlyItsPreviewSession() {
        let ids = makeIDs(count: 3)
        let desiredIDs = [ids[0], ids[2]]
        let profiles = LivePreviewPolicy().profiles(for: desiredIDs, selectedID: ids[0])
        let plan = LivePreviewReconciliationPlan(
            currentIDs: Set(ids),
            desiredIDs: desiredIDs,
            selectedID: ids[0],
            profiles: profiles
        )

        XCTAssertEqual(plan.retainedIDs, Set(desiredIDs))
        XCTAssertEqual(plan.stoppingIDs, Set([ids[1]]))
        XCTAssertTrue(plan.startingIDs.isEmpty)
    }

    func testSelectionChangeRetainsAllExistingPreviewSessions() {
        let ids = makeIDs(count: 4)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[3])
        let plan = LivePreviewReconciliationPlan(
            currentIDs: Set(ids),
            desiredIDs: ids,
            selectedID: ids[3],
            profiles: profiles
        )

        XCTAssertEqual(plan.retainedIDs, Set(ids))
        XCTAssertTrue(plan.startingIDs.isEmpty)
        XCTAssertTrue(plan.stoppingIDs.isEmpty)
    }

    func testSearchFilteringRetiresHiddenStreamsWithoutInvalidatingCachedIDs() {
        let ids = makeIDs(count: 4)
        let cachedIDs = Set(ids)
        let filteredIDs = [ids[1], ids[3]]
        let profiles = LivePreviewPolicy().profiles(for: filteredIDs, selectedID: ids[1])
        let plan = LivePreviewReconciliationPlan(
            currentIDs: Set(ids),
            desiredIDs: filteredIDs,
            selectedID: ids[1],
            profiles: profiles
        )

        XCTAssertEqual(plan.retainedIDs, Set(filteredIDs))
        XCTAssertEqual(plan.stoppingIDs, Set([ids[0], ids[2]]))
        XCTAssertEqual(cachedIDs, Set(ids), "Stream reconciliation must not evict cached images")
    }

    func testPermissionLossTerminatesActiveLifecycle() {
        var lifecycle = LivePreviewSessionLifecycle()
        let sessionID = lifecycle.begin()
        XCTAssertTrue(lifecycle.activate(sessionID: sessionID))

        lifecycle.invalidate()
        XCTAssertTrue(lifecycle.finishStopping())

        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertNil(lifecycle.currentSessionID)
    }

    func testPanelDismissalTerminatesCommitAndCancelSessions() {
        for _ in 0..<2 {
            var lifecycle = LivePreviewSessionLifecycle()
            let sessionID = lifecycle.begin()
            XCTAssertTrue(lifecycle.activate(sessionID: sessionID))

            lifecycle.invalidate()
            XCTAssertTrue(lifecycle.finishStopping())

            XCTAssertEqual(lifecycle.state, .idle)
            XCTAssertNil(lifecycle.currentSessionID)
        }
    }

    @MainActor
    func testPreviewCoordinatorStartsIdleAndStopIsIdempotent() {
        let snapshotService = WindowSnapshotService()
        let previewService = WindowPreviewService(snapshotService: snapshotService)
        let coordinator = LivePreviewCoordinator(previewService: previewService)

        XCTAssertEqual(
            coordinator.debugSnapshot,
            LivePreviewDebugSnapshot(
                state: .idle,
                sessionID: nil,
                activeStreamCount: 0,
                activeSnapshotTaskCount: 0,
                activeCaptureTaskCount: 0
            )
        )

        coordinator.stopSession()
        coordinator.stopSession()

        XCTAssertEqual(coordinator.debugSnapshot.state, .idle)
        XCTAssertEqual(coordinator.debugSnapshot.activeStreamCount, 0)
        XCTAssertEqual(coordinator.debugSnapshot.activeCaptureTaskCount, 0)
    }

    @MainActor
    func testThumbnailSessionFinishesSnapshotWorkWithoutStartingStreams() async {
        let snapshotService = WindowSnapshotService()
        let previewService = WindowPreviewService(snapshotService: snapshotService)
        let coordinator = LivePreviewCoordinator(previewService: previewService)

        coordinator.beginSession(
            mode: .thumbnail,
            allWindows: [],
            visibleWindows: [],
            selectedID: nil,
            previewSize: CGSize(width: 180, height: 105),
            displayScale: 2
        )
        for _ in 0..<20 where coordinator.debugSnapshot.activeSnapshotTaskCount != 0 {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.debugSnapshot.state, .active)
        XCTAssertEqual(coordinator.debugSnapshot.activeStreamCount, 0)
        XCTAssertEqual(coordinator.debugSnapshot.activeSnapshotTaskCount, 0)
        XCTAssertEqual(coordinator.debugSnapshot.activeCaptureTaskCount, 0)

        coordinator.stopSession()
        for _ in 0..<20 where coordinator.debugSnapshot.state != .idle {
            await Task.yield()
        }
        XCTAssertEqual(coordinator.debugSnapshot.state, .idle)
    }

    func testSmallSwitcherUsesThirtyFPSForSelection() {
        let ids = makeIDs(count: 5)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[1])

        XCTAssertEqual(profiles[ids[1]]?.framesPerSecond, 30)
        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 10)
    }

    func testSelectedWindowReceivesHighestFrameRate() {
        let ids = makeIDs(count: 12)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[4])

        XCTAssertEqual(profiles.count, LivePreviewPolicy().maximumConcurrentStreams)
        XCTAssertEqual(profiles[ids[4]]?.framesPerSecond, 30)
        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 8)
    }

    func testCrowdedSwitcherReducesBackgroundFrameRate() {
        let ids = makeIDs(count: 20)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[0])

        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 24)
        XCTAssertEqual(profiles[ids[1]]?.framesPerSecond, 6)
    }

    func testExtremeCountsAreBoundedAndAlwaysIncludeSelection() {
        let ids = makeIDs(count: 30)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[29])

        XCTAssertEqual(profiles.count, LivePreviewPolicy().maximumConcurrentStreams)
        XCTAssertNotNil(profiles[ids[29]])
        XCTAssertEqual(profiles[ids[29]]?.framesPerSecond, 20)
        XCTAssertNil(profiles[ids[0]])
        XCTAssertEqual(profiles[ids[28]]?.framesPerSecond, 5)
    }

    func testRetinaCaptureIncludesSelectedScaleHeadroom() {
        let previewSize = CGSize(width: 180, height: 105)
        let sourceSize = CGSize(width: 1_600, height: 900)
        let renderedSize = LivePreviewCaptureSizing.renderedContentSize(
            sourceSize: sourceSize,
            previewSize: previewSize
        )
        let pixelSize = LivePreviewCaptureSizing.pixelSize(
            sourceSize: sourceSize,
            previewSize: previewSize,
            backingScaleFactor: 2
        )

        XCTAssertEqual(pixelSize, CGSize(width: 344, height: 194))
        XCTAssertGreaterThan(pixelSize.width, renderedSize.width * 2)
        XCTAssertGreaterThan(pixelSize.height, renderedSize.height * 2)
    }

    func testCaptureDimensionsPreservePortraitAspectRatio() {
        let sourceSize = CGSize(width: 600, height: 900)
        let pixelSize = LivePreviewCaptureSizing.pixelSize(
            sourceSize: sourceSize,
            previewSize: CGSize(width: 180, height: 105),
            backingScaleFactor: 2
        )

        XCTAssertEqual(pixelSize.width / pixelSize.height, 2.0 / 3.0, accuracy: 0.01)
    }

    func testThumbnailCaptureIncludesRetinaSelectionHeadroom() {
        let pixelSize = LivePreviewCaptureSizing.thumbnailMaximumPixelSize(
            previewSize: CGSize(width: 180, height: 105),
            backingScaleFactor: 2
        )

        XCTAssertEqual(pixelSize, CGSize(width: 386, height: 226))
    }

    private func makeIDs(count: Int) -> [WindowID] {
        (0..<count).map { WindowID(rawValue: "live-\($0)") }
    }
}

import AppKit
import ApplicationServices
import XCTest
@testable import MacCommandTab

final class MRUWindowOrderingTests: XCTestCase {
    func testRecentlyFocusedWindowsSortFirst() {
        let windows = [makeWindow("a"), makeWindow("b"), makeWindow("c")]
        var ordering = MRUWindowOrdering()
        ordering.record(WindowID(rawValue: "b"))
        ordering.record(WindowID(rawValue: "c"))
        XCTAssertEqual(ordering.order(windows).map(\.id.rawValue), ["c", "b", "a"])
    }

    func testRecordingExistingWindowMovesItToFront() {
        let windows = [makeWindow("a"), makeWindow("b"), makeWindow("c")]
        var ordering = MRUWindowOrdering()
        ordering.record(WindowID(rawValue: "a"))
        ordering.record(WindowID(rawValue: "b"))
        ordering.record(WindowID(rawValue: "a"))
        XCTAssertEqual(ordering.order(windows).map(\.id.rawValue), ["a", "b", "c"])
    }

    private func makeWindow(_ id: String) -> WindowInfo {
        WindowInfo(
            id: WindowID(rawValue: id),
            pid: 1,
            title: id,
            applicationName: "Test",
            bundleIdentifier: nil,
            icon: nil,
            accessibilityElement: AXUIElementCreateSystemWide(),
            isMinimized: false,
            isFullscreen: false,
            isApplicationHidden: false,
            isFocused: false,
            frame: .zero
        )
    }
}

final class WindowTrackerRefreshGenerationTests: XCTestCase {
    func testStaleRefreshIsIgnoredAfterStop() {
        var lifecycle = WindowTrackerRefreshGeneration()
        lifecycle.start()
        let refresh = lifecycle.scheduleRefresh()

        lifecycle.stop()

        XCTAssertFalse(lifecycle.accepts(refresh))
    }

    func testStaleRefreshIsIgnoredAfterGenerationChanges() {
        var lifecycle = WindowTrackerRefreshGeneration()
        lifecycle.start()
        let staleRefresh = lifecycle.scheduleRefresh()
        _ = lifecycle.scheduleRefresh()

        XCTAssertFalse(lifecycle.accepts(staleRefresh))
    }

    func testLatestRefreshPublishesWhileRunning() {
        var lifecycle = WindowTrackerRefreshGeneration()
        lifecycle.start()
        let refresh = lifecycle.scheduleRefresh()

        XCTAssertTrue(lifecycle.accepts(refresh))
    }
}

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
    func testSmallSwitcherUsesSixtyFPSForSelection() {
        let ids = makeIDs(count: 5)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[1])

        XCTAssertEqual(profiles[ids[1]]?.framesPerSecond, 60)
        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 30)
    }

    func testSelectedWindowReceivesHighestFrameRate() {
        let ids = makeIDs(count: 12)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[4])

        XCTAssertEqual(profiles.count, 12)
        XCTAssertEqual(profiles[ids[4]]?.framesPerSecond, 45)
        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 30)
        XCTAssertGreaterThan(
            profiles[ids[4]]?.resolutionScale ?? 0,
            profiles[ids[0]]?.resolutionScale ?? 0
        )
    }

    func testCrowdedSwitcherReducesBackgroundFrameRate() {
        let ids = makeIDs(count: 20)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[0])

        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 30)
        XCTAssertEqual(profiles[ids[1]]?.framesPerSecond, 15)
    }

    func testExtremeCountsAreBoundedAndAlwaysIncludeSelection() {
        let ids = makeIDs(count: 30)
        let profiles = LivePreviewPolicy().profiles(for: ids, selectedID: ids[29])

        XCTAssertEqual(profiles.count, LivePreviewPolicy().maximumConcurrentStreams)
        XCTAssertNotNil(profiles[ids[29]])
        XCTAssertEqual(profiles[ids[29]]?.framesPerSecond, 30)
        XCTAssertEqual(profiles[ids[0]]?.framesPerSecond, 12)
    }

    private func makeIDs(count: Int) -> [WindowID] {
        (0..<count).map { WindowID(rawValue: "live-\($0)") }
    }
}

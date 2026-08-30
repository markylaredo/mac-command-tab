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

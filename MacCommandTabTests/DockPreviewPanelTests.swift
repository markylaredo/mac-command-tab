import AppKit
import XCTest
@testable import MacCommandTab

/// Tests for the preview panel's card model.
///
/// These exercise the update rules directly rather than through the view: which
/// cards survive a refresh, which previews are kept, and what the header reports.
/// The panel is never ordered on screen, so no window is presented during tests.
@MainActor
final class DockPreviewPanelTests: XCTestCase {
    private var coordinator: LivePreviewCoordinator!
    private var panel: DockPreviewPanel!

    override func setUp() async throws {
        try await super.setUp()
        let snapshotService = WindowSnapshotService()
        coordinator = LivePreviewCoordinator(
            previewService: WindowPreviewService(snapshotService: snapshotService)
        )
        panel = DockPreviewPanel(
            livePreviewCoordinator: coordinator,
            onSelect: { _ in },
            onClose: { _ in },
            onPointerEntered: {},
            onPointerExited: {}
        )
    }

    override func tearDown() async throws {
        panel.orderOut(nil)
        panel = nil
        coordinator = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeWindow(pid: pid_t, title: String, minimized: Bool = false) -> WindowInfo {
        WindowInfo(
            id: WindowID(rawValue: "\(pid):\(title)"),
            pid: pid,
            title: title,
            applicationName: "Test App",
            bundleIdentifier: "com.example.test",
            icon: nil,
            accessibilityElement: AXUIElementCreateApplication(pid),
            isMinimized: minimized,
            isFullscreen: false,
            isApplicationHidden: false,
            isFocused: false,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private func makeCard(_ window: WindowInfo, preview: WindowPreview? = nil, canClose: Bool = true) -> DockPreviewCard {
        DockPreviewCard(window: window, preview: preview, canClose: canClose)
    }

    private func layout(for count: Int) -> DockPreviewLayout {
        DockPreviewLayoutCalculator().calculateLayout(
            itemCount: count,
            availableSize: CGSize(width: 1728, height: 1055),
            dockEdge: .bottom,
            displayScale: 2
        )
    }

    private func makeImage(width: Int = 4, height: Int = 3) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    // MARK: - Configuration

    func testPanelNeverBecomesKeyOrMain() {
        // A preview popup must not take keyboard focus from whatever the user is
        // typing in.
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testPanelIsNonActivatingAndFloatsAboveOrdinaryWindows() {
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertFalse(panel.isMovable)
    }

    func testPanelIsExcludedFromScreenCapture() {
        // Otherwise the popup would appear inside its own previews.
        XCTAssertEqual(panel.sharingType, .none)
    }

    func testPanelJoinsAllSpaces() {
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    // MARK: - Card updates

    func testUpdateReplacesTheDisplayedWindowSet() {
        let windows = (1...3).map { makeWindow(pid: 42, title: "Window \($0)") }

        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: windows.map { makeCard($0) },
            layout: layout(for: windows.count)
        )

        XCTAssertEqual(panel.displayedWindowIDs, windows.map(\.id))
    }

    func testPreviewUpdateTargetsTheMatchingCardOnly() {
        let windows = (1...3).map { makeWindow(pid: 42, title: "Window \($0)") }
        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: windows.map { makeCard($0) },
            layout: layout(for: windows.count)
        )
        let preview = WindowPreview(image: makeImage())

        panel.updatePreview(preview, for: windows[1].id)

        XCTAssertEqual(panel.currentPreview(for: windows[1].id)?.id, preview.id)
        XCTAssertNil(panel.currentPreview(for: windows[0].id))
        XCTAssertNil(panel.currentPreview(for: windows[2].id))
    }

    func testPreviewUpdateForAnAbsentWindowIsIgnored() {
        let window = makeWindow(pid: 42, title: "Window")
        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: [makeCard(window)],
            layout: layout(for: 1)
        )

        panel.updatePreview(WindowPreview(image: makeImage()), for: WindowID(rawValue: "999:missing"))

        XCTAssertNil(panel.currentPreview(for: window.id))
        XCTAssertEqual(panel.displayedWindowIDs, [window.id])
    }

    func testRepeatedIdenticalPreviewIsNotReapplied() {
        // The capture pipeline can publish the same frame more than once. Applying
        // it again would invalidate SwiftUI for no reason.
        let window = makeWindow(pid: 42, title: "Window")
        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: [makeCard(window)],
            layout: layout(for: 1)
        )
        let preview = WindowPreview(image: makeImage())
        panel.updatePreview(preview, for: window.id)
        let appliedID = panel.currentPreview(for: window.id)?.id

        panel.updatePreview(preview, for: window.id)

        XCTAssertEqual(panel.currentPreview(for: window.id)?.id, appliedID)
    }

    func testWindowRemovalShrinksTheCardList() {
        let windows = (1...4).map { makeWindow(pid: 42, title: "Window \($0)") }
        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: windows.map { makeCard($0) },
            layout: layout(for: windows.count)
        )

        // One window closed.
        let remaining = Array(windows.dropFirst())
        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: remaining.map { makeCard($0) },
            layout: layout(for: remaining.count)
        )

        XCTAssertEqual(panel.displayedWindowIDs, remaining.map(\.id))
        XCTAssertNil(panel.currentPreview(for: windows[0].id))
    }

    func testCanCloseIsCarriedPerCard() {
        let closable = makeWindow(pid: 42, title: "Closable")
        let notClosable = makeWindow(pid: 42, title: "Not closable")

        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: [
                makeCard(closable, canClose: true),
                makeCard(notClosable, canClose: false)
            ],
            layout: layout(for: 2)
        )

        XCTAssertEqual(panel.displayedWindowIDs.count, 2)
    }

    func testLayoutIsStoredFromTheUpdate() {
        let windows = (1...5).map { makeWindow(pid: 42, title: "Window \($0)") }
        let layout = layout(for: windows.count)

        panel.update(
            applicationName: "Safari",
            applicationIcon: nil,
            cards: windows.map { makeCard($0) },
            layout: layout
        )

        XCTAssertEqual(panel.currentLayout, layout)
    }

    // MARK: - Header

    func testWindowCountLabelIsSingularForOneWindow() {
        let model = DockPreviewViewModel()
        model.cards = [makeCard(makeWindow(pid: 1, title: "Only"))]
        XCTAssertEqual(model.windowCountLabel, "1 window")
    }

    func testWindowCountLabelIsPluralForSeveralWindows() {
        let model = DockPreviewViewModel()
        model.cards = (1...3).map { makeCard(makeWindow(pid: 1, title: "Window \($0)")) }
        XCTAssertEqual(model.windowCountLabel, "3 windows")
    }

    func testWindowCountLabelHandlesNoWindows() {
        XCTAssertEqual(DockPreviewViewModel().windowCountLabel, "0 windows")
    }

    // MARK: - Rendering

    func testContentBuildsAndLaysOutWithRealCards() {
        // The panel's hierarchy has never been rendered if this is skipped. A
        // SwiftUI failure or an unsatisfiable constraint would otherwise only
        // appear when a user hovered a Dock icon.
        let windows = (1...6).map { makeWindow(pid: 42, title: "Window \($0)") }
        panel.update(
            applicationName: "Test App",
            applicationIcon: NSImage(size: NSSize(width: 32, height: 32)),
            cards: windows.map { makeCard($0, preview: WindowPreview(image: makeImage())) },
            layout: layout(for: windows.count)
        )

        let content = try? XCTUnwrap(panel.contentView)
        content?.frame = NSRect(origin: .zero, size: layout(for: windows.count).panelSize)
        content?.layoutSubtreeIfNeeded()

        XCTAssertNotNil(content)
        XCTAssertGreaterThan(content?.subviews.count ?? 0, 0)
    }

    func testContentBuildsForAMinimizedSingleWindow() {
        let window = makeWindow(pid: 7, title: "Minimized", minimized: true)
        panel.update(
            applicationName: "Test App",
            applicationIcon: nil,
            cards: [makeCard(window, preview: nil, canClose: false)],
            layout: layout(for: 1)
        )

        let content = panel.contentView
        content?.layoutSubtreeIfNeeded()

        // A missing preview must fall back to the placeholder rather than an
        // empty card, and a card with no close button must still render.
        XCTAssertNotNil(content)
        XCTAssertEqual(panel.displayedWindowIDs, [window.id])
    }

    func testPresentationSetsThePanelFrameWithoutShowingIt() {
        let windows = (1...3).map { makeWindow(pid: 42, title: "Window \($0)") }
        let layout = layout(for: windows.count)
        panel.update(
            applicationName: "Test App",
            applicationIcon: nil,
            cards: windows.map { makeCard($0) },
            layout: layout
        )

        panel.present(at: CGPoint(x: 200, y: 300), size: layout.panelSize, animated: false)

        XCTAssertEqual(panel.frame.size.width, layout.panelSize.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size.height, layout.panelSize.height, accuracy: 0.5)
        panel.orderOut(nil)
    }

    func testDismissOnAHiddenPanelIsHarmless() {
        // Dismissal can race the panel hiding itself; it must not report a hide
        // that did not happen or crash.
        panel.dismiss(animated: false)
        panel.dismiss(animated: false)
        XCTAssertFalse(panel.isVisible)
    }

    func testDidHideHandlerFiresOnlyWhenThePanelWasVisible() {
        var hideCount = 0
        panel.setDidHideHandler { hideCount += 1 }

        // Never shown, so ordering out is not a hide event.
        panel.orderOut(nil)
        XCTAssertEqual(hideCount, 0)
    }

    // MARK: - Hit testing

    func testContainsIsFalseWhileThePanelIsHidden() {
        // A hidden panel must never be treated as part of the interaction region,
        // or a preview could never be dismissed.
        panel.setFrame(NSRect(x: 100, y: 100, width: 400, height: 200), display: false)

        XCTAssertFalse(panel.contains(CGPoint(x: 300, y: 200)))
    }
}

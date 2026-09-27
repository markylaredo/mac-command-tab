import XCTest
@testable import MacCommandTab

/// Tests for preview panel sizing and placement.
///
/// Positioning is where a Dock popup most visibly fails: half off-screen, on the
/// wrong display, or covering the icon it belongs to. These cases pin the
/// clamping and edge behaviour down without needing a second monitor.
final class DockPreviewLayoutCalculatorTests: XCTestCase {
    private let calculator = DockPreviewLayoutCalculator()
    private let screen = CGSize(width: 1728, height: 1117)

    private func layout(
        itemCount: Int,
        dockEdge: DockScreenEdge = .bottom,
        availableSize: CGSize? = nil
    ) -> DockPreviewLayout {
        calculator.calculateLayout(
            itemCount: itemCount,
            availableSize: availableSize ?? screen,
            dockEdge: dockEdge,
            displayScale: 2
        )
    }

    func testSizePreferenceChangesCardWidth() {
        let small = calculator.calculateLayout(itemCount: 3, availableSize: screen, dockEdge: .bottom, displayScale: 2, preferredItemWidth: 180)
        let large = calculator.calculateLayout(itemCount: 3, availableSize: screen, dockEdge: .bottom, displayScale: 2, preferredItemWidth: 300)
        XCTAssertEqual(small.previewSize.width, 180)
        XCTAssertEqual(large.previewSize.width, 300)
    }

    func testDenseGroupsShrinkEvenOnLargeDisplays() {
        let few = layout(itemCount: 3)
        let many = layout(itemCount: 10)
        XCTAssertLessThan(many.itemSize.width, few.itemSize.width)
        XCTAssertGreaterThanOrEqual(many.itemSize.width, 132)
    }

    func testNarrowScreensReduceColumnsInsteadOfClippingCards() {
        for edge in [DockScreenEdge.bottom, .left, .right] {
            let result = layout(itemCount: 15, dockEdge: edge, availableSize: CGSize(width: 400, height: 600))
            let contentWidth = result.itemSize.width * CGFloat(result.columns)
                + result.horizontalSpacing * CGFloat(result.columns - 1)
                + result.contentInsets * 2
            XCTAssertLessThanOrEqual(contentWidth, result.panelSize.width + 1)
            XCTAssertTrue(result.requiresScrolling)
        }
    }

    // MARK: - Auto-sizing

    func testSingleWindowUsesOneWideCard() {
        let result = layout(itemCount: 1)

        XCTAssertEqual(result.columns, 1)
        XCTAssertEqual(result.rows, 1)
        XCTAssertGreaterThan(result.itemSize.width, 200)
    }

    func testTwoAndThreeWindowsUseAMatchingSingleRow() {
        for count in 2...3 {
            let result = layout(itemCount: count)
            XCTAssertEqual(result.columns, count, "count \(count)")
            XCTAssertEqual(result.rows, 1, "count \(count)")
        }
    }

    func testFourToFiveWindowsStayInOneRow() {
        for count in 4...5 {
            let result = layout(itemCount: count)
            XCTAssertEqual(result.columns, count, "count \(count)")
            XCTAssertEqual(result.rows, 1, "count \(count)")
        }
    }

    func testManyWindowsWrapAndStopWideningThePanel() {
        let result = layout(itemCount: 20)

        XCTAssertLessThanOrEqual(result.columns, DockPreviewLayoutCalculator.maximumColumns)
        XCTAssertLessThanOrEqual(result.rows, DockPreviewLayoutCalculator.maximumVisibleRows)
        // More windows than fit must be reachable rather than silently dropped.
        XCTAssertTrue(result.requiresScrolling)
    }

    func testCardsNeverDropBelowTheMinimumReadableWidth()  {
        let result = layout(itemCount: 12)
        XCTAssertGreaterThanOrEqual(result.itemSize.width, 100)
    }

    func testPanelNeverExceedsTheUsableArea() {
        for count in [1, 2, 3, 5, 8, 20, 60] {
            let result = layout(itemCount: count)
            XCTAssertLessThanOrEqual(result.panelSize.width, screen.width * 0.92, "count \(count)")
            XCTAssertLessThanOrEqual(result.panelSize.height, screen.height * 0.86, "count \(count)")
        }
    }

    func testSideDockUsesFewerColumns() {
        let bottom = layout(itemCount: 5, dockEdge: .bottom)
        let left = layout(itemCount: 5, dockEdge: .left)
        XCTAssertLessThanOrEqual(left.columns, bottom.columns)
    }

    func testSmallScreenStillProducesAUsablePanel() {
        let result = calculator.calculateLayout(
            itemCount: 6,
            availableSize: CGSize(width: 900, height: 600),
            dockEdge: .bottom,
            displayScale: 2
        )

        XCTAssertGreaterThan(result.panelSize.width, 0)
        XCTAssertGreaterThan(result.panelSize.height, 0)
        XCTAssertLessThanOrEqual(result.panelSize.width, 900 * 0.92 + 0.5)
    }

    func testPanelHeightAlwaysMatchesTheRowsItReserves() {
        // The panel must never allocate height for rows it does not lay out: the
        // content view caps itself to the panel height, so a mismatch would show
        // as dead space or clip a card.
        for count in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20] {
            let result = layout(itemCount: count)
            let expectedContentHeight = result.itemSize.height * CGFloat(result.rows)
                + result.verticalSpacing * CGFloat(max(0, result.rows - 1))
            let expectedPanelHeight = expectedContentHeight
                + result.headerHeight
                + result.contentInsets * 2

            XCTAssertEqual(
                result.panelSize.height,
                expectedPanelHeight,
                accuracy: 0.5,
                "count \(count) rows \(result.rows)"
            )
        }
    }

    func testScrollingIsRequiredExactlyWhenWindowsOrHeightDoNotFit() {
        // `requiresScrolling` has two causes: more windows than the grid has
        // slots, or a panel that would exceed the usable area and so has to be
        // capped. Asserting only the first would be wrong on a small display.
        //
        // The tolerance matters: five cards in one row lands within a fraction of
        // a point of the width budget, so an exact comparison would flip on
        // floating-point noise rather than on behaviour.
        let tolerance: CGFloat = 1
        for count in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 40] {
            let result = layout(itemCount: count)
            let slots = result.columns * result.rows
            let overflowsGrid = slots < count
            let cappedByHeight = result.panelSize.height >= screen.height * 0.86 - tolerance
            let cappedByWidth = result.panelSize.width >= screen.width * 0.92 - tolerance

            XCTAssertEqual(
                result.requiresScrolling,
                overflowsGrid || cappedByHeight || cappedByWidth,
                "count \(count) slots \(slots) panel \(result.panelSize)"
            )
            // Whatever the cause, every window must remain reachable.
            if overflowsGrid {
                XCTAssertTrue(result.requiresScrolling, "count \(count) cannot fit its grid")
            }
        }
    }

    func testAllWindowsAreReachableWhenTheyDoNotFitTheGrid() {
        // A grid that cannot show every card must scroll, or windows would be
        // silently unreachable.
        for count in [11, 12, 20, 40] {
            let result = layout(itemCount: count)
            XCTAssertLessThan(result.columns * result.rows, count, "count \(count)")
            XCTAssertTrue(result.requiresScrolling, "count \(count)")
        }
    }

    func testColumnCountIsExactSoTheGridCannotOverflowHorizontally() {
        // More columns than cards would leave an empty slot and a panel wider than
        // its content.
        for count in 1...12 {
            let result = layout(itemCount: count)
            XCTAssertEqual(result.columns, min(count, DockPreviewLayoutCalculator.maximumColumns), "count \(count)")
        }
    }

    func testMatchingLineHeightsAcrossDockEdges() {
        // The required height is a property of the preview aspect ratio and the
        // caption, so it must not change when the Dock moves to the side. The
        // panel's own size differs only because a side Dock allows fewer columns.
        for count in [1, 2, 3] {
            let bottom = layout(itemCount: count, dockEdge: .bottom)
            let side = layout(itemCount: count, dockEdge: .left)
            XCTAssertEqual(bottom.itemSize.height, side.itemSize.height, accuracy: 0.5, "count \(count)")
            XCTAssertEqual(bottom.previewSize.height, side.previewSize.height, accuracy: 0.5, "count \(count)")
        }
    }

    func testMaximumVisibleRowsIsEnforced() {
        let result = layout(itemCount: 40)
        XCTAssertLessThanOrEqual(result.rows, DockPreviewLayoutCalculator.maximumVisibleRows)
    }

    func testSideDockNeverExceedsItsColumnLimit() {
        for count in [5, 8, 12, 20] {
            let result = layout(itemCount: count, dockEdge: .right)
            XCTAssertLessThanOrEqual(result.columns, 3, "count \(count)")
        }
    }

    func testZeroWindowsProducesAHeaderOnlyPanel() {
        let result = layout(itemCount: 0)
        XCTAssertEqual(result.rows, 0)
        XCTAssertGreaterThan(result.panelSize.height, 0)
    }

    func testLayoutIsDeterministic() {
        XCTAssertEqual(layout(itemCount: 7), layout(itemCount: 7))
    }

    // MARK: - Placement

    private let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1055)

    func testBottomDockPlacesPanelAboveTheIcon() {
        let origin = calculator.panelOrigin(
            panelSize: CGSize(width: 400, height: 200),
            dockFrame: CGRect(x: 800, y: -70, width: 60, height: 60),
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThan(origin.y, -70)
        XCTAssertLessThanOrEqual(origin.y, visibleFrame.maxY)
    }

    func testBottomDockCentresPanelOnTheHoveredIcon() {
        let panelWidth: CGFloat = 400
        let iconFrame = CGRect(x: 800, y: -70, width: 60, height: 60)

        let origin = calculator.panelOrigin(
            panelSize: CGSize(width: panelWidth, height: 200),
            dockFrame: iconFrame,
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x + panelWidth / 2, iconFrame.midX, accuracy: 1)
    }

    func testLeftDockPlacesPanelToTheRightOfTheIcon() {
        let iconFrame = CGRect(x: 0, y: 500, width: 60, height: 60)
        let origin = calculator.panelOrigin(
            panelSize: CGSize(width: 400, height: 200),
            dockFrame: iconFrame,
            dockEdge: .left,
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThan(origin.x, iconFrame.maxX)
    }

    func testRightDockPlacesPanelToTheLeftOfTheIcon() {
        let iconFrame = CGRect(x: visibleFrame.maxX - 60, y: 500, width: 60, height: 60)
        let origin = calculator.panelOrigin(
            panelSize: CGSize(width: 400, height: 200),
            dockFrame: iconFrame,
            dockEdge: .right,
            visibleFrame: visibleFrame
        )

        XCTAssertLessThan(origin.x, iconFrame.minX)
    }

    func testPanelIsClampedLeftWhenAnchoredNearTheLeftEdge() {
        let panelSize = CGSize(width: 500, height: 200)
        let origin = calculator.panelOrigin(
            panelSize: panelSize,
            dockFrame: CGRect(x: 0, y: -70, width: 60, height: 60),
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX)
    }

    func testPanelIsClampedRightWhenAnchoredNearTheRightEdge() {
        let panelSize = CGSize(width: 500, height: 200)
        let origin = calculator.panelOrigin(
            panelSize: panelSize,
            dockFrame: CGRect(x: visibleFrame.maxX - 60, y: -70, width: 60, height: 60),
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        XCTAssertLessThanOrEqual(origin.x + panelSize.width, visibleFrame.maxX)
    }

    func testPanelStaysInsideTheVisibleFrameOnASecondaryDisplay() {
        // A display positioned below and to the right of the primary one, so its
        // origin is not at (0, 0). Clamping must use the display it is on.
        let secondary = CGRect(x: 1728, y: -900, width: 1440, height: 900)
        let panelSize = CGSize(width: 600, height: 260)
        let origin = calculator.panelOrigin(
            panelSize: panelSize,
            dockFrame: CGRect(x: 2000, y: -960, width: 60, height: 60),
            dockEdge: .bottom,
            visibleFrame: secondary
        )

        XCTAssertGreaterThanOrEqual(origin.x, secondary.minX)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, secondary.maxX)
        XCTAssertGreaterThanOrEqual(origin.y, secondary.minY)
        XCTAssertLessThanOrEqual(origin.y + panelSize.height, secondary.maxY)
    }

    func testMissingDockFrameFallsBackToADockEdgeAnchor() {
        let panelSize = CGSize(width: 400, height: 200)
        let origin = calculator.panelOrigin(
            panelSize: panelSize,
            dockFrame: nil,
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX)
        XCTAssertLessThanOrEqual(origin.x + panelSize.width, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
    }

    func testPanelTallerThanTheScreenIsStillClampedInside() {
        let panelSize = CGSize(width: 400, height: 5_000)
        let origin = calculator.panelOrigin(
            panelSize: panelSize,
            dockFrame: CGRect(x: 800, y: -70, width: 60, height: 60),
            dockEdge: .bottom,
            visibleFrame: visibleFrame
        )

        // Clamping cannot fit an oversized panel, but it must not push it
        // further out either.
        XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
    }
}

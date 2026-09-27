import CoreGraphics
import XCTest
@testable import MacCommandTab

final class SwitcherLayoutCalculatorTests: XCTestCase {
    private let calculator = SwitcherLayoutCalculator()
    private let displaySizes = [
        CGSize(width: 1_440, height: 900),
        CGSize(width: 1_728, height: 1_117),
        CGSize(width: 1_920, height: 1_080),
        CGSize(width: 2_560, height: 1_440)
    ]
    private let itemCounts = [1, 2, 3, 5, 10, 15, 20, 30]

    func testEveryAppearanceKeepsEveryItemInsideDisplayBounds() {
        for appearance in SwitcherAppearance.allCases {
            for displaySize in displaySizes {
                for itemCount in itemCounts {
                    let layout = calculator.calculateLayout(
                        itemCount: itemCount,
                        availableSize: displaySize,
                        appearance: appearance
                    )

                    XCTAssertGreaterThanOrEqual(layout.rows * layout.columns, itemCount)
                    XCTAssertGreaterThan(layout.cardSize.width, 0)
                    XCTAssertGreaterThan(layout.cardSize.height, 0)
                    XCTAssertLessThanOrEqual(layout.panelSize.width, displaySize.width * 0.92 + 0.5)
                    XCTAssertLessThanOrEqual(layout.panelSize.height, displaySize.height * 0.78 + 0.5)
                }
            }
        }
    }

    func testFewWindowsProduceLargerCardsThanManyWindows() {
        for appearance in SwitcherAppearance.allCases {
            let small = calculator.calculateLayout(
                itemCount: 2,
                availableSize: CGSize(width: 1_440, height: 900),
                appearance: appearance
            )
            let large = calculator.calculateLayout(
                itemCount: 30,
                availableSize: CGSize(width: 1_440, height: 900),
                appearance: appearance
            )
            XCTAssertGreaterThan(small.cardSize.width, large.cardSize.width)
        }
    }

    func testCompactThumbnailSetUsesOneContentSizedRow() {
        let layout = calculator.calculateLayout(
            itemCount: 5,
            availableSize: CGSize(width: 1_920, height: 1_080),
            appearance: .thumbnails
        )

        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 5)
        XCTAssertLessThan(layout.panelSize.width, 1_920 * 0.75)
    }

    func testSearchDoesNotShiftStableSwitcherChromeOrCardGeometry() {
        let normal = calculator.calculateLayout(
            itemCount: 5,
            availableSize: CGSize(width: 1_920, height: 1_080),
            appearance: .thumbnails
        )
        let searching = calculator.calculateLayout(
            itemCount: 5,
            availableSize: CGSize(width: 1_920, height: 1_080),
            appearance: .thumbnails,
            searchActive: true
        )

        XCTAssertEqual(searching.itemSize, normal.itemSize)
        XCTAssertEqual(searching.panelSize.height, normal.panelSize.height)
    }

    func testEmptyResultsUseCompactPanel() {
        let layout = calculator.calculateLayout(
            itemCount: 0,
            availableSize: CGSize(width: 1_920, height: 1_080),
            appearance: .thumbnails
        )
        XCTAssertEqual(layout.rows, 0)
        XCTAssertLessThanOrEqual(layout.panelSize.height, 180)
    }

    func testThumbnailItemHeightIncludesPreviewSpacingAndMetadata() {
        let layout = calculator.calculateLayout(
            itemCount: 12,
            availableSize: CGSize(width: 1_728, height: 1_117),
            appearance: .thumbnails
        )

        XCTAssertEqual(layout.itemSize.width, layout.previewSize.width)
        XCTAssertEqual(layout.itemSize.height, layout.previewSize.height + 8 + 40)
        XCTAssertEqual(layout.verticalSpacing, 14)
        XCTAssertEqual(
            layout.panelSize.height,
            48 + 34 + 32
                + CGFloat(layout.rows) * layout.itemSize.height
                + CGFloat(layout.rows - 1) * layout.verticalSpacing
        )
        XCTAssertFalse(layout.requiresVerticalScrolling)
    }

    func testNonThumbnailGeometryRemainsSelfContained() {
        for appearance in [SwitcherAppearance.appIcons, .windowTitles] {
            let layout = calculator.calculateLayout(
                itemCount: 12,
                availableSize: CGSize(width: 1_728, height: 1_117),
                appearance: appearance
            )

            XCTAssertEqual(layout.previewSize, layout.itemSize)
            XCTAssertGreaterThan(layout.itemSize.height, 0)
        }
    }

    func testAccessibilityPortraitWindowAspectFitsInsideStablePreviewStage() {
        let stageSize = CGSize(width: 196, height: 118)
        let fittedSize = WindowIdentityLayout.aspectFit(
            sourceSize: CGSize(width: 600, height: 900),
            in: stageSize
        )

        XCTAssertEqual(fittedSize.height, stageSize.height - 14, accuracy: 0.001)
        XCTAssertLessThan(fittedSize.width, stageSize.width)
        XCTAssertLessThanOrEqual(fittedSize.width, stageSize.width - 20)
        XCTAssertLessThanOrEqual(fittedSize.height, stageSize.height - 14)
    }

    func testEightThumbnailWindowsPreferOneFocusRail() {
        let layout = calculator.calculateLayout(
            itemCount: 8,
            availableSize: CGSize(width: 1_440, height: 900),
            appearance: .thumbnails
        )

        XCTAssertEqual(layout.columns, 8)
        XCTAssertEqual(layout.rows, 1)
    }

    func testThumbnailRowsBalanceInsteadOfLeavingSingleOrphan() {
        let layout = calculator.calculateLayout(
            itemCount: 13,
            availableSize: CGSize(width: 1_440, height: 900),
            appearance: .thumbnails
        )
        let finalRowCount = 13 % layout.columns

        XCTAssertNotEqual(finalRowCount, 1)
        XCTAssertGreaterThanOrEqual(finalRowCount, layout.columns - 1)
    }
}

final class WindowSearchTests: XCTestCase {
    private struct Item: Equatable {
        let id: Int
        let app: String
        let title: String
    }

    private let items = [
        Item(id: 1, app: "Visual Studio Code", title: ".gitignore — mac-command-tab"),
        Item(id: 2, app: "Xcode", title: "MacCommandTab — AppDelegate.swift"),
        Item(id: 3, app: "Firefox", title: "ChatGPT — MacCommandTab")
    ]

    func testMatchesApplicationNameAndWindowTitleCaseInsensitively() {
        XCTAssertEqual(search("visual").map(\.id), [1])
        XCTAssertEqual(search("APPDELEGATE").map(\.id), [2])
        XCTAssertEqual(search("mac-command-tab").map(\.id), [1])
        XCTAssertEqual(search("maccommandtab").map(\.id), [2, 3])
    }

    func testNoResultsAndClearQuery() {
        XCTAssertTrue(search("missing").isEmpty)
        XCTAssertEqual(search("   "), items)
    }

    func testRanksExactAndPrefixApplicationMatchesBeforeTitlesAndSubstrings() {
        let ranked = [
            Item(id: 1, app: "Terminal", title: "Safari notes"),
            Item(id: 2, app: "Safari", title: "Documentation"),
            Item(id: 3, app: "Safari Technology Preview", title: "Start"),
            Item(id: 4, app: "Notes", title: "Safari")
        ]

        let results = WindowSearch.filter(
            ranked,
            query: "Safari",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertEqual(results.map(\.id), [2, 3, 4, 1])
    }

    func testBackspaceRemovesOneCharacter() {
        XCTAssertEqual(WindowSearch.deletingLastCharacter(from: "code"), "cod")
        XCTAssertEqual(WindowSearch.deletingLastCharacter(from: ""), "")
    }

    func testSelectionIsPreservedOrResetToFirstMatch() {
        XCTAssertEqual(WindowSearch.selectionIndex(preserving: 2, visibleIDs: [1, 2, 3]), 1)
        XCTAssertEqual(WindowSearch.selectionIndex(preserving: 2, visibleIDs: [1, 3]), 0)
        XCTAssertNil(WindowSearch.selectionIndex(preserving: 2, visibleIDs: []))
    }

    // MARK: - Token-coverage recall

    private let multiTokenItems = [
        Item(id: 1, app: "Firefox", title: "Branch · System One Overview"),
        Item(id: 2, app: "Rider", title: "Omeco.ApiV2 – Rider"),
        Item(id: 3, app: "Rider", title: "Omeco.Backend.Tests – Rider"),
        Item(id: 4, app: "Terminal", title: "markanthony — docker compose up — 120×30"),
        Item(id: 5, app: "Finder", title: "Downloads")
    ]

    func testWidensSingleQueryToTokenCoverageWhenNoLiteralMatchExists() {
        // "OMECO Rider" is not a substring of any field, but one window accounts
        // for both tokens across its application name and title.
        let outcome = WindowSearch.ranked(
            multiTokenItems,
            query: "OMECO Rider",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertTrue(outcome.isWidened)
        XCTAssertEqual(Set(outcome.elements.map(\.id)), [2, 3])
    }

    func testRanksMoreTokenCoverageFirst() {
        let items = [
            Item(id: 1, app: "Terminal", title: "compose up"),
            Item(id: 2, app: "Terminal", title: "docker notes"),
            Item(id: 3, app: "Notes", title: "something else")
        ]

        // Item 1 accounts for "terminal" only. Item 2 accounts for both tokens
        // through its application name and title together. Item 3 accounts for
        // neither and is excluded. More coverage wins.
        let outcome = WindowSearch.ranked(
            items,
            query: "Terminal docker",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertTrue(outcome.isWidened)
        XCTAssertEqual(outcome.elements.map(\.id), [2])
    }

    func testWideningRequiresEveryTokenToBeAccountedFor() {
        let items = [
            Item(id: 1, app: "Editor", title: "docker notes"),
            Item(id: 2, app: "Terminal", title: "ssh staging")
        ]

        // Each window accounts for one of the two tokens and neither accounts
        // for both, so nothing qualifies.
        let outcome = WindowSearch.ranked(
            items,
            query: "Terminal docker",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertTrue(outcome.elements.isEmpty)
        XCTAssertFalse(outcome.isWidened)
    }

    func testWideningPreservesInputOrderForEqualCoverage() {
        let items = [
            Item(id: 1, app: "Rider", title: "Omeco.ApiV2"),
            Item(id: 2, app: "Rider", title: "Omeco.Backend.Tests")
        ]

        let outcome = WindowSearch.ranked(
            items,
            query: "OMECO Rider",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertEqual(outcome.elements.map(\.id), [1, 2])
    }

    func testFullQueryMatchTakesPrecedenceOverWidening() {
        // Both windows cover the query tokens, but only item 1 matches the full
        // query literally. Phase one is authoritative, so item 2 must not appear.
        let items = [
            Item(id: 1, app: "Rider", title: "OMECO Rider"),
            Item(id: 2, app: "Rider", title: "Omeco.Backend.Tests – Rider")
        ]

        let outcome = WindowSearch.ranked(
            items,
            query: "OMECO Rider",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertEqual(outcome.elements.map(\.id), [1])
        XCTAssertFalse(outcome.isWidened)
    }

    func testSingleTokenQueryNeverWidens() {
        // A single-token query that matches nothing stays empty. Widening exists
        // for multi-token queries whose words are split across fields, not to
        // invent results for one word.
        let outcome = WindowSearch.ranked(
            multiTokenItems,
            query: "missing",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertTrue(outcome.elements.isEmpty)
        XCTAssertFalse(outcome.isWidened)
    }

    func testCaseFoldingAppliesToTokenMatching() {
        let outcome = WindowSearch.ranked(
            multiTokenItems,
            query: "OMECO rider",
            applicationName: \Item.app,
            title: \Item.title
        )

        XCTAssertEqual(Set(outcome.elements.map(\.id)), [2, 3])
    }

    private func search(_ query: String) -> [Item] {
        WindowSearch.filter(
            items,
            query: query,
            applicationName: \Item.app,
            title: \Item.title
        )
    }
}

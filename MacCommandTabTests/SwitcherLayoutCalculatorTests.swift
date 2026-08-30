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

    func testEmptyResultsUseCompactPanel() {
        let layout = calculator.calculateLayout(
            itemCount: 0,
            availableSize: CGSize(width: 1_920, height: 1_080),
            appearance: .thumbnails
        )
        XCTAssertEqual(layout.rows, 0)
        XCTAssertLessThanOrEqual(layout.panelSize.height, 100)
    }

    func testThumbnailItemHeightIncludesPreviewSpacingAndMetadata() {
        let layout = calculator.calculateLayout(
            itemCount: 12,
            availableSize: CGSize(width: 1_728, height: 1_117),
            appearance: .thumbnails
        )

        XCTAssertEqual(layout.itemSize.width, layout.previewSize.width)
        XCTAssertEqual(layout.itemSize.height, layout.previewSize.height + 8 + 44)
        XCTAssertEqual(layout.verticalSpacing, 16)
        XCTAssertEqual(
            layout.panelSize.height,
            42 + 20
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

    func testBackspaceRemovesOneCharacter() {
        XCTAssertEqual(WindowSearch.deletingLastCharacter(from: "code"), "cod")
        XCTAssertEqual(WindowSearch.deletingLastCharacter(from: ""), "")
    }

    func testSelectionIsPreservedOrResetToFirstMatch() {
        XCTAssertEqual(WindowSearch.selectionIndex(preserving: 2, visibleIDs: [1, 2, 3]), 1)
        XCTAssertEqual(WindowSearch.selectionIndex(preserving: 2, visibleIDs: [1, 3]), 0)
        XCTAssertNil(WindowSearch.selectionIndex(preserving: 2, visibleIDs: []))
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

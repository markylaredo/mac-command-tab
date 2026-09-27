import XCTest
@testable import MacCommandTab

/// Tests for mapping a pointer onto a Dock tile and a tile onto a running
/// application.
///
/// These run against values, not the live Dock, so they stay meaningful even if
/// the Dock's accessibility hierarchy changes. The rules they pin down — ignore
/// non-application tiles, prefer stable identifiers, never guess — are exactly
/// the rules that keep the feature from activating the wrong application.
final class DockItemResolverTests: XCTestCase {
    private let tileSize = CGSize(width: 48, height: 48)

    private func tile(_ x: CGFloat, title: String?, url: URL? = nil, isApplication: Bool = true) -> DockItem {
        DockItem(
            title: title,
            bundleURL: url,
            frame: CGRect(origin: CGPoint(x: x, y: 0), size: tileSize),
            isApplication: isApplication
        )
    }

    private let safariRecord = DockApplicationRecord(
        processIdentifier: 501,
        bundleIdentifier: "com.apple.Safari",
        bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
        localizedName: "Safari",
        executableURL: URL(fileURLWithPath: "/Applications/Safari.app/Contents/MacOS/Safari")
    )

    // MARK: - Hit testing

    func testItemContainingPointIsReturned() {
        let items = [tile(0, title: "Finder"), tile(48, title: "Safari"), tile(96, title: "Notes")]

        XCTAssertEqual(DockItemResolver.item(at: CGPoint(x: 60, y: 24), in: items)?.title, "Safari")
        XCTAssertEqual(DockItemResolver.item(at: CGPoint(x: 10, y: 10), in: items)?.title, "Finder")
    }

    func testPointOutsideEveryTileReturnsNil() {
        let items = [tile(0, title: "Finder"), tile(48, title: "Safari")]
        XCTAssertNil(DockItemResolver.item(at: CGPoint(x: 400, y: 400), in: items))
    }

    func testNonApplicationTilesAreNeverReturned() {
        // The Trash sits beside the applications. Pointing at it must never
        // resolve to an application.
        let items = [
            tile(0, title: "Safari"),
            tile(48, title: "Trash", isApplication: false)
        ]

        XCTAssertNil(DockItemResolver.item(at: CGPoint(x: 60, y: 24), in: items))
    }

    func testHitTestingToleratesSmallPointerOvershoot() {
        let items = [tile(48, title: "Safari")]
        // One point outside the tile's right edge, within the tolerance.
        XCTAssertEqual(DockItemResolver.item(at: CGPoint(x: 97, y: 24), in: items)?.title, "Safari")
    }

    func testDockRegionIncludesNonApplicationTiles() {
        let items = [
            tile(0, title: "Safari"),
            tile(48, title: "Trash", isApplication: false)
        ]

        // Over the Trash: not an application, but still on the Dock, so a
        // preview must not be dismissed for passing over it.
        XCTAssertTrue(DockItemResolver.isWithinDockRegion(CGPoint(x: 60, y: 24), items: items, dockFrame: nil))
        XCTAssertFalse(DockItemResolver.isWithinDockRegion(CGPoint(x: 400, y: 400), items: items, dockFrame: nil))
    }

    func testDockRegionUsesDockFrameWhenAvailable() {
        let items = [tile(48, title: "Safari")]
        let dockFrame = CGRect(x: 0, y: 0, width: 900, height: 60)

        // The gap between icon groups is inside the Dock but outside every tile.
        XCTAssertTrue(DockItemResolver.isWithinDockRegion(CGPoint(x: 500, y: 30), items: items, dockFrame: dockFrame))
    }

    // MARK: - Application matching

    func testBundleURLIsPreferredOverDisplayName() {
        // Two applications share a display name. The bundle URL disambiguates.
        let decoy = DockApplicationRecord(
            processIdentifier: 999,
            bundleIdentifier: "com.example.Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari Copy.app"),
            localizedName: "Safari",
            executableURL: nil
        )
        let item = tile(0, title: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))

        let resolved = DockItemResolver.application(for: item, among: [decoy, safariRecord])

        XCTAssertEqual(resolved?.processIdentifier, 501)
    }

    func testBundleURLMatchIgnoresSymlinksAndTrailingSlashes() {
        let item = tile(0, title: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app/"))
        XCTAssertEqual(
            DockItemResolver.application(for: item, among: [safariRecord])?.processIdentifier,
            501
        )
    }

    func testDisplayNameMatchIsUsedWhenNoBundleURLIsExposed() {
        let item = tile(0, title: "Safari")
        XCTAssertEqual(
            DockItemResolver.application(for: item, among: [safariRecord])?.processIdentifier,
            501
        )
    }

    func testDisplayNameMatchIsCaseInsensitive() {
        let item = tile(0, title: "safari")
        XCTAssertEqual(
            DockItemResolver.application(for: item, among: [safariRecord])?.processIdentifier,
            501
        )
    }

    func testBundleNameOnDiskMatchesWhenLocalizedNameDiffers() {
        // A localized display name that does not match the bundle on disk.
        let localized = DockApplicationRecord(
            processIdentifier: 700,
            bundleIdentifier: "com.example.localized",
            bundleURL: URL(fileURLWithPath: "/Applications/Notes.app"),
            localizedName: "备忘录",
            executableURL: nil
        )
        let item = tile(0, title: "Notes")

        XCTAssertEqual(
            DockItemResolver.application(for: item, among: [localized])?.processIdentifier,
            700
        )
    }

    func testUnresolvableTileReturnsNil() {
        let item = tile(0, title: "Trash")
        XCTAssertNil(DockItemResolver.application(for: item, among: [safariRecord]))
    }

    func testTileWithNoTitleAndNoURLReturnsNil() {
        let item = tile(0, title: nil)
        XCTAssertNil(DockItemResolver.application(for: item, among: [safariRecord]))
    }

    func testTerminatedApplicationsAreNotMatched() {
        let terminated = DockApplicationRecord(
            processIdentifier: 800,
            bundleIdentifier: "com.apple.Safari",
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            localizedName: "Safari",
            executableURL: nil,
            isTerminated: true
        )
        let item = tile(0, title: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))

        XCTAssertNil(DockItemResolver.application(for: item, among: [terminated]))
    }

    func testNonRegularActivationPolicyIsNotMatched() {
        // Background agents have no Dock tile, so they must never be returned.
        let agent = DockApplicationRecord(
            processIdentifier: 900,
            bundleIdentifier: "com.example.agent",
            bundleURL: URL(fileURLWithPath: "/Applications/Agent.app"),
            localizedName: "Agent",
            executableURL: nil,
            activationPolicyIsRegular: false
        )
        let item = tile(0, title: "Agent")

        XCTAssertNil(DockItemResolver.application(for: item, among: [agent]))
    }

    func testFirstMatchingApplicationWinsWhenNamesCollideWithoutURLs() {
        // With no bundle URL to disambiguate, the earlier entry is chosen rather
        // than an arbitrary one, so behaviour is at least deterministic.
        let first = DockApplicationRecord(
            processIdentifier: 1,
            bundleIdentifier: nil,
            bundleURL: nil,
            localizedName: "Music",
            executableURL: nil
        )
        let second = DockApplicationRecord(
            processIdentifier: 2,
            bundleIdentifier: nil,
            bundleURL: nil,
            localizedName: "Music",
            executableURL: nil
        )
        let item = tile(0, title: "Music")

        XCTAssertEqual(DockItemResolver.application(for: item, among: [first, second])?.processIdentifier, 1)
    }
}

import XCTest
@testable import MacCommandTab

/// Tests for the Dock preview preferences and the availability states shown in
/// the menu bar.
final class DockPreviewPreferenceTests: XCTestCase {
    private var savedThumbnailWidth: Any?
    private var savedFocusOnHover: Any?

    override func setUp() {
        savedThumbnailWidth = UserDefaults.standard.object(forKey: DockPreviewPreference.thumbnailWidthKey)
        savedFocusOnHover = UserDefaults.standard.object(forKey: DockPreviewPreference.focusOnHoverKey)
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.thumbnailWidthKey)
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.focusOnHoverKey)
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.enabledKey)
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.hoverDelayKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedThumbnailWidth, forKey: DockPreviewPreference.thumbnailWidthKey)
        UserDefaults.standard.set(savedFocusOnHover, forKey: DockPreviewPreference.focusOnHoverKey)
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.enabledKey)
        UserDefaults.standard.removeObject(forKey: DockPreviewPreference.hoverDelayKey)
        super.tearDown()
    }

    func testEnabledDefaultsToTrue() {
        XCTAssertTrue(DockPreviewPreference.isEnabled)
    }

    func testEnabledRoundTrips() {
        DockPreviewPreference.save(enabled: false)
        XCTAssertFalse(DockPreviewPreference.isEnabled)
        DockPreviewPreference.save(enabled: true)
        XCTAssertTrue(DockPreviewPreference.isEnabled)
    }

    func testHoverDelayDefaultsToThreeHundredMilliseconds() {
        XCTAssertEqual(
            DockPreviewPreference.hoverDelayMilliseconds,
            DockPreviewPreference.defaultHoverDelayMilliseconds
        )
        XCTAssertEqual(DockPreviewPreference.hoverDelayMilliseconds, 300)
    }

    func testHoverDelayRoundTrips() {
        DockPreviewPreference.save(hoverDelayMilliseconds: 400)
        XCTAssertEqual(DockPreviewPreference.hoverDelayMilliseconds, 400)
    }

    func testStoredHoverDelayIsClampedOnRead() {
        // A value written by an older build, or edited by hand, must not produce
        // an unusable delay.
        UserDefaults.standard.set(10, forKey: DockPreviewPreference.hoverDelayKey)
        XCTAssertEqual(
            DockPreviewPreference.hoverDelayMilliseconds,
            DockHoverStateMachine.hoverDelayRange.lowerBound
        )

        UserDefaults.standard.set(60_000, forKey: DockPreviewPreference.hoverDelayKey)
        XCTAssertEqual(
            DockPreviewPreference.hoverDelayMilliseconds,
            DockHoverStateMachine.hoverDelayRange.upperBound
        )
    }

    func testStoredHoverDelayIsClampedOnWrite() {
        DockPreviewPreference.save(hoverDelayMilliseconds: 5)
        XCTAssertEqual(
            DockPreviewPreference.hoverDelayMilliseconds,
            DockHoverStateMachine.hoverDelayRange.lowerBound
        )
    }

    func testHoverDelayDurationMatchesStoredMilliseconds() {
        DockPreviewPreference.save(hoverDelayMilliseconds: 250)
        XCTAssertEqual(
            DockPreviewPreference.hoverDelay,
            .milliseconds(250)
        )
    }

    func testThumbnailSizeDefaultsAndClamps() {
        XCTAssertEqual(DockPreviewPreference.thumbnailWidth, 240)
        DockPreviewPreference.save(thumbnailWidth: 300)
        XCTAssertEqual(DockPreviewPreference.thumbnailWidth, 300)
        DockPreviewPreference.save(thumbnailWidth: -10)
        XCTAssertEqual(DockPreviewPreference.thumbnailWidth, 160)
        UserDefaults.standard.set(9000, forKey: DockPreviewPreference.thumbnailWidthKey)
        XCTAssertEqual(DockPreviewPreference.thumbnailWidth, 320)
    }

    func testHoverFocusDefaultsOnAndPersistsDisabledChoice() {
        XCTAssertTrue(DockPreviewPreference.focusOnHover)
        DockPreviewPreference.save(focusOnHover: false)
        XCTAssertFalse(DockPreviewPreference.focusOnHover)
    }

    func testAvailabilityMenuTitlesAreDistinct() {
        let titles = [
            DockPreviewAvailability.ready.menuTitle,
            DockPreviewAvailability.disabled.menuTitle,
            DockPreviewAvailability.needsAccessibilityPermission.menuTitle
        ]
        XCTAssertEqual(Set(titles).count, titles.count)
        for title in titles {
            XCTAssertTrue(title.hasPrefix("Dock Previews:"), title)
        }
    }

    func testAvailabilityEquality() {
        XCTAssertEqual(DockPreviewAvailability.ready, .ready)
        XCTAssertNotEqual(DockPreviewAvailability.ready, .disabled)
        XCTAssertNotEqual(DockPreviewAvailability.disabled, .needsAccessibilityPermission)
    }
}

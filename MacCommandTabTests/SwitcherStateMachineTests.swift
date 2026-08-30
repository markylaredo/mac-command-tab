import XCTest
@testable import MacCommandTab

final class SwitcherStateMachineTests: XCTestCase {
    func testInitialOptionTabSelectsNextWindow() {
        var machine = SwitcherStateMachine()
        XCTAssertEqual(machine.handle(.optionTab(reverse: false), itemCount: 4), .opened(selection: 1))
    }

    func testRepeatedTabAdvancesSelection() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: false), itemCount: 4)
        XCTAssertEqual(machine.handle(.tab(reverse: false), itemCount: 4), .selectionChanged(2))
    }

    func testShiftTabMovesBackward() {
        var machine = SwitcherStateMachine()
        XCTAssertEqual(machine.handle(.optionTab(reverse: true), itemCount: 4), .opened(selection: 3))
        XCTAssertEqual(machine.handle(.tab(reverse: true), itemCount: 4), .selectionChanged(2))
    }

    func testNavigationWrapsInBothDirections() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: true), itemCount: 3)
        XCTAssertEqual(machine.handle(.moveNext, itemCount: 3), .selectionChanged(0))
        XCTAssertEqual(machine.handle(.movePrevious, itemCount: 3), .selectionChanged(2))
    }

    func testTileGridSupportsSpatialArrowNavigation() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: false), itemCount: 9)

        XCTAssertEqual(
            machine.handle(.moveNext, itemCount: 9, navigationLayout: .tileGrid),
            .selectionChanged(2)
        )
        XCTAssertEqual(
            machine.handle(.moveDown, itemCount: 9, navigationLayout: .tileGrid),
            .selectionChanged(7)
        )
        XCTAssertEqual(
            machine.handle(.movePrevious, itemCount: 9, navigationLayout: .tileGrid),
            .selectionChanged(6)
        )
        XCTAssertEqual(
            machine.handle(.moveUp, itemCount: 9, navigationLayout: .tileGrid),
            .selectionChanged(1)
        )
    }

    func testTileGridDoesNotCrossRowBoundaries() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: true), itemCount: 5)

        XCTAssertNil(machine.handle(.moveNext, itemCount: 5, navigationLayout: .tileGrid))
        XCTAssertNil(machine.handle(.moveDown, itemCount: 5, navigationLayout: .tileGrid))
    }

    func testEscapeCancelsWithoutCommit() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: false), itemCount: 3)
        XCTAssertEqual(machine.handle(.escape, itemCount: 3), .cancelled)
        XCTAssertFalse(machine.isActive)
    }

    func testOptionReleaseCommitsSelection() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.optionTab(reverse: false), itemCount: 3)
        XCTAssertEqual(machine.handle(.optionReleased, itemCount: 3), .committed(selection: 1))
        XCTAssertFalse(machine.isActive)
    }

    func testInvalidEventOrderDoesNothing() {
        var machine = SwitcherStateMachine()
        XCTAssertNil(machine.handle(.tab(reverse: false), itemCount: 3))
        XCTAssertNil(machine.handle(.optionReleased, itemCount: 3))
        XCTAssertNil(machine.handle(.escape, itemCount: 3))
        XCTAssertNil(machine.handle(.optionTab(reverse: false), itemCount: 0))
        XCTAssertFalse(machine.isActive)
    }
}

final class SwitcherAppearancePreferenceTests: XCTestCase {
    func testSelectionEffectPersists() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: SwitcherSelectionEffect.defaultsKey)
        defer { restore(previousValue, forKey: SwitcherSelectionEffect.defaultsKey) }

        SwitcherSelectionEffect.emberBurn.save()

        XCTAssertEqual(SwitcherSelectionEffect.saved, .emberBurn)
    }

    func testGlassDefaultsToEnabledAndPersistsDisabledChoice() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: SwitcherGlassPreference.defaultsKey)
        defer { restore(previousValue, forKey: SwitcherGlassPreference.defaultsKey) }

        defaults.removeObject(forKey: SwitcherGlassPreference.defaultsKey)
        XCTAssertTrue(SwitcherGlassPreference.saved)

        SwitcherGlassPreference.save(false)
        XCTAssertFalse(SwitcherGlassPreference.saved)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

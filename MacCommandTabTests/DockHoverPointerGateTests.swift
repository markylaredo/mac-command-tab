import XCTest
@testable import MacCommandTab

/// Tests for the pointer gate that decides which mouse samples the Dock hover
/// feature acts on.
///
/// The critical property is the trailing edge: the sample that leaves the Dock
/// and panel is the one that begins a dismissal. If it were throttled away as
/// uninteresting, a preview would stay on screen until the pointer happened to
/// re-enter the zone.
final class DockHoverPointerGateTests: XCTestCase {
    private let interval: CFTimeInterval = 1.0 / 30.0

    private func makeGate() -> DockHoverPointerGate {
        DockHoverPointerGate(minimumInterval: interval)
    }

    // MARK: - Inside the zone

    func testFirstSampleInsideTheZoneIsReported() {
        var gate = makeGate()
        // A pointer that starts on the Dock must not be held back by the throttle.
        XCTAssertTrue(gate.shouldReport(isInsideZone: true, at: 0))
    }

    func testSamplesInsideTheZoneAreThrottled()  {
        var gate = makeGate()
        XCTAssertTrue(gate.shouldReport(isInsideZone: true, at: 0))

        // Well inside the minimum interval.
        XCTAssertFalse(gate.shouldReport(isInsideZone: true, at: interval / 4))
        XCTAssertFalse(gate.shouldReport(isInsideZone: true, at: interval / 2))
        XCTAssertFalse(gate.shouldReport(isInsideZone: true, at: interval * 0.99))

        // At or past the interval, movement is reported again.
        XCTAssertTrue(gate.shouldReport(isInsideZone: true, at: interval))
    }

    func testSustainedMovementInsideTheZoneIsCappedNearTheSampleRate() {
        var gate = makeGate()
        var reported = 0
        // One second of movement at 120 Hz, the rate a trackpad can emit.
        let inputSamples = 121
        for step in 0..<inputSamples {
            let time = Double(step) / 120.0
            if gate.shouldReport(isInsideZone: true, at: time) { reported += 1 }
        }

        // The point is that the input rate does not become the work rate. The
        // exact count varies by a sample or two because 1/30 is not representable
        // in binary, so the accumulated step occasionally falls just short of the
        // interval. Asserting an exact number would encode that noise.
        XCTAssertLessThan(reported, inputSamples / 3, "the throttle must cut the input rate substantially")
        XCTAssertGreaterThan(reported, 15, "the throttle must not starve the interaction")
        XCTAssertLessThanOrEqual(Double(reported), 1.0 / interval + 2)
    }

    // MARK: - Outside the zone

    func testSamplesOutsideTheZoneBeforeAnyEntryAreDropped() {
        var gate = makeGate()
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 0))
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 1))
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 2))
    }

    func testRepeatedSamplesOutsideTheZoneAreDropped() {
        var gate = makeGate()
        _ = gate.shouldReport(isInsideZone: true, at: 0)
        _ = gate.shouldReport(isInsideZone: false, at: 1)

        // The exit was delivered; nothing further should be.
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 2))
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 100))
    }

    // MARK: - The trailing edge

    func testLeavingTheZoneIsAlwaysReportedExactlyOnce()  {
        var gate = makeGate()
        _ = gate.shouldReport(isInsideZone: true, at: 0)

        XCTAssertTrue(gate.shouldReport(isInsideZone: false, at: 0.001), "the exit must be delivered")

        // Even immediately afterwards, and regardless of timing.
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: 0.002))
        XCTAssertFalse(gate.shouldReport(isInsideZone: false, at: interval * 10))
    }

    func testLeavingTheZoneIsNotSuppressedByTheThrottle() {
        var gate = makeGate()
        // Enter and immediately leave, well inside the throttle window.
        _ = gate.shouldReport(isInsideZone: true, at: 0)

        XCTAssertTrue(
            gate.shouldReport(isInsideZone: false, at: 0.0001),
            "a departure immediately after entry must still be reported"
        )
    }

    func testReentryAfterLeavingIsReportedWithoutWaitingForTheThrottle() {
        var gate = makeGate()
        _ = gate.shouldReport(isInsideZone: true, at: 0)
        _ = gate.shouldReport(isInsideZone: false, at: 0.001)

        // Straight back in. The throttle must not swallow the first new entry.
        XCTAssertTrue(gate.shouldReport(isInsideZone: true, at: 0.002))
    }

    func testAlternatingEntryAndExitReportsEveryTransition() {
        var gate = makeGate()
        var transitions = 0
        var isInside = false
        for step in 0..<10 {
            isInside.toggle()
            if gate.shouldReport(isInsideZone: isInside, at: Double(step) * 0.001) {
                transitions += 1
            }
        }
        XCTAssertEqual(transitions, 10, "every zone transition must be delivered")
    }

    // MARK: - State

    func testTrackingFlagFollowsTheZoneState() {
        var gate = makeGate()
        XCTAssertFalse(gate.isTrackingInsideZone)

        _ = gate.shouldReport(isInsideZone: true, at: 0)
        XCTAssertTrue(gate.isTrackingInsideZone)

        _ = gate.shouldReport(isInsideZone: false, at: 1)
        XCTAssertFalse(gate.isTrackingInsideZone)
    }

    func testResetReturnsToTheInitialState() {
        var gate = makeGate()
        _ = gate.shouldReport(isInsideZone: true, at: 0)
        _ = gate.shouldReport(isInsideZone: false, at: 1)
        gate.reset()

        XCTAssertFalse(gate.isTrackingInsideZone)
        // After a reset the first sample inside the zone is reported again.
        XCTAssertTrue(gate.shouldReport(isInsideZone: true, at: 2))
    }

    func testDefaultIntervalMatchesThirtySamplesPerSecond() {
        let gate = DockHoverPointerGate()
        XCTAssertEqual(gate.minimumInterval, 1.0 / 30.0, accuracy: 0.0001)
    }
}

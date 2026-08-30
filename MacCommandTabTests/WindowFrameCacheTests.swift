import CoreGraphics
import XCTest
@testable import MacCommandTab

final class WindowFrameCacheTests: XCTestCase {
    @MainActor
    func testDevelopmentPreviewCanCreateSampleSnapshot() {
        XCTAssertNotNil(EffectPreviewSnapshotFactory.makeSnapshot())
    }

    func testUniformLayoutMatchesMetalStruct() {
        XCTAssertEqual(MemoryLayout<EffectUniforms>.stride, 32)
    }

    func testEffectDurationsStayWithinPhaseOneTargets() {
        XCTAssertTrue((0.35...0.45).contains(WindowEffect.tv.defaultDuration))
        XCTAssertTrue((0.20...0.30).contains(WindowEffect.glide.defaultDuration))
        XCTAssertGreaterThan(WindowEffect.pixelate.defaultDuration, 0)
    }

    func testCacheEvictsLeastRecentlyUsedSnapshot() throws {
        var cache = WindowFrameCache(capacity: 2)
        let first = try snapshot(id: "first")
        let second = try snapshot(id: "second")
        let third = try snapshot(id: "third")

        cache.insert(first)
        cache.insert(second)
        XCTAssertNotNil(cache.snapshot(for: first.windowID))
        cache.insert(third)

        XCTAssertNotNil(cache.snapshot(for: first.windowID))
        XCTAssertNil(cache.snapshot(for: second.windowID))
        XCTAssertNotNil(cache.snapshot(for: third.windowID))
        XCTAssertEqual(cache.count, 2)
    }

    func testReplacingSnapshotDoesNotConsumeAnotherSlot() throws {
        var cache = WindowFrameCache(capacity: 2)
        let original = try snapshot(id: "same")
        let replacement = WindowSnapshot(windowID: original.windowID, image: original.image, seed: 0.75)

        cache.insert(original)
        cache.insert(replacement)

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.snapshot(for: original.windowID)?.seed, 0.75)
    }

    private func snapshot(id: String) throws -> WindowSnapshot {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw SnapshotTestError.imageCreationFailed
        }
        return WindowSnapshot(windowID: WindowID(rawValue: id), image: image)
    }
}

private enum SnapshotTestError: Error {
    case imageCreationFailed
}

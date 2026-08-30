import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowPreview: @unchecked Sendable {
    let image: CGImage
}

struct WindowCaptureSource: @unchecked Sendable {
    let window: SCWindow
}

actor WindowPreviewService {
    private let snapshotService: WindowSnapshotService

    init(snapshotService: WindowSnapshotService) {
        self.snapshotService = snapshotService
    }

    func prepareSession(for windows: [WindowInfo]) async {
        await snapshotService.prepare(for: windows)
    }

    func captureWindows(for windows: [WindowInfo]) async -> [WindowID: WindowCaptureSource] {
        await snapshotService.captureWindows(for: windows)
    }

    func capturePreviews(for windows: [WindowInfo]) async -> [WindowID: WindowPreview] {
        let snapshots = await snapshotService.captureSnapshots(
            for: windows,
            maximumPixelSize: CGSize(width: 560, height: 350)
        )
        return snapshots.mapValues { WindowPreview(image: $0.image) }
    }

    func cachedPreviews(for windows: [WindowInfo]) async -> [WindowID: WindowPreview] {
        let snapshots = await snapshotService.cachedSnapshots(for: windows)
        return snapshots.mapValues { WindowPreview(image: $0.image) }
    }

    func clear() async {
        await snapshotService.clear()
    }
}

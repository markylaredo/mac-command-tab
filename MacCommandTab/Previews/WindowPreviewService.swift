import CoreGraphics
import Foundation

struct WindowPreview: @unchecked Sendable {
    let image: CGImage
}

actor WindowPreviewService {
    private let snapshotService: WindowSnapshotService

    init(snapshotService: WindowSnapshotService) {
        self.snapshotService = snapshotService
    }

    func prepareSession(for windows: [WindowInfo]) async {
        await snapshotService.prepare(for: windows)
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

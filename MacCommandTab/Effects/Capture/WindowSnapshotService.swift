@preconcurrency import ScreenCaptureKit
import CoreGraphics
import Foundation

actor WindowSnapshotService {
    private let matcher = WindowPreviewMatcher()
    private var frameCache: WindowFrameCache
    private var captureWindows: [WindowID: SCWindow] = [:]

    init(cacheCapacity: Int = 12) {
        frameCache = WindowFrameCache(capacity: cacheCapacity)
    }

    func prepare(for windows: [WindowInfo]) async {
        captureWindows.removeAll(keepingCapacity: true)
        guard ScreenCapturePermission.isGranted else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let candidates = content.windows.compactMap { window -> WindowPreviewCandidate? in
                guard let application = window.owningApplication else { return nil }
                return WindowPreviewCandidate(
                    windowID: window.windowID,
                    pid: application.processID,
                    title: window.title ?? "",
                    frame: window.frame
                )
            }
            let windowsByID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

            for window in windows {
                guard let candidate = matcher.match(
                    target: WindowPreviewTarget(window: window),
                    candidates: candidates
                ), let captureWindow = windowsByID[candidate.windowID] else { continue }
                captureWindows[window.id] = captureWindow
            }
        } catch {
            captureWindows.removeAll(keepingCapacity: true)
        }
    }

    func captureSnapshots(
        for windows: [WindowInfo],
        maximumPixelSize: CGSize
    ) async -> [WindowID: WindowSnapshot] {
        guard ScreenCapturePermission.isGranted else {
            return frameCache.snapshots(for: Set(windows.map(\.id)))
        }

        for window in windows {
            guard !Task.isCancelled else { break }
            if let snapshot = await captureSnapshot(for: window, maximumPixelSize: maximumPixelSize) {
                frameCache.insert(snapshot)
            }
        }
        return frameCache.snapshots(for: Set(windows.map(\.id)))
    }

    func captureSnapshot(
        for window: WindowInfo,
        maximumPixelSize: CGSize = CGSize(width: 1_920, height: 1_200)
    ) async -> WindowSnapshot? {
        guard ScreenCapturePermission.isGranted else { return frameCache.snapshot(for: window.id) }
        if captureWindows[window.id] == nil {
            await prepare(for: [window])
        }
        guard let captureWindow = captureWindows[window.id] else {
            return frameCache.snapshot(for: window.id)
        }

        let configuration = SCStreamConfiguration()
        let pixelSize = Self.scaledPixelSize(for: captureWindow.frame.size, maximum: maximumPixelSize)
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: captureWindow),
                configuration: configuration
            )
            let snapshot = WindowSnapshot(windowID: window.id, image: image)
            frameCache.insert(snapshot)
            return snapshot
        } catch {
            return frameCache.snapshot(for: window.id)
        }
    }

    func cachedSnapshot(for windowID: WindowID) -> WindowSnapshot? {
        frameCache.snapshot(for: windowID)
    }

    func cachedSnapshots(for windows: [WindowInfo]) -> [WindowID: WindowSnapshot] {
        frameCache.snapshots(for: Set(windows.map(\.id)))
    }

    func clear() {
        captureWindows.removeAll(keepingCapacity: false)
        frameCache.removeAll()
    }

    private static func scaledPixelSize(for source: CGSize, maximum: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(maximum.width / source.width, maximum.height / source.height, 2)
        return CGSize(
            width: max(1, (source.width * scale).rounded()),
            height: max(1, (source.height * scale).rounded())
        )
    }
}

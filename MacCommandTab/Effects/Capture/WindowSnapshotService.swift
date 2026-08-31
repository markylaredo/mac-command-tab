@preconcurrency import ScreenCaptureKit
import CoreGraphics
import Foundation

actor WindowSnapshotService {
    private let matcher = WindowPreviewMatcher()
    private var frameCache: WindowFrameCache
    private var captureWindows: [WindowID: SCWindow] = [:]

    init(cacheCapacity: Int = 32) {
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
                ), let captureWindow = windowsByID[candidate.windowID] else {
                    LivePreviewDiagnostics.log("preview source unavailable id=\(window.id.rawValue)")
                    continue
                }
                captureWindows[window.id] = captureWindow
                LivePreviewDiagnostics.log("preview source created id=\(window.id.rawValue)")
            }
        } catch {
            LivePreviewDiagnostics.log("preview source resolution failed error=\(error.localizedDescription)")
            captureWindows.removeAll(keepingCapacity: true)
        }
    }

    func captureSnapshots(
        for windows: [WindowInfo],
        maximumPixelSize: CGSize
    ) async -> [WindowID: WindowSnapshot] {
        let startedAt = Date()
        let requestedIDs = Set(windows.map(\.id))
        let cacheHits = frameCache.snapshots(for: requestedIDs).count
        guard ScreenCapturePermission.isGranted else {
            let cached = frameCache.snapshots(for: requestedIDs)
            logCaptureMetrics(
                windowCount: windows.count,
                cacheHits: cached.count,
                duration: Date().timeIntervalSince(startedAt)
            )
            return cached
        }

        await prepare(for: windows)
        for window in windows {
            guard !Task.isCancelled else { break }
            guard let captureWindow = captureWindows[window.id] else { continue }
            if let snapshot = await captureSnapshot(
                for: window,
                captureWindow: captureWindow,
                maximumPixelSize: maximumPixelSize
            ) {
                frameCache.insert(snapshot)
            }
        }
        let snapshots = frameCache.snapshots(for: requestedIDs)
        logCaptureMetrics(
            windowCount: windows.count,
            cacheHits: cacheHits,
            duration: Date().timeIntervalSince(startedAt)
        )
        return snapshots
    }

    func captureWindows(for windows: [WindowInfo]) async -> [WindowID: WindowCaptureSource] {
        await prepare(for: windows)
        let requestedIDs = Set(windows.map(\.id))
        return captureWindows
            .filter { requestedIDs.contains($0.key) }
            .mapValues { WindowCaptureSource(window: $0) }
    }

    func captureSnapshot(
        for window: WindowInfo,
        maximumPixelSize: CGSize = CGSize(width: 1_920, height: 1_200)
    ) async -> WindowSnapshot? {
        guard ScreenCapturePermission.isGranted else { return frameCache.snapshot(for: window.id) }
        if captureWindows[window.id] == nil {
            await prepare(for: [window])
        }
        guard let captureWindow = captureWindows[window.id] else { return frameCache.snapshot(for: window.id) }
        return await captureSnapshot(
            for: window,
            captureWindow: captureWindow,
            maximumPixelSize: maximumPixelSize
        )
    }

    private func captureSnapshot(
        for window: WindowInfo,
        captureWindow: SCWindow,
        maximumPixelSize: CGSize
    ) async -> WindowSnapshot? {
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

    private func logCaptureMetrics(windowCount: Int, cacheHits: Int, duration: TimeInterval) {
        let formattedDuration = String(format: "%.0f", duration * 1_000)
        LivePreviewDiagnostics.log(
            "thumbnail capture windows=\(windowCount) duration=\(formattedDuration)ms "
                + "cacheHits=\(cacheHits) cacheMisses=\(max(0, windowCount - cacheHits))"
        )
    }
}

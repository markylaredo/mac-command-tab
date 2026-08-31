import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowPreview: @unchecked Sendable {
    let id: UUID
    let image: CGImage

    init(id: UUID = UUID(), image: CGImage) {
        self.id = id
        self.image = image
    }
}

struct WindowCaptureSource: @unchecked Sendable {
    let window: SCWindow
}

enum LivePreviewSessionState: String, Sendable {
    case idle
    case starting
    case active
    case stopping
}

struct LivePreviewSessionLifecycle: Equatable, Sendable {
    private(set) var state = LivePreviewSessionState.idle
    private(set) var currentSessionID: UUID?

    @discardableResult
    mutating func begin(sessionID: UUID = UUID()) -> UUID {
        currentSessionID = sessionID
        state = .starting
        return sessionID
    }

    @discardableResult
    mutating func activate(sessionID: UUID) -> Bool {
        guard state == .starting, currentSessionID == sessionID else { return false }
        state = .active
        return true
    }

    func allowsCapture(sessionID: UUID) -> Bool {
        state == .active && currentSessionID == sessionID
    }

    @discardableResult
    mutating func invalidate() -> UUID? {
        guard state != .idle else { return nil }
        let endingSessionID = currentSessionID
        currentSessionID = nil
        state = .stopping
        return endingSessionID
    }

    @discardableResult
    mutating func finishStopping() -> Bool {
        guard state == .stopping, currentSessionID == nil else { return false }
        state = .idle
        return true
    }
}

struct LivePreviewProfile: Equatable, Sendable {
    let framesPerSecond: Int
}

enum LivePreviewCaptureSizing {
    static let maximumSelectionScale: CGFloat = 1.07
    private static let stageInsets = CGSize(width: 20, height: 14)
    private static let maximumPixelSize = CGSize(width: 1_024, height: 640)

    static func renderedContentSize(sourceSize: CGSize, previewSize: CGSize) -> CGSize {
        let available = CGSize(
            width: max(1, previewSize.width - stageInsets.width),
            height: max(1, previewSize.height - stageInsets.height)
        )
        guard sourceSize.width > 0, sourceSize.height > 0 else { return available }

        let sourceAspectRatio = sourceSize.width / sourceSize.height
        if available.width / available.height > sourceAspectRatio {
            return CGSize(width: available.height * sourceAspectRatio, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / sourceAspectRatio)
    }

    static func pixelSize(
        sourceSize: CGSize,
        previewSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGSize {
        let renderedSize = renderedContentSize(sourceSize: sourceSize, previewSize: previewSize)
        let physicalScale = max(1, backingScaleFactor) * maximumSelectionScale
        let requestedSize = CGSize(
            width: renderedSize.width * physicalScale,
            height: renderedSize.height * physicalScale
        )
        let limitingScale = min(
            1,
            maximumPixelSize.width / requestedSize.width,
            maximumPixelSize.height / requestedSize.height
        )
        return CGSize(
            width: evenPixelDimension(requestedSize.width * limitingScale),
            height: evenPixelDimension(requestedSize.height * limitingScale)
        )
    }

    static func thumbnailMaximumPixelSize(
        previewSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGSize {
        let physicalScale = max(1, backingScaleFactor) * maximumSelectionScale
        return CGSize(
            width: evenPixelDimension(previewSize.width * physicalScale),
            height: evenPixelDimension(previewSize.height * physicalScale)
        )
    }

    private static func evenPixelDimension(_ value: CGFloat) -> CGFloat {
        max(2, ceil(value / 2) * 2)
    }
}

struct LivePreviewPolicy: Sendable {
    let maximumConcurrentStreams = 8

    func profiles(for windowIDs: [WindowID], selectedID: WindowID?) -> [WindowID: LivePreviewProfile] {
        guard !windowIDs.isEmpty else { return [:] }

        let activeIDs = prioritizedWindowIDs(windowIDs, selectedID: selectedID)

        let count = windowIDs.count
        return Dictionary(uniqueKeysWithValues: activeIDs.map { id in
            let selected = id == selectedID
            let profile: LivePreviewProfile
            switch count {
            case ...6:
                profile = LivePreviewProfile(framesPerSecond: selected ? 30 : 10)
            case 7...12:
                profile = LivePreviewProfile(framesPerSecond: selected ? 30 : 8)
            case 13...20:
                profile = LivePreviewProfile(framesPerSecond: selected ? 24 : 6)
            default:
                profile = LivePreviewProfile(framesPerSecond: selected ? 20 : 5)
            }
            return (id, profile)
        })
    }

    private func prioritizedWindowIDs(_ windowIDs: [WindowID], selectedID: WindowID?) -> [WindowID] {
        guard windowIDs.count > maximumConcurrentStreams else { return windowIDs }
        guard let selectedID, let selectedIndex = windowIDs.firstIndex(of: selectedID) else {
            return Array(windowIDs.prefix(maximumConcurrentStreams))
        }

        var prioritized = [selectedID]
        var distance = 1
        while prioritized.count < maximumConcurrentStreams {
            let previous = selectedIndex - distance
            let next = selectedIndex + distance
            if previous >= 0 { prioritized.append(windowIDs[previous]) }
            if prioritized.count < maximumConcurrentStreams, next < windowIDs.count {
                prioritized.append(windowIDs[next])
            }
            distance += 1
        }
        return prioritized
    }
}

struct LivePreviewReconciliationPlan: Equatable, Sendable {
    let retainedIDs: Set<WindowID>
    let startingIDs: [WindowID]
    let stoppingIDs: Set<WindowID>

    init(
        currentIDs: Set<WindowID>,
        desiredIDs: [WindowID],
        selectedID: WindowID?,
        profiles: [WindowID: LivePreviewProfile]
    ) {
        let requiredIDs = Set(profiles.keys)
        retainedIDs = currentIDs.intersection(requiredIDs)
        stoppingIDs = currentIDs.subtracting(requiredIDs)

        let orderedRequiredIDs = desiredIDs.filter { requiredIDs.contains($0) }
        let prioritizedIDs: [WindowID]
        if let selectedID, requiredIDs.contains(selectedID) {
            prioritizedIDs = [selectedID] + orderedRequiredIDs.filter { $0 != selectedID }
        } else {
            prioritizedIDs = orderedRequiredIDs
        }
        startingIDs = prioritizedIDs.filter { !currentIDs.contains($0) }
    }
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

    func capturePreviews(
        for windows: [WindowInfo],
        previewSize: CGSize,
        displayScale: CGFloat
    ) async -> [WindowID: WindowPreview] {
        let snapshots = await snapshotService.captureSnapshots(
            for: windows,
            maximumPixelSize: LivePreviewCaptureSizing.thumbnailMaximumPixelSize(
                previewSize: previewSize,
                backingScaleFactor: displayScale
            )
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

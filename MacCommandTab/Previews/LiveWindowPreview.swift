import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import SwiftUI

private final class WeakDisplayLayer: @unchecked Sendable {
    weak var value: AVSampleBufferDisplayLayer?

    init(_ value: AVSampleBufferDisplayLayer) {
        self.value = value
    }
}

struct LivePreviewProfile: Equatable, Sendable {
    let framesPerSecond: Int
    let resolutionScale: CGFloat
}

struct LivePreviewPolicy: Sendable {
    let maximumConcurrentStreams = 20

    func profiles(for windowIDs: [WindowID], selectedID: WindowID?) -> [WindowID: LivePreviewProfile] {
        guard !windowIDs.isEmpty else { return [:] }

        var activeIDs = Array(windowIDs.prefix(maximumConcurrentStreams))
        if let selectedID, windowIDs.contains(selectedID), !activeIDs.contains(selectedID) {
            activeIDs[activeIDs.count - 1] = selectedID
        }

        let count = windowIDs.count
        return Dictionary(uniqueKeysWithValues: activeIDs.map { id in
            let selected = id == selectedID
            let profile: LivePreviewProfile
            switch count {
            case ...6:
                profile = LivePreviewProfile(
                    framesPerSecond: selected ? 60 : 30,
                    resolutionScale: selected ? 2.0 : 1.5
                )
            case 7...12:
                profile = LivePreviewProfile(
                    framesPerSecond: selected ? 45 : 30,
                    resolutionScale: selected ? 2.0 : 1.35
                )
            case 13...20:
                profile = LivePreviewProfile(
                    framesPerSecond: selected ? 30 : 15,
                    resolutionScale: selected ? 1.75 : 1.0
                )
            default:
                profile = LivePreviewProfile(
                    framesPerSecond: selected ? 30 : 12,
                    resolutionScale: selected ? 1.5 : 0.9
                )
            }
            return (id, profile)
        })
    }
}

@MainActor
final class LivePreviewCoordinator {
    private let previewService: WindowPreviewService
    private let policy = LivePreviewPolicy()
    private var sessions: [WindowID: LivePreviewSession] = [:]
    private var captureWindows: [WindowID: WindowCaptureSource] = [:]
    private var attachedLayers: [WindowID: WeakDisplayLayer] = [:]
    private var desiredWindows: [WindowInfo] = []
    private var selectedID: WindowID?
    private var previewSize = CGSize(width: 320, height: 180)
    private var displayScale: CGFloat = 2
    private var generation = 0
    private var isSessionActive = false

    init(previewService: WindowPreviewService) {
        self.previewService = previewService
    }

    func beginSession(
        allWindows: [WindowInfo],
        visibleWindows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        stopAll()
        generation += 1
        let currentGeneration = generation
        isSessionActive = true
        desiredWindows = visibleWindows
        self.selectedID = selectedID
        self.previewSize = previewSize
        self.displayScale = displayScale

        Task { [weak self, previewService] in
            let resolved = await previewService.captureWindows(for: allWindows)
            guard let self,
                  self.isSessionActive,
                  self.generation == currentGeneration else { return }
            self.captureWindows = resolved
            self.reconcileSessions()
        }
    }

    func updateVisibleWindows(
        _ windows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        guard isSessionActive else { return }
        desiredWindows = windows
        self.selectedID = selectedID
        self.previewSize = previewSize
        self.displayScale = displayScale
        reconcileSessions()
    }

    func updateSelection(_ selectedID: WindowID?) {
        guard isSessionActive else { return }
        self.selectedID = selectedID
        reconcileSessions()
    }

    func attach(_ layer: AVSampleBufferDisplayLayer, to windowID: WindowID) {
        if attachedLayers[windowID]?.value === layer { return }
        attachedLayers[windowID] = WeakDisplayLayer(layer)
        sessions[windowID]?.attach(layer)
    }

    func detach(_ layer: AVSampleBufferDisplayLayer, from windowID: WindowID) {
        guard attachedLayers[windowID]?.value === layer else { return }
        attachedLayers.removeValue(forKey: windowID)
        sessions[windowID]?.detach(layer)
    }

    func stopAll() {
        generation += 1
        isSessionActive = false
        captureWindows.removeAll(keepingCapacity: false)
        desiredWindows = []
        selectedID = nil
        let sessionsToStop = Array(sessions.values)
        sessions.removeAll(keepingCapacity: false)
        for session in sessionsToStop {
            session.detachCurrentLayer()
            Task { await session.stop() }
        }
    }

    private func reconcileSessions() {
        guard isSessionActive else { return }
        let eligibleWindows = desiredWindows.filter { !$0.isMinimized && captureWindows[$0.id] != nil }
        let orderedIDs = eligibleWindows.map(\.id)
        let profiles = policy.profiles(for: orderedIDs, selectedID: selectedID)
        let requiredIDs = Set(profiles.keys)

        for id in sessions.keys where !requiredIDs.contains(id) {
            guard let session = sessions.removeValue(forKey: id) else { continue }
            session.detachCurrentLayer()
            Task { await session.stop() }
        }

        let prioritizedIDs = orderedIDs.sorted { lhs, rhs in
            if lhs == selectedID { return true }
            if rhs == selectedID { return false }
            return orderedIDs.firstIndex(of: lhs) ?? 0 < orderedIDs.firstIndex(of: rhs) ?? 0
        }
        for id in prioritizedIDs {
            guard let profile = profiles[id], let captureWindow = captureWindows[id] else { continue }
            if let existing = sessions[id] {
                existing.update(profile: profile, previewSize: previewSize, displayScale: displayScale)
                continue
            }

            let sessionIdentity = UUID()
            let session = LivePreviewSession(
                identity: sessionIdentity,
                windowID: id,
                captureWindow: captureWindow.window,
                profile: profile,
                previewSize: previewSize,
                displayScale: displayScale
            ) { [weak self] failedID, failedIdentity in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.sessions[failedID]?.identity == failedIdentity else { return }
                    self.sessions.removeValue(forKey: failedID)
                }
            }
            sessions[id] = session
            if let layer = attachedLayers[id]?.value { session.attach(layer) }
            Task {
                do {
                    try await session.start()
                } catch {
                    await MainActor.run { [weak self] in
                        guard let self, self.sessions[id] === session else { return }
                        self.sessions.removeValue(forKey: id)
                    }
                }
            }
        }
    }
}

private final class LivePreviewSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct ConfigurationKey: Equatable {
        let width: Int
        let height: Int
        let framesPerSecond: Int
    }

    let identity: UUID
    let windowID: WindowID
    private var stream: SCStream!
    private let outputQueue: DispatchQueue
    private let onFailure: @Sendable (WindowID, UUID) -> Void
    private let stateLock = NSLock()
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var hasPresentedFrame = false
    private var configurationKey: ConfigurationKey
    private var isStopping = false

    init(
        identity: UUID,
        windowID: WindowID,
        captureWindow: SCWindow,
        profile: LivePreviewProfile,
        previewSize: CGSize,
        displayScale: CGFloat,
        onFailure: @escaping @Sendable (WindowID, UUID) -> Void
    ) {
        self.identity = identity
        self.windowID = windowID
        self.onFailure = onFailure
        outputQueue = DispatchQueue(label: "com.maccommandtab.live-preview.\(windowID.rawValue)", qos: .userInteractive)
        let configuration = Self.configuration(
            profile: profile,
            previewSize: previewSize,
            displayScale: displayScale
        )
        configurationKey = Self.key(for: configuration, framesPerSecond: profile.framesPerSecond)
        stream = nil
        super.init()
        stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: captureWindow),
            configuration: configuration,
            delegate: self
        )
    }

    func start() async throws {
        guard !stateLock.withLock({ isStopping }) else { throw CancellationError() }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        guard !stateLock.withLock({ isStopping }) else {
            try? stream.removeStreamOutput(self, type: .screen)
            throw CancellationError()
        }
        try await stream.startCapture()
        if stateLock.withLock({ isStopping }) {
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    func stop() async {
        stateLock.withLock { isStopping = true }
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
    }

    func attach(_ layer: AVSampleBufferDisplayLayer) {
        let retainsLastFrame = layer.status == .rendering
        if layer.status == .failed { layer.flushAndRemoveImage() }
        layer.opacity = retainsLastFrame ? 1 : 0
        let layerReference = WeakDisplayLayer(layer)
        outputQueue.async { [weak self, layerReference] in
            guard let self else { return }
            self.stateLock.withLock {
                self.displayLayer = layerReference.value
                self.hasPresentedFrame = retainsLastFrame
            }
        }
    }

    func detach(_ layer: AVSampleBufferDisplayLayer) {
        let layerReference = WeakDisplayLayer(layer)
        outputQueue.async { [weak self, layerReference] in
            guard let self else { return }
            self.stateLock.withLock {
                guard self.displayLayer === layerReference.value else { return }
                self.displayLayer = nil
                self.hasPresentedFrame = false
            }
        }
    }

    func detachCurrentLayer() {
        outputQueue.async { [weak self] in
            self?.stateLock.withLock {
                self?.displayLayer = nil
                self?.hasPresentedFrame = false
            }
        }
    }

    func update(profile: LivePreviewProfile, previewSize: CGSize, displayScale: CGFloat) {
        let configuration = Self.configuration(
            profile: profile,
            previewSize: previewSize,
            displayScale: displayScale
        )
        let newKey = Self.key(for: configuration, framesPerSecond: profile.framesPerSecond)
        let shouldUpdate = stateLock.withLock { () -> Bool in
            guard configurationKey != newKey else { return false }
            configurationKey = newKey
            return true
        }
        guard shouldUpdate else { return }
        Task { try? await stream.updateConfiguration(configuration) }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              sampleBuffer.imageBuffer != nil,
              Self.isCompleteFrame(sampleBuffer) else { return }

        let target = stateLock.withLock { displayLayer }
        guard let target else { return }
        if target.status == .failed { target.flush() }
        guard target.isReadyForMoreMediaData else { return }
        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        )
        target.enqueue(sampleBuffer)

        let isFirstFrame = stateLock.withLock { () -> Bool in
            guard !hasPresentedFrame else { return false }
            hasPresentedFrame = true
            return true
        }
        if isFirstFrame {
            let layerReference = WeakDisplayLayer(target)
            DispatchQueue.main.async { [layerReference] in
                guard let target = layerReference.value else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.10)
                target.opacity = 1
                CATransaction.commit()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onFailure(windowID, identity)
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let rawStatus = attachments.first?[.status] as? Int,
        let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }

    private static func configuration(
        profile: LivePreviewProfile,
        previewSize: CGSize,
        displayScale: CGFloat
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let requestedScale = max(0.75, min(2, profile.resolutionScale * max(1, displayScale) / 2))
        let maximum = profile.framesPerSecond >= 30
            ? CGSize(width: 960, height: 600)
            : CGSize(width: 640, height: 400)
        let width = max(160, min(maximum.width, previewSize.width * requestedScale))
        let height = max(100, min(maximum.height, previewSize.height * requestedScale))
        configuration.width = Int(width.rounded(.up))
        configuration.height = Int(height.rounded(.up))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(profile.framesPerSecond))
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    private static func key(
        for configuration: SCStreamConfiguration,
        framesPerSecond: Int
    ) -> ConfigurationKey {
        ConfigurationKey(
            width: configuration.width,
            height: configuration.height,
            framesPerSecond: framesPerSecond
        )
    }
}

final class LivePreviewNSView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()
    weak var previewCoordinator: LivePreviewCoordinator?
    var windowID: WindowID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 8
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.opacity = 0
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }
}

struct LiveWindowPreviewView: NSViewRepresentable {
    let windowID: WindowID
    let coordinator: LivePreviewCoordinator

    func makeNSView(context: Context) -> LivePreviewNSView {
        let view = LivePreviewNSView(frame: .zero)
        view.previewCoordinator = coordinator
        view.windowID = windowID
        coordinator.attach(view.displayLayer, to: windowID)
        return view
    }

    func updateNSView(_ nsView: LivePreviewNSView, context: Context) {
        if let previousID = nsView.windowID, previousID != windowID {
            nsView.previewCoordinator?.detach(nsView.displayLayer, from: previousID)
        }
        nsView.previewCoordinator = coordinator
        nsView.windowID = windowID
        coordinator.attach(nsView.displayLayer, to: windowID)
    }

    static func dismantleNSView(_ nsView: LivePreviewNSView, coordinator context: ()) {
        if let windowID = nsView.windowID {
            nsView.previewCoordinator?.detach(nsView.displayLayer, from: windowID)
        }
        nsView.displayLayer.flushAndRemoveImage()
    }
}

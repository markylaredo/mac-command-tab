import AppKit
import AVFoundation
import CoreMedia
import CoreImage
import OSLog
import ScreenCaptureKit
import SwiftUI

enum LivePreviewDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.maccommandtab.app",
        category: "PreviewSession"
    )

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        logger.debug("[PreviewSession] \(message(), privacy: .public)")
        #endif
    }

    static func fault(_ message: @autoclosure () -> String) {
        #if DEBUG
        logger.fault("[PreviewSession] \(message(), privacy: .public)")
        #endif
    }
}

struct LivePreviewDebugSnapshot: Equatable, Sendable {
    let state: LivePreviewSessionState
    let sessionID: UUID?
    let activeStreamCount: Int
    let activeSnapshotTaskCount: Int
    let activeCaptureTaskCount: Int
}

private final class PreviewFrameImageRenderer: @unchecked Sendable {
    let context = CIContext(options: [.cacheIntermediates: false])
}

private final class WeakDisplayLayer: @unchecked Sendable {
    weak var value: AVSampleBufferDisplayLayer?

    init(_ value: AVSampleBufferDisplayLayer) {
        self.value = value
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
    private var lifecycle = LivePreviewSessionLifecycle()
    private var activeMode: PreviewMode?
    private var snapshotTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var streamStartTasks: [UUID: Task<Void, Never>] = [:]
    private var sessionStopTasks: [UUID: Task<Void, Never>] = [:]
    private var teardownTask: Task<Void, Never>?
    private var currentTeardownID: UUID?
    private var activeStreamIdentities: Set<UUID> = []
    private let frameRenderer = PreviewFrameImageRenderer()
    var onPreviewUpdated: ((WindowID, WindowPreview) -> Void)?

    var state: LivePreviewSessionState { lifecycle.state }
    private var currentSessionID: UUID? { lifecycle.currentSessionID }

    init(previewService: WindowPreviewService) {
        self.previewService = previewService
    }

    func beginSession(
        mode: PreviewMode,
        allWindows: [WindowInfo],
        visibleWindows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        switch mode {
        case .live:
            beginLiveSession(
                allWindows: allWindows,
                visibleWindows: visibleWindows,
                selectedID: selectedID,
                previewSize: previewSize,
                displayScale: displayScale
            )
        case .thumbnail:
            beginThumbnailSession(
                visibleWindows: visibleWindows,
                selectedID: selectedID,
                previewSize: previewSize,
                displayScale: displayScale
            )
        }
    }

    private func beginLiveSession(
        allWindows: [WindowInfo],
        visibleWindows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        stopSession()
        let precedingTeardown = teardownTask
        let sessionID = lifecycle.begin()
        activeMode = .live
        desiredWindows = visibleWindows
        self.selectedID = selectedID
        self.previewSize = previewSize
        self.displayScale = displayScale

        LivePreviewDiagnostics.log("START id=\(Self.shortID(sessionID))")
        discoveryTask = Task { @MainActor [weak self, previewService] in
            if let precedingTeardown { await precedingTeardown.value }
            guard !Task.isCancelled else { return }
            let resolved = await previewService.captureWindows(for: allWindows)
            guard let self,
                  !Task.isCancelled,
                  self.lifecycle.state == .starting,
                  self.lifecycle.activate(sessionID: sessionID) else { return }
            self.discoveryTask = nil
            self.captureWindows = resolved
            self.reconcileSessions(for: sessionID)
        }
    }

    private func beginThumbnailSession(
        visibleWindows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        stopSession()
        let precedingTeardown = teardownTask
        let sessionID = lifecycle.begin()
        activeMode = .thumbnail
        desiredWindows = visibleWindows
        self.selectedID = selectedID
        self.previewSize = previewSize
        self.displayScale = displayScale

        LivePreviewDiagnostics.log("START thumbnail id=\(Self.shortID(sessionID))")
        guard lifecycle.activate(sessionID: sessionID) else { return }
        snapshotTask = Task { @MainActor [weak self, previewService] in
            let cachedPreviews = await previewService.cachedPreviews(for: visibleWindows)
            guard let self,
                  !Task.isCancelled,
                  self.lifecycle.allowsCapture(sessionID: sessionID) else { return }
            self.publish(cachedPreviews, sessionID: sessionID)

            if let precedingTeardown { await precedingTeardown.value }
            guard !Task.isCancelled,
                  self.lifecycle.allowsCapture(sessionID: sessionID) else { return }
            let freshPreviews = await previewService.capturePreviews(
                for: visibleWindows,
                previewSize: previewSize,
                displayScale: displayScale
            )
            guard !Task.isCancelled,
                  self.lifecycle.allowsCapture(sessionID: sessionID) else { return }
            self.publish(freshPreviews, sessionID: sessionID)
            self.snapshotTask = nil
            LivePreviewDiagnostics.log(
                "thumbnail refresh complete id=\(Self.shortID(sessionID)) snapshots=\(freshPreviews.count)"
            )
            self.logAccounting()
        }
    }

    func updateVisibleWindows(
        _ windows: [WindowInfo],
        selectedID: WindowID?,
        previewSize: CGSize,
        displayScale: CGFloat
    ) {
        guard activeMode == .live, state == .starting || state == .active else { return }
        desiredWindows = windows
        self.selectedID = selectedID
        self.previewSize = previewSize
        self.displayScale = displayScale
        guard let currentSessionID else { return }
        reconcileSessions(for: currentSessionID)
    }

    func updateSelection(_ selectedID: WindowID?) {
        guard activeMode == .live, state == .starting || state == .active else { return }
        self.selectedID = selectedID
        guard let currentSessionID else { return }
        reconcileSessions(for: currentSessionID)
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

    func stopSession() {
        let hasWork = state != .idle
            || snapshotTask != nil
            || discoveryTask != nil
            || !sessions.isEmpty
            || !streamStartTasks.isEmpty
            || !sessionStopTasks.isEmpty
            || !activeStreamIdentities.isEmpty
        guard hasWork else { return }
        if state == .stopping,
           snapshotTask == nil,
           sessions.isEmpty,
           streamStartTasks.isEmpty,
           sessionStopTasks.isEmpty { return }

        let endingSessionID = lifecycle.invalidate()
        LivePreviewDiagnostics.log("STOP requested id=\(Self.shortID(endingSessionID))")

        let snapshotTaskToStop = snapshotTask
        snapshotTaskToStop?.cancel()
        snapshotTask = nil
        let discoveryTaskToStop = discoveryTask
        discoveryTaskToStop?.cancel()
        discoveryTask = nil
        let startTasksToStop = Array(streamStartTasks.values)
        startTasksToStop.forEach { $0.cancel() }
        streamStartTasks.removeAll(keepingCapacity: false)
        let retirementTasksToFinish = Array(sessionStopTasks.values)
        sessionStopTasks.removeAll(keepingCapacity: false)
        let precedingTeardown = teardownTask
        let teardownID = UUID()
        currentTeardownID = teardownID
        captureWindows.removeAll(keepingCapacity: false)
        activeMode = nil
        desiredWindows = []
        selectedID = nil
        let sessionsToStop = Array(sessions.values)
        sessions.removeAll(keepingCapacity: false)
        sessionsToStop.forEach { session in
            session.detachCurrentLayer()
            session.requestStop()
        }

        LivePreviewDiagnostics.log(
            "cancelling tasks snapshots=\(snapshotTaskToStop == nil ? 0 : 1) "
                + "starts=\(startTasksToStop.count) discovery=\(discoveryTaskToStop == nil ? 0 : 1)"
        )
        let teardown = Task { @MainActor [weak self] in
            if let precedingTeardown { await precedingTeardown.value }

            await withTaskGroup(of: Void.self) { group in
                for session in sessionsToStop {
                    group.addTask { await session.stop() }
                }
            }
            for task in startTasksToStop { await task.value }
            for task in retirementTasksToFinish { await task.value }
            if let snapshotTaskToStop { await snapshotTaskToStop.value }
            if let discoveryTaskToStop { await discoveryTaskToStop.value }

            guard let self else { return }
            for session in sessionsToStop {
                self.activeStreamIdentities.remove(session.identity)
            }
            LivePreviewDiagnostics.log("END id=\(Self.shortID(endingSessionID))")
            self.logAccounting()
            if self.lifecycle.state == .stopping,
               self.currentTeardownID == teardownID {
                _ = self.lifecycle.finishStopping()
                self.teardownTask = nil
                self.currentTeardownID = nil
                self.logAccounting()
            }
        }
        teardownTask = teardown
    }

    func verifyIdleAfterPanelClosed() {
        #if DEBUG
        let pendingTeardown = teardownTask
        Task { @MainActor [weak self] in
            if let pendingTeardown { await pendingTeardown.value }
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.currentSessionID == nil else { return }
            let snapshot = self.debugSnapshot
            guard snapshot.state == .idle,
                  snapshot.activeStreamCount == 0,
                  snapshot.activeSnapshotTaskCount == 0,
                  snapshot.activeCaptureTaskCount == 0 else {
                LivePreviewDiagnostics.fault(
                    "BUG panel closed state=\(snapshot.state.rawValue) "
                        + "activeStreams=\(snapshot.activeStreamCount) "
                        + "activeSnapshots=\(snapshot.activeSnapshotTaskCount) "
                        + "activeTasks=\(snapshot.activeCaptureTaskCount)"
                )
                return
            }
            LivePreviewDiagnostics.log("idle invariant passed activeStreams=0 activeTasks=0")
        }
        #endif
    }

    var debugSnapshot: LivePreviewDebugSnapshot {
        LivePreviewDebugSnapshot(
            state: state,
            sessionID: currentSessionID,
            activeStreamCount: activeStreamIdentities.count,
            activeSnapshotTaskCount: snapshotTask == nil ? 0 : 1,
            activeCaptureTaskCount: (snapshotTask == nil ? 0 : 1)
                + (discoveryTask == nil ? 0 : 1)
                + streamStartTasks.count
                + sessionStopTasks.count
        )
    }

    private func reconcileSessions(for sessionID: UUID) {
        guard lifecycle.allowsCapture(sessionID: sessionID) else { return }
        let eligibleWindows = desiredWindows.filter { !$0.isMinimized && captureWindows[$0.id] != nil }
        let orderedIDs = eligibleWindows.map(\.id)
        let profiles = policy.profiles(for: orderedIDs, selectedID: selectedID)
        let plan = LivePreviewReconciliationPlan(
            currentIDs: Set(sessions.keys),
            desiredIDs: orderedIDs,
            selectedID: selectedID,
            profiles: profiles
        )

        for id in plan.stoppingIDs {
            guard let session = sessions.removeValue(forKey: id) else { continue }
            retire(session, windowID: id)
        }

        for id in plan.retainedIDs {
            guard let profile = profiles[id], let existing = sessions[id] else { continue }
            existing.update(profile: profile, previewSize: previewSize, displayScale: displayScale)
        }

        for id in plan.startingIDs {
            guard let profile = profiles[id], let captureWindow = captureWindows[id] else { continue }
            createSession(
                windowID: id,
                captureWindow: captureWindow,
                profile: profile,
                sessionID: sessionID
            )
        }
    }

    private func publish(_ previews: [WindowID: WindowPreview], sessionID: UUID) {
        guard lifecycle.allowsCapture(sessionID: sessionID) else { return }
        for (windowID, preview) in previews {
            onPreviewUpdated?(windowID, preview)
        }
    }

    private func createSession(
        windowID: WindowID,
        captureWindow: WindowCaptureSource,
        profile: LivePreviewProfile,
        sessionID: UUID
    ) {
        guard lifecycle.allowsCapture(sessionID: sessionID), sessions[windowID] == nil else { return }
        let sessionIdentity = UUID()
        let session = LivePreviewSession(
                identity: sessionIdentity,
                windowID: windowID,
                captureWindow: captureWindow.window,
                profile: profile,
                previewSize: previewSize,
                displayScale: displayScale,
                frameRenderer: frameRenderer,
                onValidFrame: { [weak self] frameID, image in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.lifecycle.allowsCapture(sessionID: sessionID),
                              self.sessions[frameID]?.identity == sessionIdentity else { return }
                        self.onPreviewUpdated?(frameID, WindowPreview(image: image))
                    }
                }
            ) { [weak self] failedID, failedIdentity in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.sessions[failedID]?.identity == failedIdentity else { return }
                    guard let failedSession = self.sessions.removeValue(forKey: failedID) else { return }
                    self.retire(failedSession, windowID: failedID)
                }
            }
        sessions[windowID] = session
        if let layer = attachedLayers[windowID]?.value { session.attach(layer) }
        let startTask = Task { @MainActor [weak self] in
            do {
                try await session.start()
                guard let self else {
                    await session.stop()
                    return
                }
                self.activeStreamIdentities.insert(sessionIdentity)
                LivePreviewDiagnostics.log("stream start window=\(windowID.rawValue)")
                guard self.lifecycle.allowsCapture(sessionID: sessionID),
                      self.sessions[windowID] === session else {
                    await session.stop()
                    self.activeStreamIdentities.remove(sessionIdentity)
                    LivePreviewDiagnostics.log("stream stop window=\(windowID.rawValue)")
                    return
                }
            } catch {
                await session.stop()
                if let self {
                    self.activeStreamIdentities.remove(sessionIdentity)
                    if self.sessions[windowID] === session {
                        self.sessions.removeValue(forKey: windowID)
                    }
                }
            }
            if let self,
               self.streamStartTasks[sessionIdentity] != nil {
                self.streamStartTasks.removeValue(forKey: sessionIdentity)
            }
        }
        streamStartTasks[sessionIdentity] = startTask
    }

    private func logAccounting() {
        let snapshot = debugSnapshot
        LivePreviewDiagnostics.log(
            "state=\(snapshot.state.rawValue) id=\(Self.shortID(snapshot.sessionID)) "
                + "activeStreams=\(snapshot.activeStreamCount) "
                + "activeSnapshots=\(snapshot.activeSnapshotTaskCount) "
                + "activeTasks=\(snapshot.activeCaptureTaskCount)"
        )
    }

    private func retire(_ session: LivePreviewSession, windowID: WindowID) {
        let identity = session.identity
        guard sessionStopTasks[identity] == nil else { return }
        let startTask = streamStartTasks.removeValue(forKey: identity)
        startTask?.cancel()
        session.detachCurrentLayer()
        session.requestStop()
        let stopTask = Task { @MainActor [weak self] in
            await session.stop()
            if let startTask { await startTask.value }
            await session.stop()
            guard let self else { return }
            self.activeStreamIdentities.remove(identity)
            self.sessionStopTasks.removeValue(forKey: identity)
            LivePreviewDiagnostics.log("stream stop window=\(windowID.rawValue)")
        }
        sessionStopTasks[identity] = stopTask
    }

    private static func shortID(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "none"
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
    private var stream: SCStream?
    private let outputQueue: DispatchQueue
    private let onFailure: @Sendable (WindowID, UUID) -> Void
    private let frameRenderer: PreviewFrameImageRenderer
    private let onValidFrame: @Sendable (WindowID, CGImage) -> Void
    private let sourceSize: CGSize
    private let stateLock = NSLock()
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var hasPresentedFrame = false
    private var configurationKey: ConfigurationKey
    private var isStopping = false
    private var lastCachedFrameTime: CFTimeInterval = 0
    private var configurationUpdateTask: Task<Void, Never>?
    private var frameCount = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastDiagnosticTime: CFTimeInterval = 0

    init(
        identity: UUID,
        windowID: WindowID,
        captureWindow: SCWindow,
        profile: LivePreviewProfile,
        previewSize: CGSize,
        displayScale: CGFloat,
        frameRenderer: PreviewFrameImageRenderer,
        onValidFrame: @escaping @Sendable (WindowID, CGImage) -> Void,
        onFailure: @escaping @Sendable (WindowID, UUID) -> Void
    ) {
        self.identity = identity
        self.windowID = windowID
        self.onFailure = onFailure
        self.frameRenderer = frameRenderer
        self.onValidFrame = onValidFrame
        sourceSize = captureWindow.frame.size
        outputQueue = DispatchQueue(label: "com.maccommandtab.live-preview.\(windowID.rawValue)", qos: .userInteractive)
        let configuration = Self.configuration(
            profile: profile,
            previewSize: previewSize,
            displayScale: displayScale,
            sourceSize: captureWindow.frame.size
        )
        configurationKey = Self.key(for: configuration, framesPerSecond: profile.framesPerSecond)
        stream = nil
        super.init()
        stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: captureWindow),
            configuration: configuration,
            delegate: self
        )
        let renderedSize = LivePreviewCaptureSizing.renderedContentSize(
            sourceSize: captureWindow.frame.size,
            previewSize: previewSize
        )
        let formattedScale = String(format: "%.2f", displayScale)
        LivePreviewDiagnostics.log(
            "configuration id=\(windowID.rawValue) render=\(Self.dimensions(renderedSize))pt "
                + "scale=\(formattedScale) "
                + "capture=\(configuration.width)x\(configuration.height)px"
        )
    }

    func start() async throws {
        guard !stateLock.withLock({ isStopping }) else { throw CancellationError() }
        guard !Task.isCancelled,
              let stream = stateLock.withLock({ isStopping ? nil : stream }) else {
            throw CancellationError()
        }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        guard !Task.isCancelled, !stateLock.withLock({ isStopping }) else {
            try? stream.removeStreamOutput(self, type: .screen)
            throw CancellationError()
        }
        try await stream.startCapture()
        LivePreviewDiagnostics.log("capture started id=\(windowID.rawValue)")
        if Task.isCancelled || stateLock.withLock({ isStopping }) {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
            throw CancellationError()
        }
    }

    @discardableResult
    func requestStop() -> Task<Void, Never>? {
        let updateTask = stateLock.withLock { () -> Task<Void, Never>? in
            isStopping = true
            let task = configurationUpdateTask
            configurationUpdateTask = nil
            return task
        }
        updateTask?.cancel()
        return updateTask
    }

    func stop() async {
        let updateTask = requestStop()
        let stream = stateLock.withLock { () -> SCStream? in
            let currentStream = self.stream
            self.stream = nil
            return currentStream
        }
        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
            LivePreviewDiagnostics.log("capture stopped id=\(windowID.rawValue)")
        }
        if let updateTask { await updateTask.value }
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
            displayScale: displayScale,
            sourceSize: sourceSize
        )
        let newKey = Self.key(for: configuration, framesPerSecond: profile.framesPerSecond)
        let shouldUpdate = stateLock.withLock { () -> Bool in
            guard configurationKey != newKey else { return false }
            configurationKey = newKey
            return true
        }
        guard shouldUpdate else { return }
        let updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self,
                  !Task.isCancelled,
                  let stream = self.stateLock.withLock({ self.isStopping ? nil : self.stream }) else { return }
            try? await stream.updateConfiguration(configuration)
        }
        let previousTask = stateLock.withLock { () -> Task<Void, Never>? in
            guard !isStopping else {
                updateTask.cancel()
                return nil
            }
            let previousTask = configurationUpdateTask
            configurationUpdateTask = updateTask
            return previousTask
        }
        previousTask?.cancel()
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

        logFrameDelivery(sampleBuffer)
        cacheValidFrameIfNeeded(sampleBuffer)

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
            LivePreviewDiagnostics.log("first frame id=\(windowID.rawValue)")
            LivePreviewDiagnostics.log("displaying live frame id=\(windowID.rawValue)")
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

    private func cacheValidFrameIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()
        let shouldCache = stateLock.withLock { () -> Bool in
            guard now - lastCachedFrameTime >= 0.5 else { return false }
            lastCachedFrameTime = now
            return true
        }
        guard shouldCache, let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard image.extent.width > 1,
              image.extent.height > 1,
              let rendered = frameRenderer.context.createCGImage(image, from: image.extent) else { return }
        onValidFrame(windowID, rendered)
    }

    private static func configuration(
        profile: LivePreviewProfile,
        previewSize: CGSize,
        displayScale: CGFloat,
        sourceSize: CGSize
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let pixelSize = LivePreviewCaptureSizing.pixelSize(
            sourceSize: sourceSize,
            previewSize: previewSize,
            backingScaleFactor: displayScale
        )
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
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

    private func logFrameDelivery(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let now = CACurrentMediaTime()
        let diagnostic = stateLock.withLock { () -> (count: Int, age: CFTimeInterval, shouldLog: Bool) in
            frameCount += 1
            let age = lastFrameTimestamp > 0 ? now - lastFrameTimestamp : 0
            lastFrameTimestamp = now
            let shouldLog = frameCount <= 3 || now - lastDiagnosticTime >= 2
            if shouldLog { lastDiagnosticTime = now }
            return (frameCount, age, shouldLog)
        }
        guard diagnostic.shouldLog else { return }

        let formattedAge = String(format: "%.3f", diagnostic.age)
        LivePreviewDiagnostics.log(
            "frame id=\(windowID.rawValue) #\(diagnostic.count) "
                + "size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))px "
                + "age=\(formattedAge)s"
        )
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
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
        displayLayer.videoGravity = .resizeAspect
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

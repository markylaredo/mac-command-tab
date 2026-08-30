import AppKit
import OSLog

@MainActor
final class EffectEngine {
    private struct ActiveEffect {
        let token: UUID
        let window: EffectWindow
        let rendererView: EffectRendererView
    }

    private let resources: EffectRendererResources?
    private var activeEffects: [WindowID: ActiveEffect] = [:]
    private let logger = Logger(subsystem: "com.maccommandtab.app", category: "Effects")

    init() {
        do {
            resources = try EffectRendererResources()
        } catch {
            resources = nil
            logger.error("Metal effects initialization failed: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    func play(
        effect: WindowEffect,
        snapshot: WindowSnapshot,
        frame: CGRect,
        direction: EffectDirection,
        duration: TimeInterval
    ) -> EffectPlayback? {
        let placement = EffectWindow.placement(forQuartzFrame: frame)
        return play(
            effect: effect,
            snapshot: snapshot,
            appKitFrame: placement.frame,
            screen: placement.screen,
            direction: direction,
            duration: duration
        )
    }

    @discardableResult
    func playPreview(
        effect: WindowEffect,
        snapshot: WindowSnapshot,
        appKitFrame: CGRect,
        direction: EffectDirection,
        duration: TimeInterval
    ) -> EffectPlayback? {
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitFrame) } ?? NSScreen.main
        return play(
            effect: effect,
            snapshot: snapshot,
            appKitFrame: appKitFrame,
            screen: screen,
            direction: direction,
            duration: duration
        )
    }

    func cancel(windowID: WindowID) {
        guard let active = activeEffects.removeValue(forKey: windowID) else { return }
        active.rendererView.cancel()
        active.window.removeImmediately()
    }

    func cancelAll() {
        for windowID in Array(activeEffects.keys) {
            cancel(windowID: windowID)
        }
    }

    private func play(
        effect: WindowEffect,
        snapshot: WindowSnapshot,
        appKitFrame: CGRect,
        screen: NSScreen?,
        direction: EffectDirection,
        duration: TimeInterval
    ) -> EffectPlayback? {
        guard effect != .none,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              appKitFrame.width > 1,
              appKitFrame.height > 1,
              let resources else { return nil }

        cancel(windowID: snapshot.windowID)
        let token = UUID()

        do {
            let rendererView = try EffectRendererView(
                resources: resources,
                snapshot: snapshot,
                effect: effect,
                direction: direction,
                duration: duration
            ) { [weak self] in
                self?.finish(windowID: snapshot.windowID, token: token)
            }
            let window = EffectWindow(frame: appKitFrame, rendererView: rendererView, screen: screen)
            activeEffects[snapshot.windowID] = ActiveEffect(
                token: token,
                window: window,
                rendererView: rendererView
            )
            window.show()
            rendererView.start()
            return EffectPlayback(engine: self, windowID: snapshot.windowID, token: token)
        } catch {
            logger.error("Effect playback failed for \(effect.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func finish(windowID: WindowID, token: UUID) {
        guard let active = activeEffects[windowID], active.token == token else { return }
        activeEffects.removeValue(forKey: windowID)
        active.rendererView.cancel()
        active.window.removeImmediately()
    }

    fileprivate func cancel(windowID: WindowID, token: UUID) {
        guard activeEffects[windowID]?.token == token else { return }
        cancel(windowID: windowID)
    }
}

@MainActor
final class EffectPlayback {
    private weak var engine: EffectEngine?
    private let windowID: WindowID
    private let token: UUID

    fileprivate init(engine: EffectEngine, windowID: WindowID, token: UUID) {
        self.engine = engine
        self.windowID = windowID
        self.token = token
    }

    func cancel() {
        engine?.cancel(windowID: windowID, token: token)
    }
}

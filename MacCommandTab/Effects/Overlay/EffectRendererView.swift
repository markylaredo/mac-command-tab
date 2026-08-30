@preconcurrency import MetalKit

@MainActor
final class EffectRendererView: MTKView {
    private var effectRenderer: EffectRenderer?

    init(
        resources: EffectRendererResources,
        snapshot: WindowSnapshot,
        effect: WindowEffect,
        direction: EffectDirection,
        duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) throws {
        super.init(frame: .zero, device: resources.device)
        guard let pipeline = resources.pipeline(for: effect) else {
            throw EffectRendererError.shaderUnavailable(effect.rawValue)
        }
        let textureLoader = MTKTextureLoader(device: resources.device)
        let sourceTexture = try textureLoader.newTexture(
            cgImage: snapshot.image,
            options: [
                .origin: MTKTextureLoader.Origin.topLeft.rawValue,
                .SRGB: false
            ]
        )

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        autoResizeDrawable = true
        wantsLayer = true
        layer?.isOpaque = false

        let renderer = EffectRenderer(
            resources: resources,
            pipeline: pipeline,
            sourceTexture: sourceTexture,
            direction: direction,
            duration: duration,
            seed: snapshot.seed,
            completion: completion
        )
        effectRenderer = renderer
        delegate = renderer
    }

    required init(coder: NSCoder) {
        fatalError("EffectRendererView must be created programmatically")
    }

    func start() {
        effectRenderer?.start()
        isPaused = false
    }

    func cancel() {
        isPaused = true
        effectRenderer?.cancel()
        delegate = nil
        effectRenderer = nil
    }
}

@preconcurrency import Metal
@preconcurrency import MetalKit
import Foundation
import QuartzCore

enum EffectRendererError: Error {
    case metalUnavailable
    case defaultLibraryUnavailable
    case commandQueueUnavailable
    case shaderUnavailable(String)
    case pipelineCreationFailed
}

final class EffectRendererResources: @unchecked Sendable {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipelines: [WindowEffect: MTLRenderPipelineState]

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EffectRendererError.metalUnavailable
        }
        guard let library = (try? device.makeDefaultLibrary(bundle: .main)) ?? device.makeDefaultLibrary() else {
            throw EffectRendererError.defaultLibraryUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw EffectRendererError.commandQueueUnavailable
        }
        guard let vertexFunction = library.makeFunction(name: "effectVertex") else {
            throw EffectRendererError.shaderUnavailable("effectVertex")
        }

        self.device = device
        self.commandQueue = commandQueue

        var pipelines: [WindowEffect: MTLRenderPipelineState] = [:]
        for effect in WindowEffect.allCases where effect != .none {
            guard let fragmentFunction = library.makeFunction(name: effect.fragmentFunctionName) else {
                throw EffectRendererError.shaderUnavailable(effect.fragmentFunctionName)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
                throw EffectRendererError.pipelineCreationFailed
            }
            pipelines[effect] = pipeline
        }
        self.pipelines = pipelines
    }

    func pipeline(for effect: WindowEffect) -> MTLRenderPipelineState? {
        pipelines[effect]
    }
}

private extension WindowEffect {
    var fragmentFunctionName: String {
        switch self {
        case .none: ""
        case .tv: "tvEffectFragment"
        case .pixelate: "pixelateEffectFragment"
        case .glide: "glideEffectFragment"
        }
    }
}

final class EffectRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let resources: EffectRendererResources
    private let pipeline: MTLRenderPipelineState
    private let sourceTexture: MTLTexture
    private let direction: EffectDirection
    private let duration: TimeInterval
    private let seed: Float
    private let completion: @MainActor @Sendable () -> Void
    private var startTime: CFTimeInterval?
    private var didComplete = false

    init(
        resources: EffectRendererResources,
        pipeline: MTLRenderPipelineState,
        sourceTexture: MTLTexture,
        direction: EffectDirection,
        duration: TimeInterval,
        seed: Float,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        self.resources = resources
        self.pipeline = pipeline
        self.sourceTexture = sourceTexture
        self.direction = direction
        self.duration = max(duration, 0.05)
        self.seed = seed
        self.completion = completion
    }

    func start() {
        startTime = CACurrentMediaTime()
        didComplete = false
    }

    func cancel() {
        didComplete = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !didComplete else { return }
        let now = CACurrentMediaTime()
        let startedAt = startTime ?? now
        if startTime == nil { startTime = startedAt }
        let elapsed = max(now - startedAt, 0)
        let linearProgress = min(elapsed / duration, 1)
        let effectProgress = direction == .opening ? 1 - linearProgress : linearProgress

        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = resources.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            if linearProgress >= 1 { finish() }
            return
        }

        var uniforms = EffectUniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            progress: Float(effectProgress),
            time: Float(elapsed),
            seed: seed
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if linearProgress >= 1 { finish() }
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        Task { @MainActor in completion() }
    }
}

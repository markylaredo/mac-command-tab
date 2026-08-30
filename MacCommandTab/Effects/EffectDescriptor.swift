import CoreGraphics
import Foundation

enum WindowEffect: String, CaseIterable, Identifiable, Sendable {
    case none
    case tv
    case pixelate
    case glide

    static let defaultsKey = "windowEffect"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .tv: "TV"
        case .pixelate: "Pixelate"
        case .glide: "Glide"
        }
    }

    var subtitle: String {
        switch self {
        case .none: "Switch immediately without a window transition"
        case .tv: "Collapse through a bright CRT scan line"
        case .pixelate: "Resolve through stable dissolving pixel blocks"
        case .glide: "A subtle professional scale and fade"
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .none: 0
        case .tv: 0.40
        case .pixelate: 0.42
        case .glide: 0.25
        }
    }

    static var saved: WindowEffect {
        guard let value = UserDefaults.standard.string(forKey: defaultsKey),
              let effect = WindowEffect(rawValue: value) else { return .glide }
        return effect
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

enum EffectDirection: Sendable {
    case opening
    case closing
}

struct EffectUniforms: Sendable {
    var resolution: SIMD2<Float>
    var progress: Float
    var time: Float
    var seed: Float
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0
}

struct WindowSnapshot: @unchecked Sendable {
    let windowID: WindowID
    let image: CGImage
    let capturedAt: Date
    let seed: Float

    init(windowID: WindowID, image: CGImage, capturedAt: Date = Date(), seed: Float? = nil) {
        self.windowID = windowID
        self.image = image
        self.capturedAt = capturedAt
        self.seed = seed ?? Self.stableSeed(for: windowID)
    }

    private static func stableSeed(for windowID: WindowID) -> Float {
        var hash: UInt32 = 2_166_136_261
        for byte in windowID.rawValue.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Float(hash % 10_000) / 10_000
    }
}

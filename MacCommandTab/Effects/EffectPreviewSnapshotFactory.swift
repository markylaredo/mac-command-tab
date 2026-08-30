import AppKit
import CoreGraphics

@MainActor
enum EffectPreviewSnapshotFactory {
    static let windowID = WindowID(rawValue: "maccommandtab:effect-preview")

    static func makeSnapshot(size: CGSize = CGSize(width: 640, height: 360)) -> WindowSnapshot? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let bounds = CGRect(origin: .zero, size: size)
        let background = NSGradient(colors: [
            NSColor(red: 0.035, green: 0.055, blue: 0.075, alpha: 1),
            NSColor(red: 0.075, green: 0.10, blue: 0.15, alpha: 1)
        ])
        background?.draw(in: bounds, angle: -24)

        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: size.height - 42, width: size.width, height: 42)).fill()

        let controls: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (index, color) in controls.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: 16 + CGFloat(index) * 22, y: size.height - 27, width: 12, height: 12)).fill()
        }

        let accent = NSColor(red: 0.34, green: 0.88, blue: 0.95, alpha: 1)
        accent.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: CGRect(x: 34, y: 42, width: 170, height: 245), xRadius: 16, yRadius: 16).fill()

        for row in 0..<5 {
            let opacity = 0.26 + CGFloat(row) * 0.08
            NSColor.white.withAlphaComponent(opacity).setFill()
            NSBezierPath(
                roundedRect: CGRect(x: 58, y: 76 + CGFloat(row) * 39, width: 120, height: 12),
                xRadius: 6,
                yRadius: 6
            ).fill()
        }

        let contentRect = CGRect(x: 232, y: 42, width: 374, height: 245)
        NSColor.black.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: contentRect, xRadius: 16, yRadius: 16).fill()

        accent.withAlphaComponent(0.70).setStroke()
        let graph = NSBezierPath()
        graph.lineWidth = 3
        graph.move(to: CGPoint(x: 258, y: 98))
        graph.curve(
            to: CGPoint(x: 578, y: 230),
            controlPoint1: CGPoint(x: 340, y: 245),
            controlPoint2: CGPoint(x: 472, y: 92)
        )
        graph.stroke()

        let title = "GPU WINDOW EFFECT"
        title.draw(
            at: CGPoint(x: 232, y: 305),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88),
                .kern: 1.2
            ]
        )
        let subtitle = "MacCommandTab · Metal preview"
        subtitle.draw(
            at: CGPoint(x: 258, y: 61),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.58)
            ]
        )

        guard let cgImage = context.makeImage() else { return nil }
        return WindowSnapshot(windowID: windowID, image: cgImage)
    }
}

import AppKit
import CoreGraphics

@MainActor
final class EffectWindow: NSPanel {
    init(frame: CGRect, rendererView: EffectRendererView, screen: NSScreen?) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        sharingType = .none

        rendererView.frame = NSRect(origin: .zero, size: frame.size)
        rendererView.autoresizingMask = [.width, .height]
        rendererView.drawableSize = CGSize(
            width: frame.width * (screen?.backingScaleFactor ?? 1),
            height: frame.height * (screen?.backingScaleFactor ?? 1)
        )
        contentView = rendererView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
    }

    func removeImmediately() {
        orderOut(nil)
        contentView = nil
    }

    static func placement(forQuartzFrame frame: CGRect) -> (frame: CGRect, screen: NSScreen?) {
        guard let match = screenMatch(forQuartzFrame: frame) else {
            return (frame, NSScreen.main)
        }
        let converted = CGRect(
            x: match.screen.frame.minX + frame.minX - match.displayBounds.minX,
            y: match.screen.frame.maxY - (frame.maxY - match.displayBounds.minY),
            width: frame.width,
            height: frame.height
        )
        return (converted, match.screen)
    }

    private static func screenMatch(forQuartzFrame frame: CGRect) -> (screen: NSScreen, displayBounds: CGRect)? {
        NSScreen.screens.compactMap { screen -> (NSScreen, CGRect, CGFloat)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let intersection = bounds.intersection(frame)
            let area = max(intersection.width, 0) * max(intersection.height, 0)
            return (screen, bounds, area)
        }
        .max { $0.2 < $1.2 }
        .map { ($0.0, $0.1) }
    }
}

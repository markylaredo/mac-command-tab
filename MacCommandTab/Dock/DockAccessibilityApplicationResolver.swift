@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

/// The real Dock resolver. This is the only type in the feature that depends on
/// the Dock's accessibility hierarchy, which is undocumented and may change
/// between macOS releases.
///
/// Everything here is best effort. Any failure — no Accessibility permission, a
/// changed hierarchy, a missing attribute — returns nil rather than guessing, and
/// leaves the rest of MacCommandTab untouched.
///
/// The Dock is never modified, injected into, or swizzled. Only read-only
/// accessibility queries are used.
@MainActor
final class DockAccessibilityApplicationResolver: DockApplicationResolving {
    private let diagnostics: DockHoverDiagnostics

    /// The Dock's layout changes rarely but is expensive to read. Both caches are
    /// invalidated together.
    private var cachedLayout: DockLayout?
    private var lastResolvedItem: DockItem?
    private var lastResolvedApplication: NSRunningApplication?

    /// The Dock's tile geometry is stable for long stretches. Re-reading it on
    /// every pointer sample would issue several accessibility round trips at
    /// mouse-move frequency, which is exactly what this feature must avoid.
    private let layoutLifetime: CFTimeInterval = 0.75
    private var layoutTimestamp: CFTimeInterval = 0

    init(diagnostics: DockHoverDiagnostics = DockHoverDiagnostics()) {
        self.diagnostics = diagnostics
    }

    // MARK: - DockApplicationResolving

    func application(at screenPoint: CGPoint) -> NSRunningApplication? {
        guard AccessibilityPermission.isGranted else { return nil }
        guard let layout = currentLayout() else { return nil }

        guard let item = DockItemResolver.item(at: screenPoint, in: layout.items) else {
            lastResolvedItem = nil
            lastResolvedApplication = nil
            return nil
        }

        // While the pointer stays inside one tile, the answer cannot change, so
        // the resolution is reused indefinitely rather than being re-derived on a
        // timer. Reading even a cached layout allocates the tile array, and a
        // pointer resting on a Dock icon produces samples continuously.
        if let previous = lastResolvedItem,
           previous == item,
           let application = lastResolvedApplication {
            return application
        }

        let records = runningApplicationRecords()
        guard let record = DockItemResolver.application(for: item, among: records) else {
            diagnostics.log("Dock tile did not resolve to a running application title=\(item.title ?? "nil")")
            lastResolvedItem = nil
            lastResolvedApplication = nil
            return nil
        }

        let application = NSRunningApplication(processIdentifier: record.processIdentifier)
        lastResolvedItem = item
        lastResolvedApplication = application
        diagnostics.log("Dock application resolved name=\(record.localizedName ?? "?") pid=\(record.processIdentifier)")
        return application
    }

    func isWithinDockRegion(_ screenPoint: CGPoint) -> Bool {
        guard AccessibilityPermission.isGranted else { return false }
        guard let layout = currentLayout() else { return false }
        return DockItemResolver.isWithinDockRegion(screenPoint, items: layout.items, dockFrame: layout.dockFrame)
    }

    func dockItemFrame(at screenPoint: CGPoint) -> CGRect? {
        guard AccessibilityPermission.isGranted else { return nil }
        guard let layout = currentLayout() else { return nil }
        return DockItemResolver.item(at: screenPoint, in: layout.items)?.frame
    }

    // MARK: - Dock layout

    private struct DockLayout {
        let items: [DockItem]
        let dockFrame: CGRect?
    }

    private func currentLayout() -> DockLayout? {
        let now = CACurrentMediaTime()
        if let cachedLayout, now - layoutTimestamp < layoutLifetime {
            return cachedLayout
        }
        guard let dock = dockElement() else { return nil }
        let items = readItems(from: dock)
        let layout = DockLayout(items: items, dockFrame: readDockFrame(from: dock, items: items))
        cachedLayout = layout
        layoutTimestamp = now
        return layout
    }

    private func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first else {
            diagnostics.log("Dock process not found")
            return nil
        }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }

    private func readItems(from dock: AXUIElement) -> [DockItem] {
        var collected: [DockItem] = []
        let lists = children(of: dock)
        for list in lists {
            for element in children(of: list) {
                guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else { continue }
                let title = string(element, kAXTitleAttribute as CFString)
                let url = bundleURL(of: element)
                // An application tile is one the Dock links to an installed
                // application. Everything else — Trash, folders, separators,
                // minimized windows, recent items — is recorded so the pointer
                // can still be recognised as being over the Dock, but is marked
                // as a non-application so it can never resolve to one.
                let isApplication = url != nil || hasApplicationSubrole(element)
                collected.append(
                    DockItem(
                        title: title,
                        bundleURL: url,
                        frame: appKitRect(fromAccessibilityRect: frame),
                        isApplication: isApplication
                    )
                )
            }
            if !collected.isEmpty { break }
        }
        return collected
    }

    /// The Dock reports its own frame through the same attributes as any window.
    /// It is used only as a coarse region test alongside the individual tiles.
    private func readDockFrame(from dock: AXUIElement, items: [DockItem]) -> CGRect? {
        if let frame = frame(of: dock), frame.width > 0, frame.height > 0 {
            return appKitRect(fromAccessibilityRect: frame)
        }
        guard let union = items.map(\.frame).reduce(nil as CGRect?, { partial, frame in
            partial.map { $0.union(frame) } ?? frame
        }) else { return nil }
        // Tiles do not cover the Dock's background between icon groups, so the
        // union is inflated to approximate the Dock's true extent.
        return union.insetBy(dx: -12, dy: -8)
    }

    /// Converts an Accessibility rectangle into the AppKit screen coordinates the
    /// rest of the application uses.
    ///
    /// This conversion is essential and easy to miss: accessibility reports
    /// positions from the top-left of the primary display, while
    /// `NSEvent.mouseLocation`, `NSPanel.setFrame`, and `NSScreen.frame` all use
    /// the bottom-left origin. Comparing the two directly yields a constant
    /// answer — the pointer either always looks like it is over the Dock or never
    /// does — because the y values live in disjoint ranges.
    ///
    /// Frames are converted once here rather than at each comparison, so every
    /// consumer downstream works in a single coordinate space.
    private func appKitRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func hasApplicationSubrole(_ element: AXUIElement) -> Bool {
        // `AXApplicationDockItem` is the subrole the Dock has used for
        // application tiles. It is treated as a hint only: when the hierarchy
        // stops reporting it, resolution falls back to the bundle URL and the
        // title, so a change here degrades rather than breaks.
        guard let subrole = string(element, kAXSubroleAttribute as CFString) else { return false }
        return subrole == "AXApplicationDockItem"
    }

    private func runningApplicationRecords() -> [DockApplicationRecord] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID }
            .map(DockApplicationRecord.init)
    }

    // MARK: - Accessibility primitives

    private func children(of element: AXUIElement) -> [AXUIElement] {
        if let value = copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement],
           !value.isEmpty {
            return value
        }
        // Newer systems expose navigation order in place of `AXChildren` for
        // some hierarchies.
        if let value = copyAttribute(element, "AXChildrenInNavigationOrder" as CFString) as? [AXUIElement] {
            return value
        }
        return []
    }

    private func copyAttribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: CFString) -> String? {
        copyAttribute(element, name) as? String
    }

    private func bundleURL(of element: AXUIElement) -> URL? {
        guard let value = copyAttribute(element, kAXURLAttribute as CFString) else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}

import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Debug-only diagnostic that dumps the macOS Dock accessibility hierarchy to a
/// file, so Dock hover support can be verified against the running system.
///
/// Compiled only in DEBUG builds and never invoked in release. Does nothing when
/// Accessibility permission is absent.
enum DockAccessibilityProbe {
    /// Written to Application Support rather than the temporary directory, which
    /// differs per process and is awkward to locate from outside the app.
    static var outputURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("MacCommandTab", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dock-accessibility-report.txt")
    }

    @MainActor
    static func writeReport() {
        guard AccessibilityPermission.isGranted else {
            try? "Accessibility not granted".write(to: outputURL, atomically: true, encoding: .utf8)
            return
        }
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first else {
            try? "Dock process not found".write(to: outputURL, atomically: true, encoding: .utf8)
            return
        }

        var report = "Dock pid = \(dock.processIdentifier)\n"
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)

        var names: CFArray?
        if AXUIElementCopyAttributeNames(dockElement, &names) == .success,
           let list = names as? [String] {
            report += "Dock app attributes: \(list.sorted().joined(separator: ", "))\n"
        }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenValue)
        report += "AXChildren result = \(result.rawValue)\n"

        // The same query the resolver performs, so the report states directly
        // whether tile discovery succeeds and what it found.
        let items = describeTileDiscovery(from: dockElement)
        report += items + "\n--- tree ---\n"
        report += describe(dockElement, depth: 0, maxDepth: 4)

        try? report.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Reports how many tiles the resolver's own traversal would find, and the
    /// first few titles. This is the number that decides whether hover previews
    /// can work at all.
    private static func describeTileDiscovery(from dockElement: AXUIElement) -> String {
        var lines = "--- tile discovery ---\n"
        let lists = children(of: dockElement)
        lines += "top-level children: \(lists.count)\n"
        var found = 0
        for (listIndex, list) in lists.enumerated() {
            let candidates = children(of: list)
            lines += "  child[\(listIndex)] role=\(string(list, kAXRoleAttribute as CFString) ?? "?") has \(candidates.count) children\n"
            for element in candidates {
                guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else { continue }
                found += 1
                let title = string(element, kAXTitleAttribute as CFString) ?? ""
                let url = bundleURL(of: element)?.path ?? "nil"
                let subrole = string(element, kAXSubroleAttribute as CFString) ?? "nil"
                if found <= 12 {
                    lines += "    tile title=[\(title)] subrole=\(subrole) url=\(url) frame=\(frame)\n"
                }
            }
        }
        lines += "tiles with a usable frame: \(found)\n"
        return lines
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        if let value = copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement],
           !value.isEmpty {
            return value
        }
        if let value = copyAttribute(element, "AXChildrenInNavigationOrder" as CFString) as? [AXUIElement] {
            return value
        }
        return []
    }

    private static func bundleURL(of element: AXUIElement) -> URL? {
        guard let value = copyAttribute(element, kAXURLAttribute as CFString) else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: CFString) -> String? {
        copyAttribute(element, name) as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              AXValueGetType(unsafeDowncast(positionValue, to: AXValue.self)) == .cgPoint,
              AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetType(unsafeDowncast(sizeValue, to: AXValue.self)) == .cgSize,
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func describe(_ element: AXUIElement, depth: Int, maxDepth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var line = "\(indent)\(string(element, kAXRoleAttribute as CFString) ?? "?")"
        if let subrole = string(element, kAXSubroleAttribute as CFString), !subrole.isEmpty {
            line += " subrole=\(subrole)"
        }
        if let title = string(element, kAXTitleAttribute as CFString), !title.isEmpty {
            line += " title=\"\(title)\""
        }
        if let description = string(element, kAXDescriptionAttribute as CFString), !description.isEmpty {
            line += " desc=\"\(description)\""
        }
        if let identifier = string(element, kAXIdentifierAttribute as CFString), !identifier.isEmpty {
            line += " id=\(identifier)"
        }
        if let frame = frame(of: element) {
            line += " frame=(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))"
        }

        var names: CFArray?
        if AXUIElementCopyAttributeNames(element, &names) == .success, let list = names as? [String] {
            for name in list {
                let lower = name.lowercased()
                let isRelevant = lower.contains("url") || lower.contains("bundle") || lower.contains("file")
                guard isRelevant else { continue }
                let value = copyAttribute(element, name as CFString)
                line += "\n\(indent)    · \(name) = \(value.map { "\($0)" } ?? "nil")"
            }
        }

        var output = line + "\n"
        guard depth < maxDepth else { return output }
        if let children = copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children.prefix(80) {
                output += describe(child, depth: depth + 1, maxDepth: maxDepth)
            }
        }
        return output
    }
}

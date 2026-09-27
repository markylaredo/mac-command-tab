import Foundation
import OSLog

/// Logging for the Dock hover feature, following the existing
/// `LivePreviewDiagnostics` pattern: a dedicated OSLog category at debug level.
///
/// Deliberately not wrapped in `#if DEBUG`. This project does not set
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, so `DEBUG` is never defined and a
/// guarded logger compiles away to nothing — which makes the feature impossible
/// to diagnose. OSLog's `.debug` level already keeps these out of the default
/// console and out of release output.
///
/// Deliberately coarse. Pointer positions are never logged, and a failing Dock
/// hierarchy is reported once per state change rather than on every sample, so a
/// changed macOS hierarchy cannot turn into a log flood.
struct DockHoverDiagnostics: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.maccommandtab.app",
        category: "DockHover"
    )

    func log(_ message: @autoclosure () -> String) {
        let text = message()
        Self.logger.debug("[DockHover] \(text, privacy: .public)")
    }

    func fault(_ message: @autoclosure () -> String) {
        let text = message()
        Self.logger.fault("[DockHover] \(text, privacy: .public)")
    }
}

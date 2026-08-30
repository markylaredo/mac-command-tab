import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var applicationPath: String {
        Bundle.main.bundleURL.path
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func resetStaleEntry() async -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "ScreenCapture", bundleIdentifier]

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

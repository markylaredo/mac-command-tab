import AppKit
@preconcurrency import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static var applicationPath: String {
        Bundle.main.bundleURL.path
    }

    @discardableResult
    static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func resetStaleEntry() async -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleIdentifier]

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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

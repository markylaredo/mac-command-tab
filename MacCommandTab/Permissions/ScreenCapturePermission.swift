import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    enum SetupState: String {
        case notRequested
        case waitingForRelaunch
        case repairAvailable

        var actionTitle: String {
            switch self {
            case .notRequested: "Allow Window Previews"
            case .waitingForRelaunch: "Relaunch to Finish"
            case .repairAvailable: "Reset & Request Again"
            }
        }
    }

    static var isGranted: Bool {
        let granted = CGPreflightScreenCaptureAccess()
        if granted { setupState = .notRequested }
        return granted
    }

    static var applicationName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MacCommandTab"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown bundle"
    }

    static var applicationPath: String {
        Bundle.main.bundleURL.path
    }

    static var setupState: SetupState {
        get {
            guard let value = UserDefaults.standard.string(forKey: setupStateKey),
                  let state = SetupState(rawValue: value) else { return .notRequested }
            return state
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: setupStateKey)
        }
    }

    static var identityHelp: String {
        guard bundleIdentifier.hasSuffix(".debug") else { return "" }
        return "Running \(applicationName) from Xcode (\(bundleIdentifier)). Development builds without a signing certificate can require permission again after rebuilding."
    }

    @discardableResult
    static func request() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        setupState = granted ? .notRequested : .waitingForRelaunch
        return granted
    }

    static func resetStaleEntry() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let currentBundleIdentifier = bundleIdentifier

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "ScreenCapture", currentBundleIdentifier]

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
    static func relaunch() {
        setupState = .repairAvailable
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.6; /usr/bin/open -n \"$1\"",
            "maccommandtab-relaunch",
            applicationPath
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private static var setupStateKey: String {
        "screenCapturePermissionSetupState.\(bundleIdentifier)"
    }
}

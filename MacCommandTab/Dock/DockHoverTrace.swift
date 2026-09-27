import Foundation

/// A bounded, opt-in trace of the Dock hover decision path.
///
/// Exists because OSLog proved unreliable for diagnosing this feature: log lines
/// at `.debug` level did not reach `log stream` or `log show`, which made a
/// silent feature indistinguishable from a feature whose logs were being
/// filtered. A file is unambiguous.
///
/// Deliberately bounded twice over — only state changes are recorded, and the
/// file stops growing after a fixed number of lines — so it can never become a
/// continuous write on the pointer path. Off unless explicitly armed.
@MainActor
final class DockHoverTrace {
    static let shared = DockHoverTrace()

    private let limit: Int
    private var log = DockHoverChangeLog<String>()
    private var lineCount = 0
    private var isArmed = false

    /// When set, tracing arms automatically at launch. Needed because the global
    /// monitor does not observe a programmatically warped cursor, so a trace can
    /// only be produced by real pointer movement.
    static let autoArmDefaultsKey = "dockHoverTraceAutoArm"

    private init(limit: Int = 200) {
        self.limit = limit
    }

    func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: Self.autoArmDefaultsKey) else { return }
        begin()
    }

    static var outputURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("MacCommandTab", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dock-hover-trace.txt")
    }

    /// Starts a fresh trace. Called when the user asks for one from the menu.
    func begin() {
        lineCount = 0
        log.reset()
        isArmed = true
        try? "Dock hover trace started \(Date())\n".write(to: Self.outputURL, atomically: true, encoding: .utf8)
    }

    func end() {
        isArmed = false
    }

    /// Records a decision, but only when it differs from the previous one and
    /// only while the trace is armed.
    func record(_ outcome: String) {
        guard isArmed, lineCount < limit else { return }
        guard log.shouldLog(outcome) else { return }
        lineCount += 1
        append("\(lineCount). \(outcome)\n")
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let url = Self.outputURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

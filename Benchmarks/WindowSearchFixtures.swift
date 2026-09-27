import AppKit
import ApplicationServices

// Offline fixtures for the semantic-search evaluation.
//
// The window sets below are modelled on real window titles captured from a running
// Mac (via CGWindowListCopyWindowInfo), using the shapes that actually appear in
// practice:
//
//   "Personal — Use the TypeSafe skill. Repository: — DeepSeek Harness"   (Safari)
//   "markanthony — markanthony — codex ◂ node /opt/homebrew/bin/codex"    (Terminal)
//   "Branch · System One Overview"                                        (Firefox)
//   "AGENTS.md (Working Tree) (AGENTS.md) — omeco-android-pms"            (VS Code)
//
// Names are illustrative. No real credentials, customers, or private project
// names are used.

enum WindowFixtures {
    // MARK: - Set A: multi-project web development

    static let webDevelopment: WindowSet = WindowSet(
        id: "A",
        name: "Multi-project web development",
        windows: [
            WindowFixture(app: "Safari", title: "Personal — Use the TypeSafe skill. Repository: — DeepSeek Harness"),
            WindowFixture(app: "Safari", title: "mac-command-tab: native macOS window switcher"),
            WindowFixture(app: "Safari", title: "Pull requests · acme/omeco-api"),
            WindowFixture(app: "Google Chrome", title: "GitHub · Pull requests"),
            WindowFixture(app: "Rider", title: "Omeco.ApiV2 – Rider"),
            WindowFixture(app: "Rider", title: "Omeco.Backend.Tests – Rider"),
            WindowFixture(app: "Visual Studio Code", title: "fleet-shell"),
            WindowFixture(app: "Terminal", title: "markanthony — docker compose up — 120×30"),
            WindowFixture(app: "Finder", title: "Downloads"),
            WindowFixture(app: "System Settings", title: "Displays")
        ]
    )

    // MARK: - Set B: many windows, several browsers

    static let manyWindows: WindowSet = WindowSet(
        id: "B",
        name: "Many windows, several browsers",
        windows: [
            WindowFixture(app: "Google Chrome", title: "GitHub · Pull requests"),
            WindowFixture(app: "Google Chrome", title: "Chrome DevTools — localhost:3000"),
            WindowFixture(app: "Firefox", title: "Branch · System One Overview"),
            WindowFixture(app: "Safari", title: "Apple Developer Documentation"),
            WindowFixture(app: "Safari", title: "Personal — Use the TypeSafe skill"),
            WindowFixture(app: "Rider", title: "Omeco.ApiV2 – Rider"),
            WindowFixture(app: "Xcode", title: "MacCommandTab — SwitcherCoordinator.swift"),
            WindowFixture(app: "Visual Studio Code", title: "AGENTS.md (Working Tree) (AGENTS.md) — omeco-android-pms"),
            WindowFixture(app: "Terminal", title: "markanthony — docker compose up — 120×30"),
            WindowFixture(app: "Terminal", title: "markanthony — ssh staging — 120×30"),
            WindowFixture(app: "Finder", title: "Downloads"),
            WindowFixture(app: "Finder", title: "Documents"),
            WindowFixture(app: "Notes", title: "Release checklist"),
            WindowFixture(app: "System Settings", title: "Displays")
        ]
    )

    // MARK: - Set C: non-development work

    static let office: WindowSet = WindowSet(
        id: "C",
        name: "Accounting and office work",
        windows: [
            WindowFixture(app: "Numbers", title: "Ledger 2026 — Q1"),
            WindowFixture(app: "Safari", title: "Invoice #1042 — Billing portal"),
            WindowFixture(app: "Mail", title: "Re: invoice correction"),
            WindowFixture(app: "Finder", title: "Receipts"),
            WindowFixture(app: "Preview", title: "statement-march.pdf"),
            WindowFixture(app: "System Settings", title: "Displays"),
            WindowFixture(app: "Terminal", title: "markanthony — ssh production — 120×30")
        ]
    )

    // MARK: - Set D: small session, for the bypass check

    static let small: WindowSet = WindowSet(
        id: "D",
        name: "Small session (four windows)",
        windows: [
            WindowFixture(app: "Safari", title: "GitHub · Pull requests"),
            WindowFixture(app: "Rider", title: "Omeco.ApiV2 – Rider"),
            WindowFixture(app: "Terminal", title: "markanthony — docker compose up — 120×30"),
            WindowFixture(app: "Finder", title: "Downloads")
        ]
    )

    // MARK: - Set E: stress test for recall flooding

    /// A large session full of windows that share vocabulary with each other.
    /// Recall widening accepts a window when every query token appears somewhere
    /// in its metadata, so a long query built from common words is the case most
    /// likely to drag in unrelated windows. This set exists to measure that.
    static let stress: WindowSet = WindowSet(
        id: "E",
        name: "Stress test — 40 windows sharing vocabulary",
        windows: (1...40).map { index in
            let app: String
            let title: String
            switch index % 4 {
            case 0:
                app = "Google Chrome"
                title = "GitHub · Pull request #\(index)"
            case 1:
                app = "Terminal"
                title = "markanthony — docker service \(index) — 120×30"
            case 2:
                app = "Visual Studio Code"
                title = "service-\(index).swift — omeco-api"
            default:
                app = "Finder"
                title = "Build \(index)"
            }
            return WindowFixture(app: app, title: title)
        }
    )

    static let all: [WindowSet] = [webDevelopment, manyWindows, office, small, stress]
}

/// A window as the search pipeline sees it. `WindowSearch` only reads
/// `applicationName` and `title`; everything else exists to build a `WindowInfo`.
struct WindowFixture: Equatable, Sendable {
    let app: String
    let title: String

    func makeWindowInfo() -> WindowInfo {
        WindowInfo(
            id: WindowID(rawValue: "\(app):\(title)"),
            pid: 0,
            title: title,
            applicationName: app,
            bundleIdentifier: nil,
            icon: nil,
            // A never-created element is never read by WindowSearch. Using `AXUIElementCreateSystemWide()`
            // would touch the live accessibility server, so this stays a standalone object.
            accessibilityElement: AXUIElementCreateApplication(0),
            isMinimized: false,
            isFullscreen: false,
            isApplicationHidden: false,
            isFocused: false,
            frame: .zero
        )
    }
}

struct WindowSet {
    let id: String
    let name: String
    let windows: [WindowFixture]
}

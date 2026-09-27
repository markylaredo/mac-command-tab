import AppKit

/// One element of the Dock's accessibility hierarchy, reduced to the fields the
/// resolver needs. Keeping this a plain value type means every matching and
/// filtering rule below is testable without a live Dock.
struct DockItem: Equatable, Sendable {
    /// The element's accessibility title, which for an application tile is the
    /// application's display label.
    let title: String?
    /// The bundle URL, when the Dock exposes one. This is the strongest
    /// identifier available and is preferred over any name comparison.
    let bundleURL: URL?
    /// The element's accessibility frame in screen coordinates.
    let frame: CGRect
    /// False for the Trash, folders, separators, and other non-application tiles.
    let isApplication: Bool

    init(title: String?, bundleURL: URL?, frame: CGRect, isApplication: Bool) {
        self.title = title
        self.bundleURL = bundleURL
        self.frame = frame
        self.isApplication = isApplication
    }
}

/// A running application, reduced to the fields needed to map a Dock tile onto
/// it. Built from `NSRunningApplication` in production and from literals in tests.
struct DockApplicationRecord: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let bundleURL: URL?
    let localizedName: String?
    let executableURL: URL?
    let isTerminated: Bool
    let activationPolicyIsRegular: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        bundleURL: URL?,
        localizedName: String?,
        executableURL: URL?,
        isTerminated: Bool = false,
        activationPolicyIsRegular: Bool = true
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.localizedName = localizedName
        self.executableURL = executableURL
        self.isTerminated = isTerminated
        self.activationPolicyIsRegular = activationPolicyIsRegular
    }

    init(_ application: NSRunningApplication) {
        processIdentifier = application.processIdentifier
        bundleIdentifier = application.bundleIdentifier
        bundleURL = application.bundleURL
        localizedName = application.localizedName
        executableURL = application.executableURL
        isTerminated = application.isTerminated
        activationPolicyIsRegular = application.activationPolicy == .regular
    }
}

/// Resolves the application under a screen point by inspecting the Dock.
///
/// This is the seam that keeps Dock-specific behaviour — which depends on an
/// undocumented accessibility hierarchy — out of the rest of the feature. It
/// answers exactly one question and returns nil whenever it cannot answer
/// confidently. No preview, window, or activation logic belongs here.
///
/// Main-actor isolated because it hands back `NSRunningApplication`, which is not
/// `Sendable`, and because it is only ever called from pointer handling.
@MainActor
protocol DockApplicationResolving {
    /// The application whose Dock tile contains `screenPoint`, or nil.
    func application(at screenPoint: CGPoint) -> NSRunningApplication?

    /// Whether `screenPoint` falls within the Dock's occupied region. Used to
    /// keep a preview open while the pointer travels across the Dock.
    func isWithinDockRegion(_ screenPoint: CGPoint) -> Bool

    /// The frame of the Dock tile containing `screenPoint`, in Accessibility
    /// screen coordinates. Used to anchor the preview panel to the tile the user
    /// is actually pointing at.
    func dockItemFrame(at screenPoint: CGPoint) -> CGRect?
}

/// A resolver that never resolves anything. Used when Accessibility permission is
/// unavailable and as a stand-in in tests that do not exercise Dock behaviour.
struct InactiveDockApplicationResolver: DockApplicationResolving {
    func application(at screenPoint: CGPoint) -> NSRunningApplication? { nil }
    func isWithinDockRegion(_ screenPoint: CGPoint) -> Bool { false }
    func dockItemFrame(at screenPoint: CGPoint) -> CGRect? { nil }
}

/// Maps a pointer position onto a Dock tile, and a Dock tile onto a running
/// application. Pure: it receives the Dock layout and the running application
/// list as values, so every rule is directly testable.
enum DockItemResolver {
    /// Tolerance around a tile, in points. The Dock's tiles are adjacent with a
    /// few points of padding, and pointer positions land on the boundary often
    /// enough that an exact containment test feels unreliable.
    static let hitInset: CGFloat = 2

    /// The application tile containing `point`, if any.
    ///
    /// Only application tiles participate. The Trash, folders, separators, and
    /// minimized-window entries are ignored entirely so they can never resolve to
    /// an application.
    static func item(at point: CGPoint, in items: [DockItem]) -> DockItem? {
        items.first { item in
            item.isApplication && item.frame.insetBy(dx: -hitInset, dy: -hitInset).contains(point)
        }
    }

    /// Whether `point` falls anywhere in the Dock's occupied region, including
    /// non-application tiles. A pointer resting on the Trash is still on the
    /// Dock, and a preview should not be dismissed for that.
    static func isWithinDockRegion(_ point: CGPoint, items: [DockItem], dockFrame: CGRect?) -> Bool {
        if let dockFrame, dockFrame.insetBy(dx: -hitInset, dy: -hitInset).contains(point) {
            return true
        }
        return items.contains { $0.frame.insetBy(dx: -hitInset, dy: -hitInset).contains(point) }
    }

    /// The running application a Dock tile refers to.
    ///
    /// Identifiers are tried strongest first. A display-name comparison is the
    /// last resort because it is the least stable: it is localized, and it can
    /// collide between applications. It is only reached when the Dock exposes no
    /// bundle URL.
    static func application(
        for item: DockItem,
        among applications: [DockApplicationRecord]
    ) -> DockApplicationRecord? {
        let candidates = applications.filter { !$0.isTerminated && $0.activationPolicyIsRegular }
        guard !candidates.isEmpty else { return nil }

        // 1. Bundle URL. Exact and stable, and the only identifier the Dock
        //    exposes directly.
        if let dockURL = item.bundleURL {
            let resolved = dockURL.resolvingSymlinksInPath().standardizedFileURL
            if let match = candidates.first(where: { candidate in
                guard let url = candidate.bundleURL?.resolvingSymlinksInPath().standardizedFileURL else { return false }
                return url == resolved
            }) {
                return match
            }
            // A Dock tile can outlive the application it points at. Fall through
            // only when the URL itself corresponds to a known running app.
        }

        guard let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        // 2. Bundle identifier, when the tile title happens to carry one.
        if let match = candidates.first(where: { $0.bundleIdentifier == title }) {
            return match
        }

        // 3. Display name, exact and case-insensitive.
        if let match = candidates.first(where: { $0.localizedName?.caseInsensitiveCompare(title) == .orderedSame }) {
            return match
        }

        // 4. Bundle name on disk, which can differ from the localized display
        //    name (for example "Safari.app" versus a localized label).
        if let match = candidates.first(where: { candidate in
            candidate.bundleURL?.deletingPathExtension().lastPathComponent
                .caseInsensitiveCompare(title) == .orderedSame
        }) {
            return match
        }

        // 5. Executable name, for applications whose bundle name is unrelated to
        //    the label the Dock shows.
        if let match = candidates.first(where: { candidate in
            candidate.executableURL?.lastPathComponent.caseInsensitiveCompare(title) == .orderedSame
        }) {
            return match
        }

        return nil
    }
}

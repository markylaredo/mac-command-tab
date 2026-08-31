@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

struct MRUWindowOrdering: Sendable {
    private var identifiers: [WindowID] = []

    mutating func record(_ identifier: WindowID) {
        identifiers.removeAll { $0 == identifier }
        identifiers.insert(identifier, at: 0)
    }

    mutating func order(_ windows: [WindowInfo]) -> [WindowInfo] {
        let currentIDs = Set(windows.map(\.id))
        identifiers.removeAll { !currentIDs.contains($0) }
        let rank = Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1, $0) })
        return windows.enumerated().sorted { lhs, rhs in
            let lhsRank = rank[lhs.element.id] ?? Int.max
            let rhsRank = rank[rhs.element.id] ?? Int.max
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }
}

struct WindowTrackerRefreshGeneration: Sendable {
    private(set) var value: UInt = 0
    private(set) var isRunning = false

    mutating func start() {
        value &+= 1
        isRunning = true
    }

    mutating func stop() {
        value &+= 1
        isRunning = false
    }

    mutating func scheduleRefresh() -> UInt {
        value &+= 1
        return value
    }

    func accepts(_ refreshGeneration: UInt) -> Bool {
        isRunning && refreshGeneration == value
    }
}

@MainActor
final class WindowTracker {
    private let discovery = WindowDiscovery()
    private let discoveryQueue = DispatchQueue(label: "com.maccommandtab.window-discovery", qos: .userInitiated)
    private var ordering = MRUWindowOrdering()
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var iconCache: [pid_t: NSImage] = [:]
    private var refreshGeneration = WindowTrackerRefreshGeneration()
    private(set) var windows: [WindowInfo] = []
    var onWindowsChanged: (([WindowInfo]) -> Void)?

    func start() {
        refreshGeneration.start()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    if let pid { self?.applicationActivated(pid: pid) }
                }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildObservers(); self?.refresh() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildObservers(); self?.refresh() }
            }
        ]
        rebuildObservers()
        recordCurrentFocusedWindow()
        refresh()
    }

    func stop() {
        refreshGeneration.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        observers.values.forEach { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource($0), .defaultMode) }
        observers.removeAll()
        windows = []
        onWindowsChanged?([])
    }

    func refresh(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard refreshGeneration.isRunning else { return }
        let generation = refreshGeneration.scheduleRefresh()
        let applications = applicationSnapshots()
        let discovery = discovery
        discoveryQueue.async { [weak self] in
            let discovered = discovery.discover(applications: applications)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.refreshGeneration.accepts(generation) else { return }
                    self.windows = self.ordering.order(discovered)
                    self.onWindowsChanged?(self.windows)
                    completion?()
                }
            }
        }
    }

    private func applicationSnapshots() -> [ApplicationSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy == .regular,
                  !app.isTerminated else { return nil }
            let icon = iconCache[app.processIdentifier] ?? bestApplicationIcon(for: app)
            if let icon { iconCache[app.processIdentifier] = icon }
            return ApplicationSnapshot(
                pid: app.processIdentifier,
                name: app.localizedName ?? "Application",
                bundleIdentifier: app.bundleIdentifier,
                icon: icon,
                isHidden: app.isHidden
            )
        }
    }

    private func bestApplicationIcon(for application: NSRunningApplication) -> NSImage? {
        var candidates: [NSImage] = []
        if let icon = application.icon { candidates.append(icon) }
        if let bundleURL = application.bundleURL {
            candidates.append(NSWorkspace.shared.icon(forFile: bundleURL.path))
        }
        return candidates.max { nativePixelDimension(of: $0) < nativePixelDimension(of: $1) }
    }

    private func nativePixelDimension(of image: NSImage) -> Int {
        image.representations.map { max($0.pixelsWide, $0.pixelsHigh) }.max() ?? 0
    }

    private func rebuildObservers() {
        let activePIDs = Set(applicationSnapshots().map(\.pid))
        let removedPIDs = observers.keys.filter { !activePIDs.contains($0) }
        for pid in removedPIDs {
            guard let observer = observers[pid] else { continue }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers.removeValue(forKey: pid)
        }
        for pid in activePIDs where observers[pid] == nil {
            var observer: AXObserver?
            let result = AXObserverCreate(pid, { _, element, _, context in
                guard let context else { return }
                let tracker = Unmanaged<WindowTracker>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { tracker.focusedWindowChanged(element, pid: processIdentifier(of: element)) }
            }, &observer)
            guard result == .success, let observer else { continue }
            let appElement = AXUIElementCreateApplication(pid)
            AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        }
    }

    private func applicationActivated(pid: pid_t) {
        if !recordFocusedWindow(for: pid) { refresh() }
    }

    private func recordCurrentFocusedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        _ = recordFocusedWindow(for: app.processIdentifier)
    }

    @discardableResult
    private func recordFocusedWindow(for pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        focusedWindowChanged(element, pid: pid)
        return true
    }

    private func focusedWindowChanged(_ element: AXUIElement, pid: pid_t) {
        ordering.record(WindowID(rawValue: "\(pid):\(CFHash(element))"))
        refresh()
    }
}

private func processIdentifier(of element: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
}

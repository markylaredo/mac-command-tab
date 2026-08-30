import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SwitcherCoordinator?
    private var statusBarController: StatusBarController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = SwitcherCoordinator()
        self.coordinator = coordinator
        statusBarController = StatusBarController(coordinator: coordinator)
        coordinator.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showPermissionWindow()
        return true
    }
}

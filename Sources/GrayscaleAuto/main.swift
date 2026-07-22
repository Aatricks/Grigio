import AppKit

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let appController = AppController()
    private var menuController: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuController = MenuController(appController: appController)
        appController.onStateChange = { [weak menuController] in menuController?.refreshIcon() }
        self.menuController = menuController
        appController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController.stop()
    }
}

@main
@MainActor
private enum GrayscaleAutoApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
        _ = delegate
    }
}

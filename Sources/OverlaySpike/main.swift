import AppKit
import GrayscaleCore
import OSLog

@MainActor
private final class SpikeDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.aatricks.grayscale-auto.spike", category: "overlay")
    private var overlays: [BackdropOverlay] = []
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = PrivateAPIs.probe()
        logger.notice("CABackdropLayer available: \(status.backdropLayerAvailable, privacy: .public)")
        logger.notice("CAFilter available: \(status.colorFilterAvailable, privacy: .public)")

        do {
            overlays = try NSScreen.screens.map { screen in
                logger.notice("Creating overlay for frame \(NSStringFromRect(screen.frame), privacy: .public)")
                return try BackdropOverlay(frame: screen.frame)
            }
            overlays.forEach { $0.show() }
            installStatusMenu()
            logger.notice("Overlay spike active on \(self.overlays.count, privacy: .public) display(s)")
        } catch {
            logger.fault("Overlay startup failed: \(String(describing: error), privacy: .public)")
            presentFailure(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlays.forEach { $0.hide() }
        overlays.removeAll()
    }

    @objc private func toggleOverlay(_ sender: NSMenuItem) {
        let shouldShow = !overlays.contains(where: \.isVisible)
        overlays.forEach { shouldShow ? $0.show() : $0.hide() }
        sender.title = shouldShow ? "Hide Grayscale Overlay" : "Show Grayscale Overlay"
        logger.notice("Overlay visibility changed to \(shouldShow, privacy: .public)")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◐"
        item.button?.toolTip = "grayscale-auto overlay spike"
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Hide Grayscale Overlay", action: #selector(toggleOverlay(_:)), keyEquivalent: "g")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Overlay Spike", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Overlay spike failed"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}

@main
@MainActor
private enum OverlaySpikeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = SpikeDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}

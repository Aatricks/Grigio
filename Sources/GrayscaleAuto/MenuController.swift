import AppKit
import ServiceManagement

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let appController: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(appController: AppController) {
        self.appController = appController
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
        statusItem.button?.toolTip = "grayscale-auto"
    }

    func refreshIcon() {
        let symbol = appController.isShowingColor ? "circle.fill" : "circle.lefthalf.filled"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "grayscale-auto status")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let master = item(
            title: "Grayscale Enabled",
            action: #selector(toggleMaster),
            state: appController.masterEnabled ? .on : .off
        )
        menu.addItem(master)

        let mode = NSMenuItem(title: "Mode: \(appController.mode.rawValue)", action: nil, keyEquivalent: "")
        mode.isEnabled = false
        menu.addItem(mode)
        menu.addItem(.separator())

        let allowlistItem = NSMenuItem(title: "Allowed Applications", action: nil, keyEquivalent: "")
        let allowlistMenu = NSMenu()
        for rule in appController.allowlist.rules() {
            let ruleItem = item(
                title: rule.isBrowser ? "\(rule.displayName) (browser)" : rule.displayName,
                action: #selector(toggleAllowlist(_:)),
                state: appController.allowlist.isEnabled(identifier: rule.identifier) ? .on : .off
            )
            ruleItem.representedObject = ["identifier": rule.identifier, "name": rule.displayName]
            allowlistMenu.addItem(ruleItem)
        }
        allowlistItem.submenu = allowlistMenu
        menu.addItem(allowlistItem)

        let runningItem = NSMenuItem(title: "Add Running Application", action: nil, keyEquivalent: "")
        let runningMenu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (NSRunningApplication, String, String)? in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let identity = appController.allowlistIdentity(for: app) else { return nil }
            return (app, identity.identifier, identity.name)
        }.sorted { $0.2.localizedCaseInsensitiveCompare($1.2) == .orderedAscending }
        for (_, identifier, name) in apps {
            let appItem = item(
                title: name,
                action: #selector(toggleAllowlist(_:)),
                state: appController.allowlist.isEnabled(identifier: identifier) ? .on : .off
            )
            appItem.representedObject = ["identifier": identifier, "name": name]
            runningMenu.addItem(appItem)
        }
        if runningMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No applications found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            runningMenu.addItem(empty)
        }
        runningItem.submenu = runningMenu
        menu.addItem(runningItem)

        menu.addItem(.separator())
        let loginEnabled = SMAppService.mainApp.status == .enabled
        menu.addItem(item(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), state: loginEnabled ? .on : .off))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit grayscale-auto", action: #selector(quit), keyEquivalent: "q"))
    }

    @objc private func toggleMaster() {
        appController.toggleMaster()
    }

    @objc private func toggleAllowlist(_ sender: NSMenuItem) {
        guard let represented = sender.representedObject as? [String: String],
              let identifier = represented["identifier"],
              let name = represented["name"] else { return }
        appController.setAllowlistEnabled(
            !appController.allowlist.isEnabled(identifier: identifier),
            identifier: identifier,
            displayName: name
        )
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func item(
        title: String,
        action: Selector?,
        state: NSControl.StateValue = .off,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.state = state
        return item
    }
}

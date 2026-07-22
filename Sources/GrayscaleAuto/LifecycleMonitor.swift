import AppKit

@MainActor
final class LifecycleMonitor {
    var onEvent: ((String) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.activeSpaceDidChangeNotification, reason: "space-changed")
        observe(workspaceCenter, name: NSWorkspace.didActivateApplicationNotification, reason: "app-activated")
        observe(workspaceCenter, name: NSWorkspace.didLaunchApplicationNotification, reason: "app-launched")
        observe(workspaceCenter, name: NSWorkspace.didTerminateApplicationNotification, reason: "app-terminated")
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification, reason: "wake")
        observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification, reason: "session-unlocked")
        observe(NotificationCenter.default, name: NSApplication.didChangeScreenParametersNotification, reason: "displays-changed")
        observe(DistributedNotificationCenter.default(), name: Notification.Name("com.apple.screenIsLocked"), reason: "screen-locked")
        observe(DistributedNotificationCenter.default(), name: Notification.Name("com.apple.screenIsUnlocked"), reason: "screen-unlocked")
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name, reason: String) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onEvent?(reason) }
        })
    }

    private func observe(_ center: DistributedNotificationCenter, name: Notification.Name, reason: String) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onEvent?(reason) }
        })
    }
}

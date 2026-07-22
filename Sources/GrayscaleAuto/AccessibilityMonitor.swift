import ApplicationServices
import Foundation
import GrayscaleCore

final class AccessibilityMonitor {
    var onEvent: ((String) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var applications: [pid_t: AXUIElement] = [:]

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestTrustIfNeeded() {
        guard !isTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func updateObservedProcesses(_ pids: Set<pid_t>) {
        let removed = Set(observers.keys).subtracting(pids)
        for pid in removed {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            applications.removeValue(forKey: pid)
        }

        guard isTrusted else { return }
        for pid in pids where observers[pid] == nil {
            installObserver(for: pid)
        }
    }

    func fullscreenWindows(for pids: Set<pid_t>) -> [WindowCandidate] {
        guard isTrusted else { return [] }
        return pids.flatMap { pid in
            let application = applications[pid] ?? AXUIElementCreateApplication(pid)
            return windows(of: application).compactMap { window -> WindowCandidate? in
                guard boolAttribute("AXFullScreen", of: window) == true,
                      let frame = frame(of: window) else { return nil }
                return WindowCandidate(ownerPID: pid, frame: frame, isFullscreen: true)
            }
        }
    }

    private func installObserver(for pid: pid_t) {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &observer)
        guard result == .success, let observer else { return }

        let application = AXUIElementCreateApplication(pid)
        observers[pid] = observer
        applications[pid] = application
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, context)
        AXObserverAddNotification(observer, application, kAXFocusedWindowChangedNotification as CFString, context)
        observeWindows(of: application, with: observer, context: context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func observeWindows(of application: AXUIElement, with observer: AXObserver, context: UnsafeMutableRawPointer) {
        for window in windows(of: application) {
            AXObserverAddNotification(observer, window, "AXFullScreenChanged" as CFString, context)
            AXObserverAddNotification(observer, window, kAXWindowResizedNotification as CFString, context)
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, context)
        }
    }

    private func handle(notification: String, observer: AXObserver) {
        if notification == kAXWindowCreatedNotification as String,
           let (pid, application) = applications.first(where: { observers[$0.key] === observer }) {
            let context = Unmanaged.passUnretained(self).toOpaque()
            observeWindows(of: application, with: observer, context: context)
            applications[pid] = application
        }
        onEvent?("accessibility:\(notification)")
    }

    private func windows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static let callback: AXObserverCallback = { observer, _, notification, context in
        guard let context else { return }
        let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async {
            monitor.handle(notification: notification as String, observer: observer)
        }
    }
}

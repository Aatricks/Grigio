import AppKit
import CoreGraphics
import Darwin
import GrayscaleCore
import OSLog

@MainActor
final class AppController {
    let allowlist = AllowlistStore()
    private let logger = Logger(subsystem: "com.aatricks.grayscale-auto", category: "reconciler")
    private let accessibility = AccessibilityMonitor()
    private let lifecycle = LifecycleMonitor()
    private let backend = DisplayBackendController()
    private var watchdog: Timer?
    private var missionControlWatchdog: Timer?
    private var allowlistedPIDs: Set<pid_t> = []
    private var desiredColorSpaces: Set<SpaceOverlayKey> = []
    private var missionControlActive = false
    private var appliedMissionControlActive = false
    private(set) var desiredColorDisplays: Set<CGDirectDisplayID> = []
    private(set) var masterEnabled: Bool
    var onStateChange: (() -> Void)?

    var mode: GrayscaleMode { backend.mode }
    var isShowingColor: Bool {
        !masterEnabled || (!missionControlActive && !desiredColorDisplays.isEmpty)
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "masterEnabled") == nil {
            defaults.set(true, forKey: "masterEnabled")
        }
        masterEnabled = defaults.bool(forKey: "masterEnabled")
    }

    func start() {
        GlobalGrayscaleBackend.installCleanupHandlers()
        accessibility.onEvent = { [weak self] reason in self?.reconcile(reason: reason) }
        lifecycle.onEvent = { [weak self] reason in
            guard let self else { return }
            if reason == "displays-changed" { self.backend.synchronizeDisplays() }
            if reason == "app-launched" || reason == "app-terminated" || reason == "wake" {
                self.refreshAllowlistedProcesses()
            }
            self.reconcile(reason: "event:\(reason)")
        }
        accessibility.requestTrustIfNeeded()
        backend.synchronizeDisplays()
        lifecycle.start()
        refreshAllowlistedProcesses()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile(reason: "watchdog") }
        }
        let missionControlWatchdog = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshMissionControlState() }
        }
        RunLoop.main.add(missionControlWatchdog, forMode: .common)
        self.missionControlWatchdog = missionControlWatchdog
        reconcile(reason: "event:launch")
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        missionControlWatchdog?.invalidate()
        missionControlWatchdog = nil
        lifecycle.stop()
        backend.tearDown()
    }

    func toggleMaster() {
        masterEnabled.toggle()
        UserDefaults.standard.set(masterEnabled, forKey: "masterEnabled")
        reconcile(reason: "event:master-toggle")
    }

    func setAllowlistEnabled(_ enabled: Bool, identifier: String, displayName: String) {
        allowlist.setEnabled(enabled, identifier: identifier, displayName: displayName)
        refreshAllowlistedProcesses()
        reconcile(reason: "event:allowlist-change")
    }

    func allowlistIdentity(for app: NSRunningApplication) -> (identifier: String, name: String)? {
        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown Application"
        if let identifier = app.bundleIdentifier { return (identifier, name) }
        if name.caseInsensitiveCompare("mpv") == .orderedSame { return ("io.mpv", name) }
        return nil
    }

    private func reconcile(reason: String) {
        let displays = WindowSnapshotProvider.activeDisplays()
        let pids = allowlistedPIDs

        let visible = WindowSnapshotProvider.visibleWindows(for: pids)
        let watchdogWindows = WindowSnapshotProvider.fullscreenWindows(in: visible, displays: displays)
        let accessibilityWindows = accessibility.fullscreenWindows(for: pids).compactMap { candidate in
            watchdogWindows.first { $0.ownerPID == candidate.ownerPID }
        }
        let windows = accessibilityWindows + watchdogWindows
        let nextDisplays = Reconciler.desiredColorDisplays(
            masterEnabled: masterEnabled,
            displays: displays,
            allowlistedPIDs: pids,
            windows: windows
        )
        let nextSpaces = Reconciler.desiredColorSpaces(
            masterEnabled: masterEnabled,
            displays: displays,
            allowlistedPIDs: pids,
            windows: windows
        )

        let changed = nextDisplays != desiredColorDisplays
            || nextSpaces != desiredColorSpaces
            || missionControlActive != appliedMissionControlActive
        if changed {
            logger.notice(
                "Transition reason=\(reason, privacy: .public) missionControl=\(self.missionControlActive, privacy: .public) displays=\(String(describing: nextDisplays), privacy: .public) spaces=\(String(describing: nextSpaces), privacy: .public)"
            )
            desiredColorDisplays = nextDisplays
            desiredColorSpaces = nextSpaces
            appliedMissionControlActive = missionControlActive
        }
        backend.apply(
            desiredColorSpaces: desiredColorSpaces,
            desiredColorDisplays: desiredColorDisplays,
            masterEnabled: masterEnabled,
            forceGrayscale: missionControlActive
        )
        if changed { onStateChange?() }
    }

    private func refreshAllowlistedProcesses() {
        allowlistedPIDs = Set(NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
            guard let identity = allowlistIdentity(for: app),
                  allowlist.isEnabled(identifier: identity.identifier) else { return nil }
            return app.processIdentifier
        })
        accessibility.updateObservedProcesses(allowlistedPIDs)
        logger.notice(
            "Observed allowlistedPIDs=\(String(describing: self.allowlistedPIDs), privacy: .public) accessibilityTrusted=\(self.accessibility.isTrusted, privacy: .public)"
        )
    }

    private func refreshMissionControlState() {
        let active = WindowSnapshotProvider.isMissionControlActive(
            displays: WindowSnapshotProvider.activeDisplays()
        )
        guard active != missionControlActive else { return }
        missionControlActive = active
        reconcile(reason: active ? "mission-control-entered" : "mission-control-exited")
    }

}

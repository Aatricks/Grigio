import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import GrayscaleCore
import IOKit.pwr_mgt

enum WindowSnapshotProvider {
    private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunc = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void

    private typealias MRMediaRemoteGetNowPlayingClientFunc = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (AnyObject?) -> Void
    ) -> Void

    private struct MediaRemoteSymbols: Sendable {
        let getNowPlayingIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunc
        let getNowPlayingClient: MRMediaRemoteGetNowPlayingClientFunc

        static let shared: MediaRemoteSymbols? = {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
                return nil
            }
            guard let isPlayingSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
                  let clientSym = dlsym(handle, "MRMediaRemoteGetNowPlayingClient") else {
                return nil
            }
            let isPlaying = unsafeBitCast(isPlayingSym, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunc.self)
            let client = unsafeBitCast(clientSym, to: MRMediaRemoteGetNowPlayingClientFunc.self)
            return MediaRemoteSymbols(getNowPlayingIsPlaying: isPlaying, getNowPlayingClient: client)
        }()
    }

    static func activeDisplays() -> [DisplayDescriptor] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { DisplayDescriptor(id: $0, frame: CGDisplayBounds($0)) }
    }

    static func visibleWindows(for allowlistedPIDs: Set<pid_t>) -> [WindowCandidate] {
        guard let rows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        return rows.compactMap { row in
            guard let pidNumber = row[kCGWindowOwnerPID] as? NSNumber,
                  allowlistedPIDs.contains(pidNumber.int32Value),
                  (row[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let windowNumber = row[kCGWindowNumber] as? NSNumber,
                  let boundsDictionary = row[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            return WindowCandidate(
                ownerPID: pidNumber.int32Value,
                frame: bounds,
                isFullscreen: false,
                spaceIDs: ManagedSpaces.spaceIDs(forWindowNumber: windowNumber.intValue)
            )
        }
    }

    static func fullscreenWindows(
        in visibleWindows: [WindowCandidate],
        displays: [DisplayDescriptor]
    ) -> [WindowCandidate] {
        visibleWindows.compactMap { window in
            guard displays.contains(where: {
                FullscreenHeuristics.matchesFullscreenContentArea(
                    window.frame,
                    displayBounds: $0.frame
                )
            }) else { return nil }
            return WindowCandidate(
                ownerPID: window.ownerPID,
                frame: window.frame,
                isFullscreen: true,
                spaceIDs: window.spaceIDs
            )
        }
    }

    // Playback observations combine IOKit display-sleep assertions with
    // MediaRemote for apps such as Safari.
    static func activePlaybackPIDs(among allowlistedPIDs: Set<pid_t>) -> Set<pid_t>? {
        guard !allowlistedPIDs.isEmpty else { return [] }
        let powerAssertionPIDs = powerAssertionPlaybackPIDs(among: allowlistedPIDs)
        let mediaRemotePIDs = mediaRemotePlaybackPIDs(among: allowlistedPIDs)
        return PlaybackSignalPolicy.combine(powerAssertions: powerAssertionPIDs, mediaRemote: mediaRemotePIDs)
    }

    private static func powerAssertionPlaybackPIDs(among allowlistedPIDs: Set<pid_t>) -> Set<pid_t>? {
        guard !allowlistedPIDs.isEmpty else { return [] }
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let byProcess = assertions?.takeRetainedValue()
              as? [NSNumber: [[String: Any]]] else { return nil }

        return Set(byProcess.compactMap { pidNumber, records -> pid_t? in
            let pid = pidNumber.int32Value
            guard allowlistedPIDs.contains(pid) else { return nil }
            let holdsDisplayAssertion = records.contains { record in
                let type = record["AssertionTrueType"] as? String
                    ?? record[kIOPMAssertionTypeKey] as? String
                return type == kIOPMAssertionTypePreventUserIdleDisplaySleep
                    || type == "NoDisplaySleepAssertion"
            }
            return holdsDisplayAssertion ? pid : nil
        })
    }

    private static let mediaRemoteQueue = DispatchQueue(label: "com.aatricks.grayscale-auto.mediaremote")

    private static func mediaRemotePlaybackPIDs(among allowlistedPIDs: Set<pid_t>) -> Set<pid_t>? {
        guard !allowlistedPIDs.isEmpty else { return [] }
        guard let symbols = MediaRemoteSymbols.shared else { return nil }

        let group = DispatchGroup()
        var isPlayingResult: Bool?
        var clientResult: AnyObject?

        group.enter()
        symbols.getNowPlayingIsPlaying(mediaRemoteQueue) { isPlaying in
            isPlayingResult = isPlaying
            group.leave()
        }

        group.enter()
        symbols.getNowPlayingClient(mediaRemoteQueue) { client in
            clientResult = client
            group.leave()
        }

        let timeoutResult = group.wait(timeout: .now() + .milliseconds(100))
        if timeoutResult == .timedOut {
            return nil
        }

        guard let isPlaying = isPlayingResult else {
            return nil
        }

        if !isPlaying {
            return PlaybackSignalPolicy.mediaRemoteObservation(
                isPlaying: false,
                clientBundleIdentifier: nil,
                parentApplicationBundleIdentifier: nil,
                allowlistedBundleMap: [:]
            )
        }

        guard let client = clientResult else {
            return nil
        }

        var clientBundleID: String?
        var parentBundleID: String?
        let bundleSel = NSSelectorFromString("bundleIdentifier")
        let parentSel = NSSelectorFromString("parentApplicationBundleIdentifier")

        if let nsObj = client as? NSObject {
            if nsObj.responds(to: bundleSel) {
                clientBundleID = nsObj.perform(bundleSel)?.takeUnretainedValue() as? String
            }
            if nsObj.responds(to: parentSel) {
                parentBundleID = nsObj.perform(parentSel)?.takeUnretainedValue() as? String
            }
        }

        var allowlistedBundleMap: [pid_t: String] = [:]
        for pid in allowlistedPIDs {
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                allowlistedBundleMap[pid] = bundleID
            }
        }

        return PlaybackSignalPolicy.mediaRemoteObservation(
            isPlaying: true,
            clientBundleIdentifier: clientBundleID,
            parentApplicationBundleIdentifier: parentBundleID,
            allowlistedBundleMap: allowlistedBundleMap
        )
    }

    static func isMissionControlActive(displays: [DisplayDescriptor]) -> Bool {
        guard let rows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return false }

        return rows.contains { row in
            guard let layer = (row[kCGWindowLayer] as? NSNumber)?.intValue,
                  (18 ... 20).contains(layer),
                  let pid = (row[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  let boundsDictionary = row[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                return false
            }
            return MissionControlHeuristics.isOverviewWindow(
                ownerBundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                layer: layer,
                frame: frame,
                displays: displays
            )
        }
    }
}

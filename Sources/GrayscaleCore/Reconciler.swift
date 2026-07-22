import CoreGraphics
import Darwin

public enum Reconciler {
    public static func desiredColorSpaces(
        masterEnabled: Bool,
        displays: [DisplayDescriptor],
        allowlistedPIDs: Set<pid_t>,
        windows: [WindowCandidate]
    ) -> Set<SpaceOverlayKey> {
        guard masterEnabled else { return [] }

        return Set(windows.flatMap { window -> [SpaceOverlayKey] in
            guard window.isFullscreen,
                  allowlistedPIDs.contains(window.ownerPID),
                  let displayID = DisplayAttribution.displayID(for: window.frame, among: displays) else {
                return []
            }
            return window.spaceIDs.map { SpaceOverlayKey(displayID: displayID, spaceID: $0) }
        })
    }

    public static func playbackColorSpaces(
        masterEnabled: Bool,
        displays: [DisplayDescriptor],
        activePlaybackPIDs: Set<pid_t>,
        windows: [WindowCandidate]
    ) -> Set<SpaceOverlayKey> {
        guard masterEnabled else { return [] }

        return Set(windows.flatMap { window -> [SpaceOverlayKey] in
            guard activePlaybackPIDs.contains(window.ownerPID),
                  let displayID = DisplayAttribution.displayID(for: window.frame, among: displays) else {
                return []
            }
            return window.spaceIDs.map { SpaceOverlayKey(displayID: displayID, spaceID: $0) }
        })
    }

    public static func playbackColorDisplays(
        masterEnabled: Bool,
        displays: [DisplayDescriptor],
        activePlaybackPIDs: Set<pid_t>,
        windows: [WindowCandidate]
    ) -> Set<CGDirectDisplayID> {
        guard masterEnabled else { return [] }

        return Set(windows.compactMap { window in
            guard activePlaybackPIDs.contains(window.ownerPID) else { return nil }
            return DisplayAttribution.displayID(for: window.frame, among: displays)
        })
    }

    public static func desiredColorDisplays(
        masterEnabled: Bool,
        displays: [DisplayDescriptor],
        allowlistedPIDs: Set<pid_t>,
        windows: [WindowCandidate]
    ) -> Set<CGDirectDisplayID> {
        guard masterEnabled else {
            return Set(displays.map(\.id))
        }

        return Set(
            windows.compactMap { window in
                guard window.isFullscreen, allowlistedPIDs.contains(window.ownerPID) else {
                    return nil
                }
                return DisplayAttribution.displayID(for: window.frame, among: displays)
            }
        )
    }
}

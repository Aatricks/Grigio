import CoreGraphics
import Darwin

public enum Reconciler {
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

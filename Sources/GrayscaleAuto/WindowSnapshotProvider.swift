import ApplicationServices
import CoreGraphics
import Darwin
import GrayscaleCore

enum WindowSnapshotProvider {
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
                  let boundsDictionary = row[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            return WindowCandidate(ownerPID: pidNumber.int32Value, frame: bounds, isFullscreen: false)
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
            return WindowCandidate(ownerPID: window.ownerPID, frame: window.frame, isFullscreen: true)
        }
    }
}

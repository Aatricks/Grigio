import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import GrayscaleCore
import IOKit.pwr_mgt

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

    // Video players hold a display-sleep power assertion while actively
    // playing and drop it when paused, so an allowlisted PID holding one is
    // a reliable "is playing" signal without private frameworks.
    static func activePlaybackPIDs(among allowlistedPIDs: Set<pid_t>) -> Set<pid_t>? {
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

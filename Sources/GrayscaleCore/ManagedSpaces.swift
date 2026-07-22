import CPrivateAPIs
import CoreGraphics
import Foundation

public enum ManagedSpaces {
    public static func topology(for displayIDs: [CGDirectDisplayID]) -> [ManagedSpaceDescriptor] {
        guard let records = GrayscaleCopyManagedDisplaySpaces() as? [[String: Any]] else { return [] }
        let pairs: [(String, CGDirectDisplayID)] = displayIDs.compactMap { displayID in
            guard let uuidString = GrayscaleCopyDisplayUUID(displayID) else { return nil }
            return (uuidString as String, displayID)
        }
        let idsByUUID = Dictionary(uniqueKeysWithValues: pairs)
        return ManagedSpaceTopologyParser.parse(records, displayIDsByUUID: idsByUUID)
    }

    public static func bind(
        windowNumber: Int,
        to targetSpaceID: UInt64,
        knownSpaceIDs: Set<UInt64>
    ) {
        guard let windowID = UInt32(exactly: windowNumber) else { return }
        GrayscaleAddWindowToSpace(windowID, targetSpaceID)
        for spaceID in knownSpaceIDs where spaceID != targetSpaceID {
            GrayscaleRemoveWindowFromSpace(windowID, spaceID)
        }
    }

    public static func currentSpaceIDs(
        for displayIDs: [CGDirectDisplayID]
    ) -> [CGDirectDisplayID: UInt64] {
        Dictionary(uniqueKeysWithValues: displayIDs.compactMap { displayID in
            let spaceID = GrayscaleCurrentSpaceForDisplay(displayID)
            return spaceID == 0 ? nil : (displayID, spaceID)
        })
    }

    public static func spaceIDs(forWindowNumber windowNumber: Int) -> Set<UInt64> {
        guard let windowID = UInt32(exactly: windowNumber),
              let numbers = GrayscaleCopySpacesForWindow(windowID) as? [NSNumber] else { return [] }
        return Set(numbers.map(\.uint64Value))
    }
}

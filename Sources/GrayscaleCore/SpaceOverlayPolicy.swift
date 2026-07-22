import CoreGraphics
import Foundation

public struct SpaceOverlayKey: Hashable, Sendable {
    public let displayID: CGDirectDisplayID
    public let spaceID: UInt64

    public init(displayID: CGDirectDisplayID, spaceID: UInt64) {
        self.displayID = displayID
        self.spaceID = spaceID
    }
}

public struct ManagedSpaceDescriptor: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let spaceID: UInt64
    public let isCurrent: Bool

    public var key: SpaceOverlayKey {
        SpaceOverlayKey(displayID: displayID, spaceID: spaceID)
    }

    public init(displayID: CGDirectDisplayID, spaceID: UInt64, isCurrent: Bool) {
        self.displayID = displayID
        self.spaceID = spaceID
        self.isCurrent = isCurrent
    }
}

public enum SpaceOverlayVisibility {
    public static func visibleOverlayKeys(
        topology: [ManagedSpaceDescriptor],
        desiredColorDisplays: Set<CGDirectDisplayID>,
        masterEnabled: Bool
    ) -> Set<SpaceOverlayKey> {
        guard masterEnabled else { return [] }
        return Set(topology.compactMap { space in
            desiredColorDisplays.contains(space.displayID) && space.isCurrent ? nil : space.key
        })
    }
}

public enum ManagedSpaceTopologyParser {
    public static func parse(
        _ records: [[String: Any]],
        displayIDsByUUID: [String: CGDirectDisplayID]
    ) -> [ManagedSpaceDescriptor] {
        records.flatMap { record -> [ManagedSpaceDescriptor] in
            guard let displayUUID = record["Display Identifier"] as? String,
                  let displayID = displayIDsByUUID[displayUUID],
                  let spaces = record["Spaces"] as? [[String: Any]] else { return [] }
            let current = ((record["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
            return spaces.compactMap { space in
                guard let spaceID = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { return nil }
                return ManagedSpaceDescriptor(
                    displayID: displayID,
                    spaceID: spaceID,
                    isCurrent: spaceID == current
                )
            }
        }
    }
}

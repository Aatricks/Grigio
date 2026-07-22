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
    public let isFullscreenApplicationSpace: Bool

    public var key: SpaceOverlayKey {
        SpaceOverlayKey(displayID: displayID, spaceID: spaceID)
    }

    public init(
        displayID: CGDirectDisplayID,
        spaceID: UInt64,
        isCurrent: Bool,
        isFullscreenApplicationSpace: Bool = false
    ) {
        self.displayID = displayID
        self.spaceID = spaceID
        self.isCurrent = isCurrent
        self.isFullscreenApplicationSpace = isFullscreenApplicationSpace
    }
}

public enum SpaceOverlayVisibility {
    public static func visibleOverlayKeys(
        topology: [ManagedSpaceDescriptor],
        desiredColorSpaces: Set<SpaceOverlayKey>,
        playbackColorSpaces: Set<SpaceOverlayKey> = [],
        masterEnabled: Bool,
        forceGrayscale: Bool = false
    ) -> Set<SpaceOverlayKey> {
        guard masterEnabled else { return [] }
        let allKeys = Set(topology.map(\.key))
        guard !forceGrayscale else { return allKeys }
        let fullscreenKeys = Set(
            topology.lazy.filter(\.isFullscreenApplicationSpace).map(\.key)
        )
        // Fullscreen color is gated to genuine fullscreen Spaces; active
        // playback also colors the desktop Space it plays on, since a
        // windowed video cannot be desaturated cheaply.
        let colored = desiredColorSpaces.intersection(fullscreenKeys)
            .union(playbackColorSpaces)
        return allKeys.subtracting(colored)
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
                    isCurrent: spaceID == current,
                    isFullscreenApplicationSpace: (space["type"] as? NSNumber)?.intValue == 4
                )
            }
        }
    }
}

import CoreGraphics
import Darwin

public struct DisplayDescriptor: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let frame: CGRect

    public init(id: CGDirectDisplayID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct WindowCandidate: Equatable, Sendable {
    public let ownerPID: pid_t
    public let frame: CGRect
    public let isFullscreen: Bool
    public let spaceIDs: Set<UInt64>

    public init(
        ownerPID: pid_t,
        frame: CGRect,
        isFullscreen: Bool,
        spaceIDs: Set<UInt64> = []
    ) {
        self.ownerPID = ownerPID
        self.frame = frame
        self.isFullscreen = isFullscreen
        self.spaceIDs = spaceIDs
    }
}

public struct AppRule: Equatable, Sendable {
    public let identifier: String
    public let displayName: String
    public let isBrowser: Bool
    public let defaultEnabled: Bool

    public init(identifier: String, displayName: String, isBrowser: Bool, defaultEnabled: Bool) {
        self.identifier = identifier
        self.displayName = displayName
        self.isBrowser = isBrowser
        self.defaultEnabled = defaultEnabled
    }
}

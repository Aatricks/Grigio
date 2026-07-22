import CoreGraphics

public enum OverlayVisibilityAction: Equatable, Sendable {
    case show
    case hide
}

public enum OverlayVisibility {
    public static func displayIDsNeedingOverlay(
        allDisplayIDs: Set<CGDirectDisplayID>,
        desiredColorDisplays: Set<CGDirectDisplayID>,
        masterEnabled: Bool
    ) -> Set<CGDirectDisplayID> {
        guard masterEnabled else { return [] }
        return allDisplayIDs.subtracting(desiredColorDisplays)
    }

    public static func action(
        currentlyVisible: Bool,
        shouldBeVisible: Bool
    ) -> OverlayVisibilityAction? {
        guard currentlyVisible != shouldBeVisible else { return nil }
        return shouldBeVisible ? .show : .hide
    }
}

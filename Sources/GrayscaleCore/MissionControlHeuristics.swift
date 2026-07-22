import CoreGraphics

public enum MissionControlHeuristics {
    public static func isOverviewWindow(
        ownerBundleIdentifier: String?,
        layer: Int,
        frame: CGRect,
        displays: [DisplayDescriptor]
    ) -> Bool {
        guard ownerBundleIdentifier == "com.apple.dock",
              (18 ... 20).contains(layer) else { return false }
        return displays.contains {
            FullscreenHeuristics.matchesDisplayBounds(
                frame,
                displayBounds: $0.frame,
                tolerance: 2
            )
        }
    }
}

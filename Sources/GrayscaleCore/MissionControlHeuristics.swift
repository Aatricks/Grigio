import CoreGraphics

public enum MissionControlHeuristics {
    public static func isOverviewWindow(
        ownerBundleIdentifier: String?,
        layer: Int,
        frame: CGRect,
        displays: [DisplayDescriptor]
    ) -> Bool {
        // Mission Control is presented by WindowManager's ExposeShieldWindow
        // (layer 19). The Dock also maps display-sized windows in this layer
        // range when it reveals over a fullscreen Space, so Dock windows
        // must not count.
        guard ownerBundleIdentifier == "com.apple.WindowManager",
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

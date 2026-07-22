import CoreGraphics

public enum FullscreenHeuristics {
    public static func matchesDisplayBounds(
        _ windowBounds: CGRect,
        displayBounds: CGRect,
        tolerance: CGFloat = 2
    ) -> Bool {
        abs(windowBounds.minX - displayBounds.minX) <= tolerance
            && abs(windowBounds.minY - displayBounds.minY) <= tolerance
            && abs(windowBounds.width - displayBounds.width) <= tolerance
            && abs(windowBounds.height - displayBounds.height) <= tolerance
    }

    public static func matchesFullscreenContentArea(
        _ windowBounds: CGRect,
        displayBounds: CGRect,
        maximumTopInset: CGFloat = 96,
        tolerance: CGFloat = 2
    ) -> Bool {
        let topInset = windowBounds.minY - displayBounds.minY
        return abs(windowBounds.minX - displayBounds.minX) <= tolerance
            && abs(windowBounds.maxX - displayBounds.maxX) <= tolerance
            && abs(windowBounds.maxY - displayBounds.maxY) <= tolerance
            && topInset >= -tolerance
            && topInset <= maximumTopInset
    }
}

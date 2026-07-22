import CoreGraphics

public enum DisplayAttribution {
    public static func displayID(
        for windowFrame: CGRect,
        among displays: [DisplayDescriptor]
    ) -> CGDirectDisplayID? {
        displays
            .map { display in
                (display.id, windowFrame.intersection(display.frame).area)
            }
            .filter { $0.1 > 0 }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}

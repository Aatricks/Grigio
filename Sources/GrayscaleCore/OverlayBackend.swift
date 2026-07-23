import AppKit
import QuartzCore

@MainActor
public final class BackdropOverlay {
    public let window: NSWindow
    public let backdropLayer: CALayer

    public var isVisible: Bool { window.isVisible }
    public var isGrayscaleActive: Bool { !backdropLayer.isHidden }

    public init(frame: CGRect, joinsAllSpaces: Bool = true) throws {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = joinsAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        PrivateAPIs.setValue(false, forPrivateKey: "shouldAutoFlattenLayerTree", on: window)
        PrivateAPIs.setValue(false, forPrivateKey: "canHostLayersInWindowServer", on: window)
        PrivateAPIs.setValue(true, forPrivateKey: "canHostLayersInWindowServer", on: window)

        let rootView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        rootView.wantsLayer = true
        rootView.layerContentsRedrawPolicy = .onSetNeedsDisplay

        let backdropLayer = try PrivateAPIs.makeBackdropLayer()
        backdropLayer.frame = rootView.bounds
        backdropLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdropLayer.allowsGroupOpacity = true
        backdropLayer.allowsEdgeAntialiasing = false
        backdropLayer.filters = [try PrivateAPIs.makeColorSaturateFilter(amount: 0)]
        rootView.layer?.addSublayer(backdropLayer)
        window.contentView = rootView

        self.window = window
        self.backdropLayer = backdropLayer
    }

    public func show() {
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }

    public func setGrayscaleActive(_ active: Bool) {
        if active {
            show()
        } else {
            hide()
        }
    }

    // Toggling the layer instead of the window keeps the overlay in the
    // window server, so grayscale can engage while Mission Control is up.
    public func setHostedGrayscaleActive(_ active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.isHidden = !active
        CATransaction.commit()
    }
}

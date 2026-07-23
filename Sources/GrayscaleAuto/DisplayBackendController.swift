import AppKit
import CoreGraphics
import GrayscaleCore
import OSLog

enum GrayscaleMode: String {
    case perDisplay = "Per-display overlay"
    case globalFallback = "Global fallback"
}

@MainActor
final class DisplayBackendController {
    private let logger = Logger(subsystem: "com.aatricks.grayscale-auto", category: "backend")
    private(set) var mode: GrayscaleMode
    private var overlays: [SpaceOverlayKey: BackdropOverlay] = [:]
    private var missionControlShields: [CGDirectDisplayID: BackdropOverlay] = [:]
    private var topology: [ManagedSpaceDescriptor] = []

    init() {
        let status = PrivateAPIs.probe()
        mode = status.backdropLayerAvailable
            && status.colorFilterAvailable
            && status.managedSpacesAvailable
            ? .perDisplay
            : .globalFallback
    }

    func synchronizeDisplays() {
        guard mode == .perDisplay else { return }
        _ = GlobalGrayscaleBackend.setGrayscale(false)
        do {
            try refreshTopology()
        } catch {
            switchToGlobalFallback(error)
        }
    }

    func apply(
        desiredColorSpaces: Set<SpaceOverlayKey>,
        playbackColorSpaces: Set<SpaceOverlayKey>,
        desiredColorDisplays: Set<CGDirectDisplayID>,
        masterEnabled: Bool,
        forceGrayscale: Bool
    ) {
        switch mode {
        case .perDisplay:
            // A fullscreen Space's bound overlay is not part of the scene
            // Mission Control presents, so an all-Spaces shield carries
            // grayscale for as long as Mission Control is up.
            for shield in missionControlShields.values {
                if !shield.isVisible { shield.show() }
                shield.setHostedGrayscaleActive(masterEnabled && forceGrayscale)
            }
            do {
                try refreshTopology()
            } catch {
                switchToGlobalFallback(error)
                _ = GlobalGrayscaleBackend.setGrayscale(
                    masterEnabled && (forceGrayscale || desiredColorDisplays.isEmpty)
                )
                return
            }
            let needed = SpaceOverlayVisibility.visibleOverlayKeys(
                topology: topology,
                desiredColorSpaces: desiredColorSpaces,
                playbackColorSpaces: playbackColorSpaces,
                masterEnabled: masterEnabled,
                forceGrayscale: forceGrayscale
            )
            for (key, overlay) in overlays {
                switch OverlayVisibility.action(
                    currentlyVisible: overlay.isVisible,
                    shouldBeVisible: needed.contains(key)
                ) {
                case .show: overlay.setGrayscaleActive(true)
                case .hide: overlay.setGrayscaleActive(false)
                case nil: break
                }
            }
        case .globalFallback:
            overlays.values.forEach { $0.hide() }
            _ = GlobalGrayscaleBackend.setGrayscale(
                masterEnabled && (forceGrayscale || desiredColorDisplays.isEmpty)
            )
        }
    }

    func tearDown() {
        overlays.values.forEach { $0.hide() }
        overlays.removeAll()
        missionControlShields.values.forEach { $0.hide() }
        missionControlShields.removeAll()
        topology.removeAll()
        _ = GlobalGrayscaleBackend.setGrayscale(false)
    }

    private func refreshTopology() throws {
        let screenPairs: [(CGDirectDisplayID, NSScreen)] = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (id.uint32Value, screen)
        }
        let screens = Dictionary(uniqueKeysWithValues: screenPairs)
        let observedTopology = ManagedSpaces.topology(for: Array(screens.keys))
        let topologyDisplayIDs = Set(observedTopology.map(\.displayID))
        guard !screens.isEmpty, topologyDisplayIDs == Set(screens.keys) else {
            throw NSError(
                domain: "com.aatricks.grayscale-auto.backend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Managed Space topology did not cover every display"]
            )
        }

        let knownKeys = Set(topology.map(\.key))
        let observedKeys = Set(observedTopology.map(\.key))

        if SpaceOverlayVisibility.requiresReconciliation(knownKeys: knownKeys, observedKeys: observedKeys)
            || Set(missionControlShields.keys) != Set(screens.keys) {
            for key in knownKeys.subtracting(observedKeys) {
                overlays.removeValue(forKey: key)?.hide()
            }

            for displayID in Set(missionControlShields.keys).subtracting(screens.keys) {
                missionControlShields.removeValue(forKey: displayID)?.hide()
            }
            for (displayID, screen) in screens where missionControlShields[displayID] == nil {
                let shield = try BackdropOverlay(frame: screen.frame, joinsAllSpaces: true)
                shield.setHostedGrayscaleActive(false)
                shield.show()
                missionControlShields[displayID] = shield
            }

            let allSpaceIDs = Set(observedTopology.map(\.spaceID))
            for space in observedTopology where overlays[space.key] == nil {
                guard let screen = screens[space.displayID] else { continue }
                let overlay = try BackdropOverlay(frame: screen.frame, joinsAllSpaces: false)
                ManagedSpaces.bind(
                    windowNumber: overlay.window.windowNumber,
                    to: space.spaceID,
                    knownSpaceIDs: allSpaceIDs
                )
                guard ManagedSpaces.spaceIDs(forWindowNumber: overlay.window.windowNumber) == [space.spaceID] else {
                    overlay.hide()
                    throw NSError(
                        domain: "com.aatricks.grayscale-auto.backend",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not bind overlay to Space \(space.spaceID)"]
                    )
                }
                overlay.show()
                overlays[space.key] = overlay
            }
        }

        topology = observedTopology
    }

    private func switchToGlobalFallback(_ error: Error) {
        logger.error("Overlay setup failed; switching to global fallback: \(String(describing: error), privacy: .public)")
        overlays.values.forEach { $0.hide() }
        overlays.removeAll()
        topology.removeAll()
        mode = .globalFallback
    }
}

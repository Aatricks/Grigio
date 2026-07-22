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
            try rebuildSpaceOverlays()
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
                shield.setGrayscaleActive(masterEnabled && forceGrayscale)
            }
            do {
                try updateCurrentSpaces()
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
                if !overlay.isVisible { overlay.show() }
                switch OverlayVisibility.action(
                    currentlyVisible: overlay.isGrayscaleActive,
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

    private func rebuildSpaceOverlays() throws {
        let screenPairs: [(CGDirectDisplayID, NSScreen)] = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (id.uint32Value, screen)
        }
        let screens = Dictionary(uniqueKeysWithValues: screenPairs)
        let nextTopology = ManagedSpaces.topology(for: Array(screens.keys))
        let topologyDisplayIDs = Set(nextTopology.map(\.displayID))
        guard !screens.isEmpty, topologyDisplayIDs == Set(screens.keys) else {
            throw NSError(
                domain: "com.aatricks.grayscale-auto.backend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Managed Space topology did not cover every display"]
            )
        }

        let nextKeys = Set(nextTopology.map(\.key))
        for key in Set(overlays.keys).subtracting(nextKeys) {
            overlays.removeValue(forKey: key)?.hide()
        }

        for displayID in Set(missionControlShields.keys).subtracting(screens.keys) {
            missionControlShields.removeValue(forKey: displayID)?.hide()
        }
        for (displayID, screen) in screens where missionControlShields[displayID] == nil {
            let shield = try BackdropOverlay(frame: screen.frame, joinsAllSpaces: true)
            shield.setGrayscaleActive(false)
            shield.show()
            missionControlShields[displayID] = shield
        }

        let allSpaceIDs = Set(nextTopology.map(\.spaceID))
        for space in nextTopology where overlays[space.key] == nil {
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
        topology = nextTopology
    }

    private func updateCurrentSpaces() throws {
        let displayIDs = Set(topology.map(\.displayID))
        guard !displayIDs.isEmpty else {
            try rebuildSpaceOverlays()
            return
        }
        let current = ManagedSpaces.currentSpaceIDs(for: Array(displayIDs))
        guard Set(current.keys) == displayIDs else {
            throw NSError(
                domain: "com.aatricks.grayscale-auto.backend",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not resolve every display's current Space"]
            )
        }
        let knownKeys = Set(topology.map(\.key))
        let currentKeys = Set(current.map { SpaceOverlayKey(displayID: $0.key, spaceID: $0.value) })
        guard currentKeys.isSubset(of: knownKeys) else {
            try rebuildSpaceOverlays()
            return
        }
        topology = topology.map { space in
            ManagedSpaceDescriptor(
                displayID: space.displayID,
                spaceID: space.spaceID,
                isCurrent: current[space.displayID] == space.spaceID,
                isFullscreenApplicationSpace: space.isFullscreenApplicationSpace
            )
        }
    }

    private func switchToGlobalFallback(_ error: Error) {
        logger.error("Overlay setup failed; switching to global fallback: \(String(describing: error), privacy: .public)")
        overlays.values.forEach { $0.hide() }
        overlays.removeAll()
        topology.removeAll()
        mode = .globalFallback
    }
}

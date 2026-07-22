import Foundation
import AppKit
import GrayscaleCore

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

let status = PrivateAPIs.probe()
expect(status.backdropLayerAvailable, "CABackdropLayer must exist on the current host")
expect(status.colorFilterAvailable, "CAFilter must exist on the current host")
expect(status.managedSpacesAvailable, "managed Space APIs must exist on the current host")

do {
    let filter = try PrivateAPIs.makeColorSaturateFilter(amount: 0)
    expect(filter.value(forKey: "inputAmount") as? Double == 0, "filter must store inputAmount = 0")
} catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: zero-saturation filter creation threw \(error)\n".utf8))
}

MainActor.assumeIsolated {
    do {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let overlay = try BackdropOverlay(frame: frame)
        expect(overlay.window.frame == frame, "overlay window must match its display frame")
        expect(overlay.window.ignoresMouseEvents, "overlay must ignore mouse events")
        expect(overlay.window.collectionBehavior.contains(.canJoinAllSpaces), "overlay must join all Spaces")
        expect(overlay.window.collectionBehavior.contains(.fullScreenAuxiliary), "overlay must accompany fullscreen Spaces")
        expect(overlay.window.collectionBehavior.contains(.stationary), "overlay must remain stationary")
        expect(NSStringFromClass(type(of: overlay.backdropLayer)).contains("CABackdropLayer"), "overlay must host CABackdropLayer")
        expect(overlay.backdropLayer.filters?.count == 1, "overlay must install exactly one filter")
        overlay.show()
        expect(overlay.isVisible, "show must make the overlay visible")
        overlay.hide()
        expect(!overlay.isVisible, "hide must make the overlay invisible")
        expect(overlay.isGrayscaleActive, "a new overlay must start with grayscale active")
        overlay.show()
        overlay.setGrayscaleActive(false)
        expect(overlay.backdropLayer.isHidden, "deactivating grayscale must hide the backdrop layer")
        expect(overlay.isVisible, "deactivating grayscale must keep the overlay window ordered in")
        overlay.setGrayscaleActive(true)
        expect(overlay.isGrayscaleActive, "reactivating grayscale must unhide the backdrop layer")
        overlay.hide()
        let spaceBoundOverlay = try BackdropOverlay(frame: frame, joinsAllSpaces: false)
        expect(
            !spaceBoundOverlay.window.collectionBehavior.contains(.canJoinAllSpaces),
            "a Space-bound overlay must not be replicated to every Space"
        )
        expect(
            spaceBoundOverlay.window.collectionBehavior.contains(.fullScreenAuxiliary),
            "a Space-bound overlay must be allowed in fullscreen Spaces"
        )
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: backdrop overlay creation threw \(error)\n".utf8))
    }
}

let leftDisplay = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
let rightDisplay = DisplayDescriptor(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
let displays = [leftDisplay, rightDisplay]

expect(
    DisplayAttribution.displayID(
        for: CGRect(x: 1800, y: 100, width: 500, height: 800),
        among: displays
    ) == 2,
    "window must map to the display with the greatest intersection"
)
expect(
    DisplayAttribution.displayID(
        for: CGRect(x: -1000, y: -1000, width: 100, height: 100),
        among: displays
    ) == nil,
    "non-overlapping window must not map to a display"
)

let fullscreenOnRight = WindowCandidate(
    ownerPID: 42,
    frame: rightDisplay.frame,
    isFullscreen: true
)
let windowedOnLeft = WindowCandidate(
    ownerPID: 42,
    frame: CGRect(x: 10, y: 10, width: 800, height: 600),
    isFullscreen: false
)
let ignoredFullscreen = WindowCandidate(
    ownerPID: 99,
    frame: leftDisplay.frame,
    isFullscreen: true
)

let desired = Reconciler.desiredColorDisplays(
    masterEnabled: true,
    displays: displays,
    allowlistedPIDs: [42],
    windows: [fullscreenOnRight, windowedOnLeft, ignoredFullscreen]
)
expect(desired == [2], "only an allowlisted fullscreen window's display must receive color")

let desiredSpaces = Reconciler.desiredColorSpaces(
    masterEnabled: true,
    displays: displays,
    allowlistedPIDs: [42],
    windows: [
        WindowCandidate(
            ownerPID: 42,
            frame: rightDisplay.frame,
            isFullscreen: true,
            spaceIDs: [21]
        ),
        WindowCandidate(
            ownerPID: 99,
            frame: leftDisplay.frame,
            isFullscreen: true,
            spaceIDs: [10]
        ),
    ]
)
expect(
    desiredSpaces == [SpaceOverlayKey(displayID: 2, spaceID: 21)],
    "color permission must retain the qualifying fullscreen window's Space"
)

let disabledDesired = Reconciler.desiredColorDisplays(
    masterEnabled: false,
    displays: displays,
    allowlistedPIDs: [42],
    windows: [fullscreenOnRight]
)
expect(disabledDesired == [1, 2], "master disable must restore color to every display")

let windowedPlayer = WindowCandidate(
    ownerPID: 42,
    frame: CGRect(x: 30, y: 30, width: 900, height: 700),
    isFullscreen: false,
    spaceIDs: [10]
)
expect(
    Reconciler.playbackColorSpaces(
        masterEnabled: true,
        displays: displays,
        activePlaybackPIDs: [42],
        windows: [windowedPlayer]
    ) == [SpaceOverlayKey(displayID: 1, spaceID: 10)],
    "an actively playing windowed player must color its own Space"
)
expect(
    Reconciler.playbackColorSpaces(
        masterEnabled: true,
        displays: displays,
        activePlaybackPIDs: [],
        windows: [windowedPlayer]
    ).isEmpty,
    "a player that is not actively playing must not color any Space"
)
expect(
    Reconciler.playbackColorDisplays(
        masterEnabled: true,
        displays: displays,
        activePlaybackPIDs: [42],
        windows: [windowedPlayer]
    ) == [1],
    "active playback must color the display the player window sits on"
)
expect(
    Reconciler.playbackColorSpaces(
        masterEnabled: false,
        displays: displays,
        activePlaybackPIDs: [42],
        windows: [windowedPlayer]
    ).isEmpty,
    "master disable must not compute playback color Spaces"
)

let suiteName = "com.aatricks.grayscale-auto.contract.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
let allowlist = AllowlistStore(defaults: defaults)
expect(allowlist.isEnabled(identifier: "com.colliderli.iina"), "IINA must be enabled by default")
expect(allowlist.isEnabled(identifier: "io.mpv"), "mpv must be enabled by default")
expect(allowlist.isEnabled(identifier: "org.videolan.vlc"), "VLC must be enabled by default")
expect(allowlist.isEnabled(identifier: "com.apple.QuickTimePlayerX"), "QuickTime Player must be enabled by default")
expect(!allowlist.isEnabled(identifier: "com.apple.Safari"), "Safari must be disabled by default")
allowlist.setEnabled(true, identifier: "com.apple.Safari", displayName: "Safari")
expect(AllowlistStore(defaults: defaults).isEnabled(identifier: "com.apple.Safari"), "allowlist edits must persist")

expect(
    OverlayVisibility.displayIDsNeedingOverlay(
        allDisplayIDs: [1, 2],
        desiredColorDisplays: [2],
        masterEnabled: true
    ) == [1],
    "only displays not granted color must retain overlays"
)
expect(
    OverlayVisibility.displayIDsNeedingOverlay(
        allDisplayIDs: [1, 2],
        desiredColorDisplays: [],
        masterEnabled: false
    ).isEmpty,
    "master disable must hide every overlay"
)
expect(GlobalGrayscaleBackend.isAvailable, "global grayscale fallback symbols must exist on the current host")
expect(
    FullscreenHeuristics.matchesDisplayBounds(
        CGRect(x: 1920.5, y: 0.5, width: 2559, height: 1439),
        displayBounds: rightDisplay.frame,
        tolerance: 2
    ),
    "subpixel-rounded fullscreen bounds must match a display"
)
expect(
    !FullscreenHeuristics.matchesDisplayBounds(
        CGRect(x: 1940, y: 20, width: 2520, height: 1400),
        displayBounds: rightDisplay.frame,
        tolerance: 2
    ),
    "materially inset window bounds must not count as fullscreen"
)
expect(
    FullscreenHeuristics.matchesFullscreenContentArea(
        CGRect(x: 1920, y: 33, width: 2560, height: 1407),
        displayBounds: rightDisplay.frame,
        maximumTopInset: 96,
        tolerance: 2
    ),
    "native fullscreen content with a top safe-area inset must match its display"
)
expect(
    !FullscreenHeuristics.matchesFullscreenContentArea(
        CGRect(x: 1928, y: 41, width: 2544, height: 1391),
        displayBounds: rightDisplay.frame,
        maximumTopInset: 96,
        tolerance: 2
    ),
    "a Fill/zoomed window with side and bottom insets must not count as fullscreen"
)
expect(
    OverlayVisibility.action(currentlyVisible: true, shouldBeVisible: true) == nil,
    "an already-correct visible overlay must not be reordered"
)
expect(
    OverlayVisibility.action(currentlyVisible: false, shouldBeVisible: false) == nil,
    "an already-correct hidden overlay must not be ordered out again"
)
expect(
    OverlayVisibility.action(currentlyVisible: false, shouldBeVisible: true) == .show,
    "a newly-required overlay must be shown"
)
expect(
    OverlayVisibility.action(currentlyVisible: true, shouldBeVisible: false) == .hide,
    "an overlay no longer required must be hidden"
)

let spaceTopology = [
    ManagedSpaceDescriptor(
        displayID: 1,
        spaceID: 10,
        isCurrent: true,
        isFullscreenApplicationSpace: true
    ),
    ManagedSpaceDescriptor(displayID: 1, spaceID: 11, isCurrent: false),
    ManagedSpaceDescriptor(displayID: 2, spaceID: 20, isCurrent: true),
    ManagedSpaceDescriptor(displayID: 2, spaceID: 21, isCurrent: false),
]
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: spaceTopology,
        desiredColorSpaces: [],
        masterEnabled: true
    ) == Set(spaceTopology.map(\.key)),
    "grayscale-by-default must keep an overlay visible on every Space"
)
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: spaceTopology,
        desiredColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: true
    ) == [
        SpaceOverlayKey(displayID: 1, spaceID: 11),
        SpaceOverlayKey(displayID: 2, spaceID: 20),
        SpaceOverlayKey(displayID: 2, spaceID: 21),
    ],
    "color must hide only the qualifying fullscreen window's Space overlay"
)
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: spaceTopology,
        desiredColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: false
    ).isEmpty,
    "master disable must hide every Space-bound overlay"
)
let switchedSpaceTopology = [
    ManagedSpaceDescriptor(
        displayID: 1,
        spaceID: 10,
        isCurrent: false,
        isFullscreenApplicationSpace: true
    ),
    ManagedSpaceDescriptor(displayID: 1, spaceID: 11, isCurrent: true),
    ManagedSpaceDescriptor(displayID: 2, spaceID: 20, isCurrent: true),
    ManagedSpaceDescriptor(displayID: 2, spaceID: 21, isCurrent: false),
]
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: switchedSpaceTopology,
        desiredColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: true
    ) == [
        SpaceOverlayKey(displayID: 1, spaceID: 11),
        SpaceOverlayKey(displayID: 2, spaceID: 20),
        SpaceOverlayKey(displayID: 2, spaceID: 21),
    ],
    "a stale fullscreen observation must hide only its own Space overlay"
)
let mixedSpaceTopology = [
    ManagedSpaceDescriptor(
        displayID: 1,
        spaceID: 10,
        isCurrent: true,
        isFullscreenApplicationSpace: false
    ),
    ManagedSpaceDescriptor(
        displayID: 1,
        spaceID: 11,
        isCurrent: false,
        isFullscreenApplicationSpace: true
    ),
]
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: mixedSpaceTopology,
        desiredColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: true,
        forceGrayscale: false
    ) == Set(mixedSpaceTopology.map(\.key)),
    "a window moved onto a desktop Space must not grant that Space color"
)
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: mixedSpaceTopology,
        desiredColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 11)],
        masterEnabled: true,
        forceGrayscale: true
    ) == Set(mixedSpaceTopology.map(\.key)),
    "Mission Control must keep every Space overlay visible"
)
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: mixedSpaceTopology,
        desiredColorSpaces: [],
        playbackColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: true,
        forceGrayscale: false
    ) == [SpaceOverlayKey(displayID: 1, spaceID: 11)],
    "active playback must color its desktop Space even though it is not a fullscreen Space"
)
expect(
    SpaceOverlayVisibility.visibleOverlayKeys(
        topology: mixedSpaceTopology,
        desiredColorSpaces: [],
        playbackColorSpaces: [SpaceOverlayKey(displayID: 1, spaceID: 10)],
        masterEnabled: true,
        forceGrayscale: true
    ) == Set(mixedSpaceTopology.map(\.key)),
    "Mission Control must override playback color and keep every Space gray"
)
expect(
    MissionControlHeuristics.isOverviewWindow(
        ownerBundleIdentifier: "com.apple.WindowManager",
        layer: 19,
        frame: leftDisplay.frame,
        displays: displays
    ),
    "an on-screen WindowManager Exposé shield must identify Mission Control"
)
expect(
    !MissionControlHeuristics.isOverviewWindow(
        ownerBundleIdentifier: "com.apple.WindowManager",
        layer: 17,
        frame: leftDisplay.frame,
        displays: displays
    ),
    "an ordinary WindowManager layer must not identify Mission Control"
)
expect(
    !MissionControlHeuristics.isOverviewWindow(
        ownerBundleIdentifier: "com.apple.dock",
        layer: 20,
        frame: leftDisplay.frame,
        displays: displays
    ),
    "the Dock revealing over a fullscreen Space must not identify Mission Control"
)
let rawManagedSpaces: [[String: Any]] = [[
    "Display Identifier": "display-a",
    "Current Space": ["ManagedSpaceID": NSNumber(value: 11)],
    "Spaces": [
        ["ManagedSpaceID": NSNumber(value: 10), "type": NSNumber(value: 0)],
        ["ManagedSpaceID": NSNumber(value: 11), "type": NSNumber(value: 4)],
    ],
]]
expect(
    ManagedSpaceTopologyParser.parse(
        rawManagedSpaces,
        displayIDsByUUID: ["display-a": 1]
    ) == [
        ManagedSpaceDescriptor(
            displayID: 1,
            spaceID: 10,
            isCurrent: false,
            isFullscreenApplicationSpace: false
        ),
        ManagedSpaceDescriptor(
            displayID: 1,
            spaceID: 11,
            isCurrent: true,
            isFullscreenApplicationSpace: true
        ),
    ],
    "managed display dictionaries must map every Space and identify the current one"
)
let hostSpaceTopology = ManagedSpaces.topology(for: [CGMainDisplayID()])
expect(!hostSpaceTopology.isEmpty, "the host display must expose managed Spaces")
expect(hostSpaceTopology.contains(where: \.isCurrent), "the host topology must identify a current Space")
expect(
    ManagedSpaces.currentSpaceIDs(for: [CGMainDisplayID()])[CGMainDisplayID()]
        == hostSpaceTopology.first(where: \.isCurrent)?.spaceID,
    "the cheap current-Space query must agree with the full topology"
)
MainActor.assumeIsolated {
    if let targetSpace = hostSpaceTopology.first {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 20, height: 20),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        ManagedSpaces.bind(
            windowNumber: window.windowNumber,
            to: targetSpace.spaceID,
            knownSpaceIDs: Set(hostSpaceTopology.map(\.spaceID))
        )
        expect(
            ManagedSpaces.spaceIDs(forWindowNumber: window.windowNumber) == [targetSpace.spaceID],
            "a Space-bound window must belong exclusively to its target Space"
        )
        window.orderOut(nil)
    }
}

// Test PlaybackTracker contract
do {
    var tracker = PlaybackTracker()
    let now: TimeInterval = 1000.0
    let allowlisted: Set<pid_t> = [100, 101]

    // 1. Immediate activation on positive playback observations
    let active1 = tracker.update(allowlistedPIDs: allowlisted, observation: [100], now: now)
    expect(active1 == [100], "immediate activation for pid 100")

    // 2. Retention on an empty observation (for less than 2.0s)
    let active2 = tracker.update(allowlistedPIDs: allowlisted, observation: [], now: now + 1.0)
    expect(active2 == [100], "retention on empty observation at 1.0s")

    // 3. Retention on nil/unknown observation (for less than 2.0s)
    let active3 = tracker.update(allowlistedPIDs: allowlisted, observation: nil, now: now + 1.5)
    expect(active3 == [100], "retention on nil/unknown observation at 1.5s")

    // 4. Exact expiry at 2.0 seconds
    let active4 = tracker.update(allowlistedPIDs: allowlisted, observation: [], now: now + 2.0)
    expect(active4 == [], "exact expiry at 2.0s")

    // 5. Immediate removal when no longer allowlisted
    _ = tracker.update(allowlistedPIDs: allowlisted, observation: [100], now: now + 3.0)
    let active5 = tracker.update(allowlistedPIDs: [101], observation: [], now: now + 3.1)
    expect(active5 == [], "immediate removal when no longer allowlisted")

    // 6. Immediate reacquisition
    let active6 = tracker.update(allowlistedPIDs: [100], observation: [100], now: now + 4.0)
    expect(active6 == [100], "immediate reacquisition on new positive observation")

    // 7. Immediate reacquisition / refresh at exact 2.0s expiry boundary
    let active7 = tracker.update(allowlistedPIDs: [100], observation: [100], now: now + 6.0)
    expect(active7 == [100], "immediate reacquisition at 2.0s expiry boundary")
    let active8 = tracker.update(allowlistedPIDs: [100], observation: [], now: now + 8.0)
    expect(active8 == [], "exact expiry 2.0s after boundary reacquisition")
}

if failures > 0 {
    exit(1)
}

print("PASS: private API contract")

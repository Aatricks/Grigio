# grayscale-auto Design

## Goal

Build a menu-bar-only macOS utility that keeps every display grayscale and grants color only to a display currently showing a fullscreen window from an allowlisted application.

## Delivery gate

The first deliverable is a standalone overlay spike. On the current macOS 27.0 host it must prove that a private `CABackdropLayer` plus `CAFilter(type: "colorSaturate")` can sample other applications, desaturate a fullscreen Space, remain above fullscreen content, and idle below the requested resource thresholds. If this gate fails, the production application uses only the global `CGDisplayForceToGray` backend. The system Accessibility Color Filter is never used.

## Architecture

The Swift package contains a reusable `GrayscaleCore` library, an `OverlaySpike` executable, and the `grayscale-auto` executable. `GrayscaleCore` owns display geometry, desired-state reconciliation, allowlist persistence, fullscreen discovery, and backend protocols. AppKit-specific adapters own Accessibility observers, workspace/display lifecycle notifications, overlay windows, the global private API, and the status menu.

The reconciler is the only writer of `desiredColorDisplays`. Event callbacks request a reconcile with a reason; they never directly toggle displays. In per-display mode, a separate overlay is bound exclusively to every managed Space on every display. All overlays remain visible by default; granting color hides only the overlay for the qualifying display's current Space. This preserves grayscale throughout WindowServer's Space-switch animation instead of reacting after the animation completes. In fallback mode, grayscale is disabled globally if any qualifying fullscreen window exists because the private global API cannot grant color to one display.

## Detection and attribution

Accessibility observers provide the low-latency signal for allowlisted running applications. Each reconcile also reads current AX windows and maps fullscreen frames to displays using maximum intersection area with a display frame. Active Space, application activation/termination, display changes, wake, unlock, and a one-second watchdog all trigger full reconciliation. The watchdog uses `CGWindowListCopyWindowInfo`, compares owner PID and bounds only, and never reads window names or titles.

## App lifecycle and UI

The application is an `LSUIElement` status item with master enable, mode display, allowlist editing from running applications, browser toggles, Launch at Login using `SMAppService.mainApp`, and Quit. Disabling or quitting tears down overlays and leaves the screen in color. Signal and `atexit` cleanup are best-effort supplements to normal termination.

## Packaging

SwiftPM builds from the command line. `make bundle` assembles `build/grayscale-auto.app`, installs an external `Info.plist`, and ad-hoc signs the bundle with the stable identifier `com.aatricks.grayscale-auto`. No third-party dependencies are used.

## Verification

Pure logic is unit-tested with Swift Testing/XCTest-compatible SwiftPM tests. Runtime diagnostics report private-class availability, overlay creation, state transitions, and process resource samples. The mandatory fullscreen/z-order/sampling and steady-state GPU checks are empirical gates and are reported separately from compiler/test results.

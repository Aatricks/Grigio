# grayscale-auto Implementation Plan

Tasks use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a macOS menu-bar grayscale manager with a gated per-display private-overlay backend and global private-API fallback.

**Architecture:** A SwiftPM core library isolates deterministic state and geometry from AppKit adapters. All event sources feed one reconciler; display backends render the resulting desired-color set. A standalone overlay spike gates the production backend selection.

**Tech Stack:** Swift 6.4 compiler in Swift 5 language mode, AppKit, ApplicationServices, QuartzCore, ServiceManagement, OSLog, SwiftPM, Make.

**Project constraints:** Use the overlay backend when available. Do not use the system Accessibility Color Filter.

---

### Task 1: Package contract and overlay spike

**Goal:** Produce a signed standalone spike whose diagnostics and screenshots can prove or disprove backdrop desaturation on macOS 27.0.

**Files:** `Package.swift`, `Sources/GrayscaleCore/PrivateAPIs.swift`, `Sources/GrayscaleCore/OverlayBackend.swift`, `Sources/OverlaySpike/main.swift`, `Tests/GrayscaleCoreTests/PrivateAPITests.swift`, `Makefile`, `Resources/Info.plist`.

**Acceptance Criteria:**

- [ ] `swift test` observes tests fail before the missing implementation and pass after it.
- [ ] `make spike-bundle` creates and ad-hoc signs a runnable `.app`.
- [ ] Runtime diagnostics distinguish unavailable private classes, filter creation failure, and overlay creation failure.
- [ ] A screenshot comparison shows colorful content becomes grayscale while the overlay is visible and returns to color when hidden.
- [ ] A fullscreen application remains grayscale with the overlay enabled.
- [ ] Idle CPU is below 1%; GPU measurement is recorded when host privileges permit it.

**Verify:** `swift test && make spike-bundle && codesign --verify --deep --strict build/OverlaySpike.app`; then run the documented visual/resource diagnostic.

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

### Task 2: Deterministic state and display attribution

**Goal:** Implement allowlist defaults, window-to-display attribution, and pure desired-color reconciliation.

**Files:** `Sources/GrayscaleCore/Models.swift`, `Sources/GrayscaleCore/DisplayAttribution.swift`, `Sources/GrayscaleCore/Reconciler.swift`, `Sources/GrayscaleCore/AllowlistStore.swift`, corresponding files under `Tests/GrayscaleCoreTests/`.

**Acceptance Criteria:**

- [ ] Default allowlist enables IINA, mpv, VLC, and QuickTime Player and disables browsers.
- [ ] Fullscreen frames map to the display with the largest intersection and reject non-overlapping frames.
- [ ] Per-display mode returns only qualifying display IDs; fallback mode exposes global color if any qualifying fullscreen window exists.
- [ ] Master disable always requests color everywhere.

**Verify:** `swift test --filter GrayscaleCoreTests` reports zero failures.

### Task 3: Accessibility and watchdog detection

**Goal:** Produce event-driven fullscreen discovery corrected by a one-second window-list watchdog.

**Files:** `Sources/GrayscaleAuto/AccessibilityMonitor.swift`, `Sources/GrayscaleAuto/WindowSnapshotProvider.swift`, `Sources/GrayscaleAuto/LifecycleMonitor.swift`, `Sources/GrayscaleAuto/AppController.swift`.

**Acceptance Criteria:**

- [ ] First launch requests Accessibility trust.
- [ ] Allowlisted processes receive AX observers for fullscreen, window-created, and element-destroyed changes.
- [ ] Watchdog snapshots use owner PID and bounds without reading titles.
- [ ] Space, activation, termination, display, wake, and unlock events request a full reconcile.

**Verify:** `swift build` succeeds and structured logs show each injected/event trigger reaches the reconciler.

### Task 4: Production backends, status menu, and lifecycle

**Goal:** Assemble the menu-bar application with pure backend application, persistence, login-item control, and safe teardown.

**Files:** `Sources/GrayscaleAuto/main.swift`, `Sources/GrayscaleAuto/MenuController.swift`, `Sources/GrayscaleAuto/DisplayBackendController.swift`, `Sources/GrayscaleCore/GlobalGrayscaleBackend.swift`, `Resources/Info.plist`, `Makefile`.

**Acceptance Criteria:**

- [ ] One exclusively bound overlay exists per managed Space on every active display, and visibility is a pure function of desired color state plus the current Space.
- [ ] Global mode uses only `CGDisplayForceToGray` and reports its lack of per-display granularity.
- [ ] Menu supports master enable, mode, allowlist additions/toggles, Launch at Login, and Quit.
- [ ] Normal disable and quit restore color and remove overlays.
- [ ] `make bundle` produces a signed `LSUIElement` app with stable bundle identifier.

**Verify:** `swift test && make clean bundle && codesign --verify --deep --strict build/grayscale-auto.app` exits successfully.

### Task 5: End-to-end acceptance run

**Goal:** Capture enter/exit/Space latency, second-display isolation, watchdog recovery, hotplug/wake behavior, and idle resource evidence against the user thresholds.

**Files:** `scripts/runtime-check.sh`, `README.md`.

**Acceptance Criteria:**

- [ ] Fullscreen entry grants color on only the target display within 500 ms.
- [ ] Fullscreen exit or Space change re-grays within 200 ms.
- [ ] Thirty minutes of switching produces no stuck state.
- [ ] Display hotplug, sleep/wake, and lock/unlock reconcile without desynchronization.
- [ ] Idle CPU is below 1% and steady-state GPU cost is not measurable with the available host tooling.

**Verify:** Follow `README.md` runtime procedure and retain timestamped logs plus resource samples.

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

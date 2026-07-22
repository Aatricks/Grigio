# Grigio

Grigio is a small macOS menu bar app that keeps your displays in grayscale. When an app on the allowlist enters native fullscreen, Grigio restores color on that display. The other displays and Spaces stay gray.

IINA, mpv, VLC, and QuickTime Player are enabled by default. Browsers are included in the settings but start disabled.

## How it works

Grigio puts a private `CABackdropLayer` and `CAFilter` overlay in each managed Space. A fullscreen window can hide only the overlay in its own Space. This matters in Mission Control, where macOS may report windows from several Spaces as onscreen at the same time. If the per-display APIs are unavailable, the app falls back to `CGDisplayForceToGray`. The fallback affects every display at once, and the menu shows when it is active.

This relies on undocumented macOS APIs. An OS update may break it, and it cannot be distributed through the Mac App Store. Grigio does not use the system Accessibility Color Filter.

## Requirements

- macOS 14 or newer
- Swift 5.10 or newer
- Xcode or the Command Line Tools

## Build

```sh
make test
make bundle
open build/grayscale-auto.app
```

The app bundle is written to `build/grayscale-auto.app` and ad hoc signed with the bundle identifier `com.aatricks.grayscale-auto`.

On first launch, allow Grigio in System Settings > Privacy & Security > Accessibility. It can still detect fullscreen windows with a one-second polling fallback, but Accessibility permission makes the response much faster. macOS may forget the permission after a rebuild because the ad hoc signature changes. If that happens, toggle the permission off and back on.

Make sure the system grayscale filter is off in System Settings > Accessibility > Display > Color Filters. WindowServer applies that filter after Grigio's overlay, so Grigio cannot restore color while the system filter is enabled.

## Menu

The menu bar item lets you:

- turn grayscale on or off
- see whether the per-display backend or global fallback is active
- add running apps to the allowlist
- enable or disable saved apps and browsers
- launch Grigio at login
- quit and restore color

Grigio only treats native macOS fullscreen as fullscreen. Zoomed and Fill windows stay gray.

## Testing the overlay

There is a standalone test app for the overlay backend:

```sh
make spike-bundle
open build/OverlaySpike.app
```

On the macOS 27.0 machine used during development, the overlay worked over other apps and fullscreen Spaces, restored color when hidden, and settled at 0% CPU. `powermetrics` needed an administrator password, so GPU activity was checked with `ioreg` instead. Neither the enabled nor disabled overlay showed sustained GPU use.

For a longer runtime check, run:

```sh
scripts/runtime-check.sh 60
```

The script saves CPU samples and transition logs in `build/evidence/`. Change `60` to `1800` for a 30-minute run. A full manual test should cover fullscreen entry and exit, Space switching, display hotplug, sleep and wake, and lock and unlock. Multi-display testing should confirm that color returns only on the display with the allowlisted fullscreen app.

# Architecture

## Stages

1. Native brightness API core
2. CLI diagnostics
3. Background macOS app shell
4. F1/F2 brightness key interception
5. Pointer display routing
6. Settings home window
7. Launch-at-login and optional menu bar item
8. GitHub Actions build, test, package, and release flow
9. Sparkle self-update support

## Runtime Components

- `BrightHereCore`
  - display enumeration
  - pointer-to-display selection
  - native brightness read/write
  - brightness step logic
  - hotkey event decoding
  - settings persistence

- `BrightHereApp`
  - background app lifecycle
  - event tap
  - settings window
  - menu bar item
  - launch-at-login integration
  - Sparkle update entry point

- `BrightHereCLI`
  - list, diagnose, and set brightness commands for support and testing

## Brightness Policy

Only native display brightness APIs are used. Bright Here does not implement visual dimming layers, gamma table edits, color filters, or other apparent-brightness workarounds.

## Permissions

Intercepting F1/F2 requires macOS Accessibility permission for the event tap. The app prompts by opening the Accessibility settings pane when permission is missing.

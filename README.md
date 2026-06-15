# Bright Here

Bright Here routes the Mac brightness keys to the display under the pointer.

It is a lightweight native macOS app:

- no Dock presence while running
- optional menu bar icon
- no display filtering, dimming overlays, gamma tricks, or grayscale workarounds
- native brightness APIs only: `DisplayServices` first, `CoreDisplay` fallback
- F1/F2 brightness keys are intercepted and applied to the pointer's current display

## Build

```sh
swift build -c release
```

## Run the app during development

```sh
swift run bright-here --show-settings
```

The production app normally runs in the background. `--show-settings` opens the settings window during development.

## Pointer Debugging

Open the settings window and click **Open Debug Panel**. The panel shows:

- current pointer location from `CGEvent`
- current pointer location from `NSEvent`
- selected display id and bounds
- all active displays and whether each contains the pointer
- test brightness buttons for the currently selected display

The production F1/F2 routing uses `CGEvent(source: nil)?.location` at keypress time instead of the keyboard event's own location.

## CLI diagnostics

```sh
swift run bright-here-cli list
swift run bright-here-cli diagnose
swift run bright-here-cli set 1 0.55
swift run bright-here-cli set id:1 0.50
```

## Test

```sh
swift test
```

The automated tests cover:

- pointer-to-display selection
- pointer-based brightness routing
- brightness step clamping
- brightness write-through behavior using a fake controller
- F1/F2 system-defined event decoding
- settings defaults and persistence
- issue URL/report generation
- log file append and rotation

## Logs and Issue Reports

Runtime logs are written to:

```text
~/Library/Logs/Bright Here/bright-here.log
```

The settings window's **It's not working** button opens a prefilled GitHub issue and copies a fuller Markdown debug report to the clipboard. Paste that report into the issue description if the prefilled text is not enough.

## Package

```sh
bash Scripts/package_app.sh
```

This creates:

```text
release/Bright Here.app
release/BrightHere-<version>.zip
```

The script ad-hoc signs locally by default. CI can use `SIGN_IDENTITY` and Apple notarization secrets when configured.

## GitHub Release Automation

CI runs on `dev`, `main`, and PRs into `main`.

Release automation runs on pushes to `main`:

1. resolve packages
2. run tests
3. package the app
4. notarize if Apple credentials are configured
5. create a GitHub Release for `v$(cat VERSION)` if that tag does not already exist

## Sparkle Stage 9

Sparkle is intentionally stage 9. The app links Sparkle and exposes a Check for Updates action. The checked-in app contains the public EDDSA key; release automation signs the appcast with the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

```sh
Scripts/generate_appcast.sh
```

Before public release, publish the generated `appcast.xml` at the URL in `SUFeedURL`.

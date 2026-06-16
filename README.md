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

The settings window's **It's not working** button opens a prefilled GitHub issue and copies environment details plus recent `ERROR` log lines to the clipboard as a fenced text block. Paste that block into the issue's final section if available.

## Package

```sh
bash Scripts/package_app.sh
bash Scripts/create_dmg.sh
```

This creates:

```text
release/Bright Here.app
release/BrightHere-<version>.zip
release/BrightHere-<version>.dmg
```

The zip is used for Sparkle updates. The DMG is the recommended user-facing installer: open it and drag `Bright Here.app` to Applications. The scripts automatically use the stable self-signed identity when it exists in Keychain, or fall back to ad-hoc signing. CI can use `SIGN_IDENTITY`, `SIGNING_CERTIFICATE_P12_BASE64`, and Apple notarization secrets when configured.

## Stable Self-Signed Signing

For early distribution without a Developer ID certificate, create one stable local code signing identity and reuse it for every build:

```sh
bash Scripts/create_self_signed_identity.sh
bash Scripts/package_app.sh
bash Scripts/create_dmg.sh
```

The default identity name is:

```text
Bright Here Self-Signed Code Signing
```

`package_app.sh` and `create_dmg.sh` automatically use that identity when it exists in Keychain. If it is missing, they fall back to ad-hoc signing.

The script also writes a reusable `.p12` and password under `.build/signing/`. Keep both files private.

To use the same self-signed identity in GitHub Actions releases:

```sh
bash Scripts/create_self_signed_identity.sh
base64 -i .build/signing/bright-here-signing.p12 | pbcopy
```

Then add these GitHub Secrets:

- `SIGNING_CERTIFICATE_P12_BASE64`: the copied base64 text
- `SIGNING_CERTIFICATE_PASSWORD`: the contents of `.build/signing/bright-here-signing.password`
- `SIGN_IDENTITY`: `Bright Here Self-Signed Code Signing`

Keep the `.p12` and password private. Recreating the certificate changes the app's signing identity and may require users to grant Accessibility permission again.

## GitHub Release Automation

CI runs on `dev`, `main`, and PRs into `main`.

Release automation runs on pushes to `main`:

1. resolve packages
2. run tests
3. package the app
4. notarize the zip if Apple credentials are configured
5. generate the Sparkle appcast
6. create and optionally notarize the DMG
7. create a GitHub Release for `v$(cat VERSION)` if that tag does not already exist

## Sparkle Stage 9

Sparkle is intentionally stage 9. The app links Sparkle and exposes a Check for Updates action. The checked-in app contains the public EDDSA key; release automation signs the appcast with the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

```sh
Scripts/generate_appcast.sh
```

Before public release, publish the generated `appcast.xml` at the URL in `SUFeedURL`.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/bright-here-icon-dark.png">
    <img src="docs/assets/bright-here-icon.png" alt="Bright Here icon" width="128" height="128">
  </picture>
</p>

<h1 align="center">Bright Here</h1>

<p align="center">Your brightness follows your cursor.</p>

Bright Here makes your Mac's F1/F2 brightness keys adjust the display under your cursor. It runs quietly in the background, does not stay in the Dock, and uses native display brightness APIs rather than dimming overlays or color filters.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/a1exsun/bright-here/releases/latest), open it, then drag **Bright Here.app** to **Applications**.

On first launch, macOS may ask you to confirm opening the app. Bright Here also needs Accessibility permission so it can intercept F1/F2 and route those key presses to the right display.

## Use

1. Launch **Bright Here**.
2. Grant Accessibility permission if prompted.
3. Move your cursor to a display.
4. Press F1 or F2.

The brightness change applies to the display under your cursor. You can reopen Bright Here from Applications, Launchpad, Spotlight, or the menu bar icon if enabled.

## Settings

Bright Here includes a small settings window for:

- showing or hiding the brightness overlay
- enabling or disabling automatic updates
- launching at login
- showing or hiding the menu bar icon
- changing the brightness step size
- checking for updates
- reporting an issue

If the menu bar icon is hidden, Bright Here still runs in the background. Launch the app again to reopen settings or quit.

## Troubleshooting

If F1/F2 still adjusts the built-in display, open Bright Here and check whether Accessibility permission is required. If the app is not working as expected, click **It's not working** in the settings window to open a GitHub issue with helpful diagnostic details.

## Privacy

Bright Here does not collect analytics. It only checks your cursor position locally when F1/F2 is pressed and writes local logs for troubleshooting.

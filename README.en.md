# AltWindow 1.00

[日本語](README.md) · English

A lightweight macOS menu bar app for Windows-style, per-window switching. Press **Option (Alt) + Tab** to select the next window, then release Option to switch. Windows belonging to the same app appear separately.

![Switcher demo](Resources/Switcher-preview.png)

The image shows demo windows. Real windows display previews when screen recording permission is granted.

[Download](https://github.com/jiig6tyg1/AltWindow/releases/tag/v1.00) · [MIT License](LICENSE) · [Report an issue](https://github.com/jiig6tyg1/AltWindow/issues)

## Features

- Per-window switching with keyboard and mouse support.
- Small, medium, and large thumbnails; your preference is saved.
- Standard macOS menu bar menu.
- Native Liquid Glass on macOS 26 and later; blurred backgrounds on macOS 14/15.
- Optional background launch at login.
- On-demand previews with a bounded 8 MiB / 24-image cache. Images are released 10 seconds after closing the switcher.
- No network requests, analytics, or ads during normal use.

## Requirements and installation

macOS 14 or later. The downloadable build targets **Apple Silicon**. Runtime testing was performed on macOS 27.0.1. Intel Macs, macOS 14/15/26, and multi-display / cross-Space behavior have not all been verified on hardware.

The release ZIP is **ad-hoc signed and not notarized**. It has no Developer ID signature, and macOS may block it from opening. Building from source is also supported; see below. Signing and notarization are documented in [RELEASE.md](RELEASE.md) (Japanese).

1. Extract the ZIP and move `AltWindow.app` to `/Applications` before launching it.
2. Grant **Accessibility** permission from the app's settings. Depending on your macOS version, the system may use a different label for this permission.
3. If keyboard input is not enabled, grant **Input Monitoring** permission too.
4. To display thumbnails, grant **Screen Recording** permission. This permission is optional; icons and titles work without it.
5. Quit and reopen AltWindow if macOS requests it.

Signing changes can invalidate previous permissions even when System Settings shows an enabled switch. Remove the old AltWindow entry and add `/Applications/AltWindow.app` again in the affected permission category. Rebuilding an ad-hoc signed app changes its identity; use the same signing certificate for subsequent builds when possible.

## Controls

| Action | Result |
| --- | --- |
| Option + Tab | Open the switcher and select the next window; press again to advance |
| Option + Shift + Tab | Move backward |
| Release Option / Enter | Switch to the selected window |
| Arrow keys | Move selection |
| Escape | Cancel |
| Click a card | Switch to that window |

Use the menu bar menu to show windows, open settings, or quit. Reopening the app also opens settings. In settings, choose the thumbnail size (small / medium / large; medium is the default) and optionally enable background launch at login. The app interface is currently Japanese.

The demo button shows fictional windows for checking the layout; it does not enumerate your actual windows.

## Privacy and memory

Window titles and screenshots are not written to disk. Preview images are static snapshots, bounded to 760 pixels on their longest edge. The cache limit applies to image data, not total application memory. Idle operation does not request new screenshots. Requests already sent to macOS may complete after dismissal, but their results are discarded.

Explicit diagnostic and benchmark modes report counts and memory measurements. An optional benchmark manifest contains window IDs, never titles or image pixels. See [PRIVACY.md](PRIVACY.md) and [PERFORMANCE.md](PERFORMANCE.md) for details (Japanese). The performance report measures an earlier development build, not version 1.00 with larger thumbnails.

## Limitations

- Apps without standard Accessibility support and certain special windows may not appear.
- Full-screen and cross-Space activation depend on the target app and macOS settings.
- Minimized windows or unavailable previews fall back to icons.
- Window enumeration refreshes approximately every two seconds and when apps become active.
- The shortcut is fixed to Option + Tab.
- This project is independent of the separate AltTab app.

## Build and test

Requires Xcode 26 or later with the macOS 26 SDK or later. No external Swift packages are required.

```sh
bash build.sh
swift test --disable-sandbox
```

The app is generated in the parent directory. `ALTWINDOW_BUILD_DIR` and `ALTWINDOW_APP_PATH` override build and output paths. By default, new builds use ad-hoc signing. To preserve identity across local updates, set `ALTWINDOW_SIGNING_IDENTITY` to the same signing certificate each time; `ALTWINDOW_TIMESTAMP=none` is available for local development. The build refuses to silently overwrite a certificate-signed output with ad-hoc signing.

The test suite contains 28 tests covering selection, keyboard routing, window matching, image sizing, cache limits, and login-item state handling.

## License and support

[MIT License](LICENSE), copyright 2026 jiig6tyg1.

Please report bugs in [GitHub Issues](https://github.com/jiig6tyg1/AltWindow/issues), including your macOS version, Mac model, and reproduction steps. Remove private information from screenshots before posting.

# Satchel

A native macOS app that keeps a large set of small tools in one window. Files stay on the Mac: there is no account and no upload step.

Satchel is an independent app. Its name, copy, and icon are its own. The Dock icon is a teal kit bag — an open tool bag with a wrench and a pencil — drawn by `scripts/make_app_icon.py` (concept B). Pillow and numpy are required to redraw it:

```bash
python3 scripts/make_app_icon.py --concept B --iconset Satchel/Assets.xcassets/AppIcon.appiconset
```

The 16 and 32 point slots are drawn on a pixel grid. Larger slots come from a supersampled master.

## Layout

- `SatchelCore/` is a Swift package with the tool catalog, search, and the pure logic behind rename, duplicates, text, and developer tools. It builds on Linux.
- `Satchel/` is the SwiftUI app (macOS 15 or later).
- `project.yml` is the XcodeGen spec. The Xcode project is generated and is not committed.
- `scripts/install.sh` builds a Release app, re-signs it, and replaces `~/Applications/Satchel.app`.
- `scripts/make_app_icon.py` draws the app icon.

## Core tests

```bash
cd SatchelCore
swift test
```

## App

```bash
brew install xcodegen
./scripts/install.sh
```

`DERIVED_DATA` overrides the build directory (default `/tmp/satchel-build`). Signing uses the first Apple Development identity reported by `security find-identity`, or an ad-hoc signature when none is present.

Snapshot the home screen and every category, in light and dark, at 1440×900:

```bash
Satchel.app/Contents/MacOS/Satchel --snapshot /tmp/satchel-snap
```

The snapshot path uses an offscreen view render. It does not record the screen.

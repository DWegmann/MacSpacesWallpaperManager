# Mac Spaces Wallpaper Manager

**English** | [Deutsch](README.de.md)

I developed Mac Spaces Wallpaper Manager for my own use. If you would like to use the app but cannot build it yourself, feel free to get in touch through a [GitHub issue](https://github.com/DWegmann/MacSpacesWallpaperManager/issues).

> **Noncommercial reuse only:** The original project code may be used, modified and shared under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). This license does not permit commercial use.

A native macOS app with a separate wallpaper folder for each desktop Space and display. Built with **SwiftUI and AppKit**, with no external dependencies. The universal app supports **Apple Silicon (arm64) and Intel (x86_64), starting with macOS 13 Ventura**. The current app interface is in German; this repository includes English and German documentation.

**macOS 26 Tahoe is an intended target.** The app's minimum version is macOS 13; the optional direct mode requires macOS 14. Neither requires APIs available only in macOS 27. Space detection and direct mode use private macOS interfaces and may need changes after system updates. Direct mode checks the detected storage format before each change and is disabled by default.

## Features

- Assign separate image folders to desktop Spaces on each display, optionally including subfolders.
- Browse a thumbnail gallery and choose a particular image, random rotation or natural alphabetical order.
- Change wallpapers manually, when entering a Space or at a fixed interval.
- Edit settings for multiple Spaces together, choose image scaling and set a background color.
- Control rotation from the menu bar, pause it or enable launch at login.
- Optionally update inactive Spaces through an experimental direct mode with local backups and undo.
- Keep images and configuration on your Mac, without network services or external libraries.

## License

The original project code is published under the **PolyForm Noncommercial License 1.0.0**, following [Lichtblick](https://github.com/DWegmann/Lichtblick). The complete [license text](LICENSE.md) is authoritative. Redistribution must retain the license text or its URL and the required notices.

Required Notice: Copyright 2026 Dominic Wegmann

This license applies to the original project components to the extent that the relevant rights exist. The source code is publicly available for noncommercial reuse ("source available"); its commercial restriction means this is not an OSI open-source license.

## Build and run

Install Xcode or the Xcode Command Line Tools with Swift 5.9 or later. Running the XCTest suite requires full Xcode.

```sh
git clone https://github.com/DWegmann/MacSpacesWallpaperManager.git
cd MacSpacesWallpaperManager
./Scripts/build-app.sh --open
```

The script creates:

- `dist/Mac Spaces Wallpaper Manager.app`: a universal app, locally ad-hoc signed by default.
- `dist/Mac-Spaces-Wallpaper-Manager-universal.zip`: the packaged app.

Copy the app to Applications, especially if you want to enable launch at login. For development, open `Package.swift` in Xcode or run `./Scripts/swift-task.sh build`.

The scripts prefer `/Applications/Xcode.app` when installed. An explicit `DEVELOPER_DIR` takes precedence. To place build caches on a local temporary volume, for example when developing on an external drive in a restricted environment:

```sh
WALLPAPER_BUILD_ROOT=/private/tmp/MacSpacesWallpaperManager-build ./Scripts/build-app.sh
```

An installed **macOS 26 SDK** is preferred automatically, including when the selected Xcode is newer. To select one explicitly:

```sh
WALLPAPER_MACOS_SDK=/absolute/path/MacOSX26.sdk ./Scripts/build-app.sh
```

Otherwise, the scripts use the selected macOS SDK. The deployment target remains 13.0. The build reports the SDK and records it as `DTSDKName` in the bundle. A newer build SDK does not raise the minimum runtime version.

## Usage

1. Select a desktop in the sidebar. Create additional desktops in Mission Control first.
2. Choose **Bilderordner auswählen** to assign an image folder. Standard mode applies an initial image to a visible desktop immediately; an inactive desktop receives it on its next visit. Optional direct mode can update inactive desktops immediately.
3. Toggle **Unterordner einbeziehen** to include subfolders. Recursive scanning is enabled by default.
4. Choose an image from the gallery, change the display mode or configure automatic rotation.

Each Space has its own folder, recursion setting, image selection, display mode, order and interval. Random selection avoids an immediate repeat when at least two images are available. Alphabetical order uses natural filename sorting.

### Edit multiple Spaces

Choose **Auswählen** beside **Deine Spaces** to enter multiple selection. Check the desired desktops; **Alle** beside a display selects its Spaces. The shared editor also offers **Alle auswählen** and **Auswahl leeren**.

Enable only the settings you want to change: folder, subfolders, rotation, image scaling, background color, order or activation. **Auf … Spaces anwenden** applies those fields to the selected Spaces. Existing image selections remain unless you assign a new folder, which clears the affected selections and rescans the folder. **Fertig** or **Mehrfachauswahl beenden** returns to single-Space editing.

### Scaling and background color

Selecting **An Bildschirm anpassen** reveals **Hintergrundfarbe**, a native color picker. The color fills the unused area around the image and appears in the preview. **Schwarz** resets it. Colors are saved per Space and work in both standard and direct mode. The shared editor can apply a color to several Spaces; it changes scaling only when that setting is also checked. Existing configurations without a color continue to use black.

### Rotation and menu bar

Rotation can be manual, on reentering a Space, every 5, 15 or 30 minutes, hourly or daily. In standard mode, inactive desktops catch up when visited; direct mode can update them while inactive. No timer work runs during sleep. Use **Ordner neu einlesen** to pick up added or removed files. The timer checks every 15 seconds, so scheduled changes may be slightly delayed.

Closing the window leaves the app running in the menu bar, with **Nächstes Hintergrundbild**, **Automatik pausieren** and **Beenden**. `⌘R` refreshes the Space list; `⇧⌘N` selects the next image for visible, enabled Spaces. Settings (`⌘,`) include launch at login.

## Optional direct mode for inactive Spaces

Enable **Einstellungen → Direktmodus (experimentell) → Auch inaktive Spaces sofort aktualisieren** to use the unofficial storage method. It is off by default for new and existing installations and requires macOS 14 or later with a readable `Index.plist`.

Direct mode applies image selection, scaling and rotation to assigned inactive desktop Spaces without switching desktops. Changes to several Spaces are briefly collected to reduce background-service restarts.

It changes only `Spaces[Space-UUID].Displays[Display-UUID].Desktop` in:

```text
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

Other Spaces, display and Space defaults, and screen savers are preserved. Missing display entries receive a separate assignment based on the existing Space default. Turn off the macOS **Show on all Spaces** setting first. Coupled wallpaper/screen-saver entries and unknown formats are rejected; use standard mode for those configurations.

Before each actual change, the app creates a local backup. It pauses the logged-in user's `WallpaperAgent` during the short write phase and then restarts it. An independent helper resumes the service within three seconds if the app exits during writing. **The wallpaper can briefly flicker during an image change.** This is also explained beside the experimental option in Settings.

Writes are atomic. The app checks for concurrent changes before writing and after reloading. On error, it attempts to undo its own change, disables direct mode and pauses rotation. It displays the reason and backup location; you can then continue in standard mode.

**Letzte Direktmodus-Änderung rückgängig machen …** restores only the desktop wallpapers affected by the last direct-mode change and pauses rotation. If an affected wallpaper has since changed outside the app, restoration stops. Later changes to other Spaces and existing screen savers remain intact.

The ten latest backups are kept under:

```text
~/Library/Application Support/SpacePaper/WallpaperBackups/
```

Each contains `before.plist`, `after.plist` and a targeted `undo.plist` log, readable only by the current user. Settings includes a button to reveal backups in Finder. This mode is unsupported by Apple and may need adjustment after macOS updates. Examples of the general approach include [backgrounds](https://github.com/ThomasBPG/backgrounds/blob/main/wallhaven-wallpaper.py) and [wallall](https://github.com/TresChar/wallall); this app changes individual assignments rather than assigning one wallpaper to every Space.

## macOS limitations

Apple provides [NSWorkspace.setDesktopImageURL](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)) for display wallpapers and [Space-change notifications](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification), but no public interface for listing and identifying every Space reliably.

The app therefore dynamically loads two **read-only, private SkyLight functions**. The data format can also be seen in [Hammerspoon's implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua). UUIDs identify desktops independently of their order and temporary numbers. Standard mode sets wallpapers through the public AppKit API; optional direct mode writes the private wallpaper store.

- An inactive Space receives its standard-mode assignment when visited while the app is running. Direct mode can apply it earlier. The app does not switch Spaces itself.
- Normal desktop Spaces are supported; full-screen and Split View Spaces are skipped.
- Displays are handled separately, including when Spaces are managed together. Disconnected displays retain their saved assignments.
- Deleting and recreating a Space gives it a new identity and requires a new assignment.
- Space detection may require adjustment after macOS updates. No wallpapers change if detection fails.
- Private Space detection makes this app intended for direct distribution rather than the Mac App Store. It requires neither Accessibility nor Screen Recording permission, nor disabling SIP.
- macOS slideshow rotation or another wallpaper app can overwrite selections. Disable other rotation for the desktops you manage here.

## Images and local data

The scanner detects JPEG, PNG, HEIC, TIFF and other formats readable by macOS Image I/O. It reads image metadata and generates reduced, cached thumbnails. Hidden files, package contents and symbolic links are skipped. Corrupted images and unreadable subfolders are reported. A damaged file can still cause a separate macOS error when applied as wallpaper.

Original images remain unchanged in your folder. The app has no network functionality or external services. Settings and folder bookmarks are saved atomically under:

```text
~/Library/Application Support/SpacePaper/configuration.json
```

The internal data directory and bundle identifier retain the earlier SpacePaper name to preserve existing assignments. If the configuration is corrupted or unknown, automatic changes stop and the file is preserved. Use **Einstellungsdatei im Finder zeigen**, quit the app, then back up and rename the file if you want to start with a fresh configuration.

## Validation

```sh
./Scripts/swift-task.sh test
"./dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager" --diagnostics
"./dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager" --direct-store-check
lipo -archs "dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager"
codesign --verify --deep --strict "dist/Mac Spaces Wallpaper Manager.app"
```

`--diagnostics` reads actual desktop UUIDs, visible Spaces and displays without loading configuration or changing wallpapers. `--direct-store-check` checks a targeted change and full undo in memory against the current macOS store. It writes no files and signals no processes. Passing this check confirms a recognized format, not the actual display after a service restart.

Tests cover recursive scanning, natural sorting, corrupted files, symlink cycles, cancellation, multiple displays, full-screen filtering, persistent identity, selection, intervals and persistence. Shared changes are checked against selected Spaces and explicitly enabled fields, including colors and compatibility with existing configurations.

Direct-mode tests use temporary files and a simulated background service. They cover targeted edits, colors, Unicode paths, backups, undo, external changes, reload and recovery failures, permissions and backup retention. Automated tests do not change real wallpaper settings.

For a manual check, create two desktops, assign different folders, switch between desktops and toggle recursion. Then check image selection, timers, pause, relaunch and an additional display if available. An Apple Silicon Mac can build and inspect Intel binaries; an actual Intel runtime check requires an Intel Mac.

To inspect the build SDK and minimum system version:

```sh
xcrun vtool -show-build "dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager"
```

`minos` is the minimum runtime version; `sdk` is the compilation SDK. Building against the macOS 26 SDK and running tests on a newer host does not replace a runtime check on macOS 26, especially for experimental direct mode.

## Signing for distribution

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./Scripts/build-app.sh
xcrun notarytool submit dist/Mac-Spaces-Wallpaper-Manager-universal.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple "dist/Mac Spaces Wallpaper Manager.app"
```

For Developer ID distribution, sign and notarize with your own Apple credentials. The default ad-hoc signature is intended for local use. After stapling, create a fresh archive:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "dist/Mac Spaces Wallpaper Manager.app" \
  dist/Mac-Spaces-Wallpaper-Manager-notarized.zip
```

## Project structure

- `Sources/MacSpacesWallpaperManager`: SwiftUI interface, app state, menu bar and settings.
- `Sources/WallpaperCore`: Space detection, image scanning, configuration and optional direct mode.
- `Tests/WallpaperCoreTests`: tests using temporary files and a simulated background service.
- `Resources/Info.plist`: application metadata and minimum system version.
- `Scripts`: SDK selection, Swift builds and universal-app packaging.
- `Tools/GenerateIcon.swift`: app icon generation.

Build products and local development files are excluded through `.gitignore`. Report bugs and suggestions through [GitHub issues](https://github.com/DWegmann/MacSpacesWallpaperManager/issues). For Space-detection problems, include your macOS version, architecture, display setup and a sanitized error message.

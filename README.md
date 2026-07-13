# Tesviye

![Tesviye application icon](docs/assets/tesviye-icon-256.png)

Tesviye is a focused, native macOS utility for resizing one or many images. It combines precise pixel sizing,
useful presets, format conversion, quality control, safe output naming, and a Finder Quick Action in one compact
workflow.

[Website](https://tercan.github.io/tesviye/) · [Türkçe tanıtım](https://tercan.github.io/tesviye/tr/) ·
[Version 1.0.0](https://github.com/tercan/tesviye/tree/v1.0.0)

## Features

- Resize a single image or process multiple selected images as a batch.
- Enter exact width and height values or choose one of five built-in presets.
- Preserve the aspect ratio, swap width and height, and optionally prevent upscaling.
- Keep the source format or convert output to JPEG, PNG, or WebP.
- Use automatic quality by default or enable manual quality control for JPEG and WebP.
- Preserve originals, overwrite intentionally, or save copies to a custom output folder.
- Add a dimension-based filename suffix and resolve collisions with `-1`, `-2`, and subsequent numbers.
- Preserve image metadata while optionally removing location metadata.
- Choose a JPEG background color when a transparent source must be flattened.
- Start from Finder through the **Resize Images** Quick Action.
- Remember the most recent resize settings, output folder, suffix, and appearance mode.
- Follow the system appearance or use a saved light or dark theme.
- Review per-file results and clear the selected image list in one action.

## Requirements

- macOS 14 or later
- Xcode 16 or later for building from source
- An Apple development team selected in Xcode when running a signed local build

## Build from source

1. Clone the repository:

   ```bash
   git clone https://github.com/tercan/tesviye.git
   cd tesviye
   ```

2. Open `tesviye.xcodeproj` in Xcode.
3. Select the **tesviye** scheme and choose your development team under **Signing & Capabilities**.
4. Build and run the current scheme.

Xcode resolves the pinned `libwebp-Xcode` Swift Package dependency automatically.

## Usage

1. Select one or more images with **Select Images**, drag them onto the application window, or invoke the Finder
   Quick Action.
2. Choose a preset or enter a target width and height.
3. Set upscaling, overwrite behavior, output format, and quality mode.
4. Open **Advanced Settings** when you need a custom suffix, output folder, metadata options, or JPEG background
   color.
5. Select **Resize Images** and review the result list when processing finishes.

By default, Tesviye keeps the original file and writes the resized copy next to it. If a file with the same name
already exists, the application chooses the next available numbered name instead of replacing it silently.

## Finder Quick Action

The `TesviyeFinderAction` extension is embedded in the application bundle and accepts up to 100 images per Finder
request. After building or installing Tesviye:

1. Select one or more image files in Finder.
2. Open the context menu and choose **Quick Actions → Resize Images**.
3. Tesviye opens a single window with all selected images loaded.

If the action is hidden, review the macOS extension controls under **System Settings → General → Login Items &
Extensions** and enable the Tesviye action.

## Privacy and resource use

Tesviye processes images locally. It does not upload images, require an account, include an analytics SDK, or run a
background service after the application exits. The only website link in the app opens the public Tesviye project
page when the user selects it.

## Localization

The application and Finder Quick Action include English and Turkish localizations. New user-facing strings must be
added to both localization files:

- `en.lproj/Localizable.strings`
- `tr.lproj/Localizable.strings`
- `FinderAction/en.lproj/InfoPlist.strings`
- `FinderAction/tr.lproj/InfoPlist.strings`

## Tests

Run the unit and integration suite without code signing:

```bash
xcodebuild \
  -project tesviye.xcodeproj \
  -scheme tesviye \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TesviyeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Create an unsigned Release build:

```bash
xcodebuild \
  -project tesviye.xcodeproj \
  -scheme tesviye \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/TesviyeDerivedData-Release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Project structure

- `ContentView.swift` — main SwiftUI interface and native macOS window integration
- `MainViewModel.swift` — selection, progress, state, and batch workflow coordination
- `ImageResizeService.swift` — image decoding, resizing, metadata, encoding, and safe output installation
- `PreferencesStore.swift` — durable user preferences and migration
- `FinderAction/` — Finder Quick Action extension
- `TesviyeTests/` — model, file workflow, extension, asset, and regression tests
- `docs/` — public GitHub Pages website

## License

Tesviye is available under the [GNU General Public License v2.0](LICENSE). WebP support is provided through
`libwebp-Xcode`; see [ThirdPartyNotices.txt](ThirdPartyNotices.txt) for attribution and license information.

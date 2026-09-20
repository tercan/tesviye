# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-09-20 00:16

### Changed

- Replaced separate light and dark controls with a single icon that toggles between the two appearances, with localized action labels.
- Refreshed the English and Turkish presentation pages and README with up-to-date English light/dark screenshots and descriptions of the current conversion workflow.
- Updated screenshot references and asset budgets to validate both appearances and remove obsolete image paths.

## [1.2.0] - 2026-09-19 23:49

### Added

- Keep Size mode converts image formats while preserving each source image’s oriented pixel dimensions.
- Explicit Custom Size selection enables shared width and height inputs independently of JPEG, PNG, or WebP output.

### Changed

- Simplified size choices to a text-only strip with Keep Size first and Custom Size last.
- Made filename, output location, metadata, and JPEG background options always visible, with the last three controls sharing one row.
- Replaced system/light/dark cycling with separate light and dark controls; existing system preferences migrate once to the current appearance.
- Closing the app now terminates it completely, with safe batch cancellation and preference saving. Removed the persistent menu bar mode.

### Fixed

- Preserved explicit Keep Size and Custom Size selections when normalizing and reloading preferences.

## [1.1.2] - 2026-09-19 23:26

### Fixed

- Capitalized the Turkish Finder Quick Action label as “Görselleri Yeniden Boyutlandır”.
- Added light and dark Finder icon renditions while retaining template rendering, with a new asset identifier to avoid the older icon cache.

## [1.1.1] - 2026-09-19 19:25

### Changed

- Shortened the completion heading and grouped the content-sized Finder and Clear List buttons in one consistent action row.
- Sized the window to its content to remove unused space below collapsed and expanded Advanced Settings.

### Fixed

- Disabled the JPEG background color well for PNG and WebP output while retaining the saved color.
- Dismissed the color panel on outside clicks, application deactivation, and control removal without blocking other controls.

## [1.1.0] - 2026-09-19 18:26

### Added

- Optional filename suffix with a persistent checkbox; disabling it preserves the basename while retaining safe collision numbering.

### Changed

- Redesigned the completion dialog with a clear result count, a prominent Show Images in Finder action, and separate failure and interrupted-batch details.
- Updated English and Turkish completion messages and suffix controls.

### Fixed

- Restored closing the borderless application window from its custom title bar.
- Enabled native window dragging from the title and the unused area of the custom title bar.
- Preserved existing custom suffix preferences when migrating to the new settings schema.

## [1.0.0] - 2026-07-13 08:50

### Added

- Native macOS image resizing for single files and batches of up to 100 images.
- Precise width and height controls with aspect-ratio locking, dimension swapping, optional upscaling, and five
  built-in presets.
- JPEG, PNG, and WebP output with automatic quality selection and optional manual quality control.
- Safe copy creation, intentional overwrite mode, custom output folders, dimension-based suffixes, and automatic
  collision numbering.
- Metadata preservation, optional location metadata removal, and selectable JPEG background color for transparent
  sources.
- Finder Quick Action that launches one Tesviye window with all selected images loaded.
- Persistent resize settings, filename suffix, output location, and system, light, or dark appearance preferences.
- Batch progress, per-file result reporting, and a one-step action for clearing the selected image list.
- English and Turkish localization for the application and Finder extension.
- Native menu bar integration, compact radius-free windows, and accessible keyboard and VoiceOver labels.
- Automated unit and integration coverage for resize behavior, preferences, output safety, Finder import, resources,
  and application packaging.
- Bilingual GitHub Pages presentation website, project README, license, and third-party notices.

### Security

- Image processing remains on the local Mac and does not require uploads, accounts, analytics, or a background
  service.
- Custom output folder access is persisted with security-scoped bookmarks, and file replacement requires explicit
  user intent.

[1.0.0]: https://github.com/tercan/tesviye/tree/v1.0.0

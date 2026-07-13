# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and uses semantic versioning.

## [1.0.1] - 2026-03-07

### Added
- Added `schemaVersion` field to `AMS_DB` for future-proofing data format migrations.
- Added migration logic to handle `schemaVersion` changes and ensure safe upgrades without data loss.
- Added `lastUpdated` timestamp to `AMS_DB` for tracking data freshness and potential staleness issues.
- Added `locale` field to `AMS_DB` to track the locale of persisted data and enable locale-specific handling in future updates.
- Added more language and add fallback to local names in the index build process to improve search results for non-English locales.

### Changed
- Improved memory behavior by keeping Auctionator price DB loading strictly lazy.
- Added API-only initialization path to avoid loading heavy DB data at addon startup.
- Reduced temporary memory retention after index build/reconcile and when closing the main window.
- Added bounds for analysis metadata cache to prevent unbounded growth in long play sessions.
- Switched SavedVariables `searchIndex` to a compact persistence format (core fields + optional ranges + locale names).
- Removed redundant persisted runtime-derived fields (`nameLower`, `itemLink`, duplicate name aliases).
- Updated locale name handling to preserve additional language keys in `names` for future localization expansion.
- Added locale quality metadata (`verified` vs `beta`) and automated locale key-coverage checks against `enUS`.
- Kept strict fallback behavior for missing texts (`active locale -> enUS -> deDE -> key`) to avoid broken UI strings.

### Removed
- Removed AMS custom price line from the item tooltip.
- Removed the "Show price in tooltip" option from settings.

### Fixed
- Restored default WoW item tooltip on result row hover while keeping AMS price overlay disabled.


## [1.0.0] - 2026-03-02

### Added
- Initial retail release of Auctionator Mini Search.
- CurseForge packaging helper file `.pkgmeta`.

### Changed
- Minimap button now prefers custom icon `Assets/icon` with fallback to Blizzard spyglass icon.

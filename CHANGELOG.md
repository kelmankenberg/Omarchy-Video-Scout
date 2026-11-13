# Changelog

## 1.1.0 - 2026-11-13

### Added

- Scrollable Setup page with saved refresh and result-limit preferences.
- Opt-in automatic refresh: Off (default), 10, 15, 30, 45, 60, 90, or
  120 minutes. Searches use the selected date filter and never overlap.
- Configurable search limits of 50 (default), 100, or 150 videos, used by
  both manual and automatic refreshes.
- Persistent read/unread status shared across date filters, with per-video
  toggles and Mark all read / Mark all unread for the displayed results.
- Accent borders for unread videos and neutral gray borders for read videos.
- Automatic mark-as-read after an unread card scrolls completely above the
  viewport for more than one second. Returning it to view before the deadline,
  closing the panel, switching pages/filters, or refreshing cancels the mark.
- Unread-count badges for each filter's last successful search. Unsearched
  filters have no badge; counts update across cached filters as read status
  changes. Counts are capped by the selected search limit and can be stale.
- Help, feature-request, and bug-report links in Setup, plus GitHub issue
  forms that prefill the version from the installed manifest.
- Regression tests for result limits, settings migration/persistence,
  read-state persistence, and delayed scroll-read cancellation.

### Changed

- Replaced the bar's plain play triangle with a YouTube-style icon and
  added the matching icon beside the panel title.
- The bar icon uses the theme accent color only during automatic searches.
- Watch, Download, and read/unread controls are icon-only buttons on one
  row, with translated action tooltips. Envelope icons show the current
  read state: closed for unread and open for read.
- Opening the panel no longer starts a search. Manual Refresh remains
  available, and selecting a date filter still searches.
- Existing results remain visible while a refresh runs.

### Upgrade notes

- Automatic refresh is disabled for new installations until explicitly
  enabled. Preferences are stored in
  `$XDG_CONFIG_HOME/omarchy-video-scout/settings.json`, or
  `~/.config/omarchy-video-scout/settings.json` by default.
- Read video IDs are stored alongside preferences in `read.json`; removing
  the plugin does not remove these files or downloaded videos.
- Filter results/counts are held in memory and reset on shell restart.
- Existing interval-only settings are migrated with a default 50-video limit.
- No new runtime dependencies or administrator privileges are required.

## 1.0.0 - 2026-10-30

- Initial marketplace release of Omarchy Video Scout.
- Day, Week, Month, and All YouTube searches with up to 50 results,
  newest-first sorting, approximate upload dates, and video thumbnails.
- Watch in the default browser and download with yt-dlp.
- Native Omarchy panel lifecycle, English translations, MIT license,
  installation/removal documentation, and offline search tests.

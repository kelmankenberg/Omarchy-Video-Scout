# Omarchy Video Scout

A native Omarchy bar widget for discovering the latest Omarchy videos on
YouTube. Browse thumbnails, filter by day, week, month, or all time, and
watch or download videos with yt-dlp.

Independent community plugin; not affiliated with YouTube or the Omarchy project.

Current version: **1.1.0**. See [CHANGELOG.md](CHANGELOG.md) for release details.

![Omarchy Video Scout v1.0.0 showing recent videos and date filters](preview.png)

The preview shows v1.0.0; v1.1.0 adds the Setup page, unread tracking, and
icon-only video actions described below.

## Requirements

- Omarchy Quattro with its Quickshell-based shell and plugin CLI.
- Python 3 (standard library only).
- A recent `yt-dlp` on PATH for searches and downloads.
- A default browser for Watch actions.
- Internet access. FFmpeg may be needed by yt-dlp to merge video and audio.

No API key, account, administrator privileges, background service, or install
script is required. The plugin does not automatically install dependencies.

## Install

```sh
omarchy plugin add https://github.com/kelmankenberg/Omarchy-Video-Scout.git --enable
```

The plugin ID is `kel.omarchy-video-scout`. Look for the YouTube-style button on the
right side of the bar. To move it:

```sh
omarchy bar move kel.omarchy-video-scout --section right
```

If you already have the locally created Video Scout at that ID, back it up
outside the plugin directory before replacing it with a Git-managed install.
Do not install a second copy with the same ID.

## Use

Click the YouTube-style button to open the panel. Click **Refresh** to search.
Choose **Day**, **Week**, **Month**,
or **All**, then use the play icon to **Watch** or the download icon to
**Download** a video. The envelope icon toggles read status; tooltips describe
each action. Click outside
the panel, press Escape, or click the bar button again to dismiss it.

The standard shell commands also open and close the panel:

```sh
omarchy-shell shell summon kel.omarchy-video-scout '{}'
omarchy-shell shell hide kel.omarchy-video-scout
```

- Opening the panel does not search. Refreshing or changing the range does.
- Each video has **Mark as read**, changing to **Mark as unread** when read.
  Read videos keep a neutral gray border; unread
  videos have an accent border. **Mark all read / Mark all unread** affect
  only the current filter's displayed results. Status is shared across date
  filters and survives searches and restarts. Watch/Download do not implicitly
  mark videos read.
- While scrolling the Videos page, an unread card that moves entirely above
  the viewport and stays there for over one second is automatically marked
  read. Scrolling it back into view, closing the panel, changing pages or
  filters, or refreshing cancels pending marks. Already offscreen cards are
  not marked merely by reopening the panel.
- **Setup > Refreshing** offers Off (default), 10, 15, 30, 45, 60, 90, or
  120 minutes. Automatic searches continue with the panel closed, using the
  current date filter. The first scheduled search happens after the chosen
  interval, and searches never overlap. Manual Refresh remains available.
  During automatic refresh, the bar icon uses the theme accent color; manual
  refresh does not change its color.
- The default range is Week; the selection lasts until the plugin reloads.
- **Setup > Videos per refresh** selects 50 (default), 100, or 150 videos.
  This saved limit applies to the next manual or automatic refresh. YouTube
  may return fewer. Changing it does not start a search or reset the timer.
- Each range is sent to YouTube before applying the selected result limit.
- Date-filter badges count unread videos from each filter's last successful
  search, without making additional background requests. Unsearched filters
  have no badge; a searched filter with no unread videos shows zero.
  Read/unread changes update all cached filter counts, including overlapping
  videos. Counts may be stale and are limited to the returned results, not
  YouTube-wide totals. Cached filter results and badges reset on shell restart.
- Day uses YouTube's last-day filter, not a local midnight cutoff.
- All removes the date restriction; it does not retrieve every matching video.
- Results are sorted newest first using approximate timestamps from YouTube's
  displayed upload ages. Undated results remain visible at the end.
- YouTube determines relevance, so matches can include Shorts, live streams,
  and videos whose titles do not mention Omarchy. There is no additional
  plugin-specific topic, channel, or language filter.
- Logged-out results may differ from your browser's personalized results.
  YouTube indexing and search changes can also affect coverage.

Downloads run one at a time and are saved under:

```text
~/Videos/Omarchy Video Scout/
```

Download only content you own or have permission to download, and respect
applicable terms and laws. Disabling or reloading the plugin while a download
is running can interrupt it.

Both searches and downloads ignore personal yt-dlp configuration so unrelated
options do not change plugin behavior. Browser cookies are not read or passed
to yt-dlp. Restricted videos may therefore be unavailable.

## Network, permissions, and local data

**Setup > Help, features & bugs** links to this guide and the repository's
bug-report and feature-request forms. These links prefill the version read
from the installed `manifest.json`; users do not need to look it up.
Direct visitors to GitHub can find the version in Setup.
GitHub login is required to submit an issue. Opening a form does not submit
anything or upload logs; review your report before sending it.

Plugins run unsandboxed inside the Omarchy shell with your user permissions.
Review the source before installation.

The search helper invokes the installed yt-dlp against a fixed HTTPS YouTube
search URL. Searches have a 30-second overall timeout and 15-second socket
timeout. It validates IDs, timestamps, text lengths, result counts, and the
size of captured metadata before handing results to QML.

Thumbnails load from `https://i.ytimg.com` only while the panel is open.
Opening a video launches its YouTube watch URL in your default browser.
Downloading lets yt-dlp contact YouTube and its media delivery hosts.
Those services receive normal network request information, such as your IP.

Periodic refreshes are opt-in through Setup and stop when Off is selected or
the plugin is disabled. The interval is stored in
`~/.config/omarchy-video-scout/settings.json` (under `XDG_CONFIG_HOME` if set).
Explicit read status is stored alongside it in `read.json`, as video IDs only.
Storage is bounded to 100,000 IDs; reaching the limit reports an error instead
of silently forgetting previously read videos.
There is no telemetry, stored credentials, or persistent search query history.
Results are held in memory; Qt may cache thumbnails. Downloads
and partial downloads remain on disk until you remove them. User configuration
is changed only through explicit Setup or Omarchy plugin/bar commands.

## Disable, update, and remove

```sh
omarchy plugin disable kel.omarchy-video-scout
omarchy plugin enable kel.omarchy-video-scout
omarchy plugin update kel.omarchy-video-scout
omarchy plugin remove kel.omarchy-video-scout
```

Removal does not delete downloaded videos or saved refresh settings. To reset
the interval and video limit, remove only the plugin's `settings.json` file above. Remove
`read.json` to reset read status.

## Development

From the repository root on an Omarchy installation:
Node.js is needed only for the JavaScript regression tests, not to run the plugin.

```sh
python3 bin/test_search_videos.py
python3 bin/test_refresh_settings.py
python3 bin/test_read_state.py
node bin/test_scroll_read.js
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml
```

An optional live search check (contacts YouTube):

```sh
python3 bin/search-videos.py day
```

Edit a user-owned plugin copy, never `/usr/share/omarchy`. The shell normally
reloads local changes. If it retains stale QML, use `omarchy restart shell`.
Static validation does not replace checking the running shell for errors.

## Marketplace submission

Version 1.0.0 was published to the marketplace through
[submission #13401](https://github.com/omacom/omarchy-plugin-marketplace/issues/13401).
Version 1.1.0 is prepared for release and updated listing review; the earlier
validation applies only to the reviewed v1.0.0 commit, not these changes.

Version 1.0.0 checks completed on an Omarchy desktop: clean Git-based installation,
all four filters, thumbnail loading, shell summon/hide, Escape dismissal,
disable/re-enable, shell restart, and removal followed by reinstallation.
Watch was manually confirmed, and a downloaded WebM was checked with FFprobe.
Offline regression tests also run in GitHub Actions.

Version 1.1.0 desktop checks confirmed settings persistence, manual refresh,
100- and 150-video searches, per-item/bulk read controls, delayed scroll-read behavior
and cancellation, and GitHub support forms with the version prefilled.
Automated tests cover all three video limits and persistence/migration.
The complete installable snapshot passed manifest validation, QML lint,
12 Python regression tests, and JavaScript scroll-read tests with no local
build artifacts. Full removal/reinstallation was checked for v1.0.0;
the v1.1.0 checks do not claim a fresh-machine install.

Before requesting updated listing review, publish the prepared commit/release,
confirm its GitHub Actions checks, and reference the new exact commit/version
in the marketplace request rather than claiming the old approval covers it.
Suggested category: **Widgets**. Tags: **Bar**, **Media**, **Quickshell**.

Marketplace approval is for listing and is not a security review.
See the [official publishing guide](https://plugins.omarchy.org/publish.html).

## License

[MIT](LICENSE).

# Music Toolbar

Music Toolbar is an Omarchy Quickshell bar widget for MPRIS playback, optional CAVA visualization, and synchronized lyrics. It works with Spotify, browser MPRIS players, MPV, VLC, and other compatible players.

All plugin-authored interface text, logs, scripts, comments, and documentation are in English. Player metadata and lyric content are displayed as provided by the player and the lyric services.

## Features

- A theme-aware bar pill with a full-width, style-selectable CAVA background visualizer behind independently toggled player icon, track text, and optional previous/play-pause/next controls. A Full-bar visualizer toggle in Settings moves the wave to a transparent bar-sized overlay across the entire topbar (250 ms cross-fade) and turns the pill transparent; see Visualizer placement below.
- A clean three-column main popup: circular album artwork with an animated halo; track metadata, playback controls, and a seek bar; and synced lyrics.
- A gear button in the main popup opens a separate Settings panel. A back arrow returns to the main popup.
- Player source and visualizer-style selectors appear only in Settings, never in the main popup.
- Auto/recent-player selection, or a fixed MPRIS player filter that keeps metadata and playback actions scoped to the selected player.
- Free lyrics lookup through LRCLIB, then lyrics.ovh for plain-text fallback. No API key or paid API is used.
- Wave, Bars, and Dots CAVA renderers. The selected style and all bar display choices persist across shell restarts.

## Requirements and dependencies

- An Omarchy Quickshell version that provides `qs.Commons`, `qs.Ui`, the `Panel`/`KeyboardPanel` lifecycle, and Quickshell MPRIS.
- `omarchy` and `omarchy-shell` for installation and plugin discovery. The installer uses `omarchy-restart-shell` when available.
- Python 3 with its standard library for bounded, no-follow JSON reads and atomic JSON edits. No pip packages are used. This is a required safety helper for installation, removal, and persistent preferences; if the requirement is interpreted as “no dependency other than CAVA,” the current safe-JSON design cannot meet that literally without replacing the parser/file-safety layer with a host-provided equivalent.
- CAVA is optional. Without it, playback, settings, and lyrics continue to work, while the spectrum visualizer is hidden. The included `cava.ini` uses CAVA's PulseAudio input backend, typically available on PipeWire systems with PulseAudio compatibility enabled. Its fixed 96-bar configuration is safely staged once at startup to `/tmp/music-toolbar/cava.ini` and is not rewritten when settings change.
- Network access to `lrclib.net` and `api.lyrics.ovh` is needed only for lyric lookup.

The plugin does not install system packages, request elevated privileges, or use third-party Python modules. Omarchy plugins run unsandboxed in the user's shell process, so review the source before installation.

## Install

From the project directory, run:

```sh
bash install.sh
```

### Fresh install on another Omarchy machine

Prerequisites (checked by the installer, no pip packages needed):

- An Omarchy session with `omarchy` and `omarchy-shell` on `PATH`.
- Python 3 with its standard library (required for safe settings storage).
- CAVA is optional: without it the visualizer stays hidden and everything else works.

Steps:

```sh
# copy the project folder to the new machine (git clone, zip, USB — any method),
# then from the project directory:
bash install.sh
```

Press Enter at the placement prompt for **Center**, or type Left / Center / Right. The installer validates the plugin, enables it, applies placement, and performs a one-time shell restart. On first boot there is no legacy settings file, so defaults apply (`wave`, Auto source, icon + text shown): no migration runs and no error is expected. Toggle anything (or right-click the widget) and confirm the bar does not blink — saves go to `~/.config/music-toolbar/config.json`, outside the shell's watched plugins directory.

The installer prompts for **Left**, **Center**, or **Right** placement; pressing Enter selects **Center**. It copies and validates the plugin, rescans discovery, enables Music Toolbar, then applies the prompted placement and `omarchy.media` disabled state to the host bar configuration. Reapplying placement after enabling the plugin prevents its manifest default section from overriding the user's choice. Installation performs its one-time shell restart after setup; runtime preference changes do not touch the host bar layout.

Placement rules are:

- **Left:** after `omarchy.menu`, or at the end of the left section if the menu is absent.
- **Center:** after `omarchy.clock`, or at the end of the center section if the clock is absent.
- **Right:** at the end of the right section.

The installer removes `omarchy.media` from the bar layout and ensures it is listed in `disabledPlugins`. It saves the media widget's original section, index, entry, and prior disabled state in the plugin's private install-state file. Uninstall uses that record to restore the original state. Host-layout reads are bounded and reject symlinks; writes use a same-directory temporary file and atomic rename while preserving file permissions.

To enable the visualizer, install CAVA with your system package manager and restart the Omarchy shell. CAVA is not bundled with the plugin.

To validate the installation and QML imports:

```sh
PLUGIN_DIR="$HOME/.config/omarchy/plugins/music-toolbar"
omarchy plugin validate "$PLUGIN_DIR"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
qmllint -I "$OMARCHY_PATH/shell" \
  "$PLUGIN_DIR/Service.qml" "$PLUGIN_DIR/BarWidget.qml" \
  "$PLUGIN_DIR/Panel.qml" "$PLUGIN_DIR/SettingsPanel.qml" \
  "$PLUGIN_DIR/LyricsFetcher.qml" "$PLUGIN_DIR/CavaVisualizer.qml" \
  "$PLUGIN_DIR/PlayerSelector.qml"
```

Test with at least one MPRIS player. If possible, start two players and verify Auto/recent-player behavior and fixed-source filtering. Open Settings from the gear, change the source and CAVA style, toggle each bar option, return with the back arrow, and reopen the panel. Drag the seek slider only when the active player reports seek support. CAVA can be installed separately to validate live spectrum input.

## Controls

| Input | Action |
| --- | --- |
| Left-click the bar widget | Open or close the main popup |
| Middle-click the bar widget | Play or pause the active player |
| Scroll up on the bar widget | Previous track |
| Scroll down on the bar widget | Next track |
| Right-click the bar widget | Toggle track text; the preference is saved |
| Gear button in the main popup | Open the separate Settings panel |
| Back arrow in Settings | Return to the main popup |
| Previous, Play/Pause, or Next in the main popup | Control the active player when that action is supported |
| Drag the progress slider | Seek when the player supports seeking and reports track length |
| Select a Player pill in Settings | Choose Auto or one detected MPRIS player |
| Select a Style pill in Settings | Choose Wave, Bars, or Dots |
| Toggle a Bar display setting | Show or hide the player icon, track text, or bar controls |
| Toggle Full-bar visualizer | Move the wave to a transparent full-topbar overlay; the pill turns transparent while it is on |
| Escape | Close the currently open panel |

By default, the bar shows the player icon and track text; its playback control strip is off. When CAVA is available, its full-width background remains visible independently of those three toggles, at 0.35 opacity while playing and 0.15 while idle. Waiting for a fixed player dims the icon while the visualizer stays subdued.

## Player selection and MPRIS filtering

- **Auto** is the default. It selects the most recently started player when multiple MPRIS players are playing. If all are paused, it remembers the last active player when possible, then falls back to a player with track metadata.
- A fixed source is matched by a normalized MPRIS `desktopEntry`, falling back to `identity`. The active-player candidate list is restricted to that key. Metadata, transport actions, seeking, artwork, and lyrics are not routed to a different player when the selected source is unavailable.
- Settings lists detected MPRIS players even when they are paused. A saved-but-unavailable selection remains visible so it can be changed or cleared.
- Player identity is normalized to lower-case ASCII letters and digits for matching. The visible player label and icon are derived from the detected identity; unknown players use a generic music glyph.

CAVA reads the system audio source configured in `cava.ini`, not an individual MPRIS player's stream. If that source is a mixed output monitor, its spectrum can include other sounds in the same mix. The MPRIS filter still scopes the widget's player metadata and playback commands.

## Main popup and Settings structure

`Panel.qml` is the main popup and follows Omarchy's `Panel` plus `KeyboardPanel` pattern. Its columns are artwork/animated halo, metadata/transport/progress, and the synced-lyrics viewport. The top-right gear calls into the bar widget, which closes the main popup and opens `SettingsPanel.qml` as a separate Omarchy panel. Settings owns the source selector, CAVA style selector, and the three persisted bar toggles; its back arrow closes Settings and reopens the main popup.

Both panels are anchored to the same bar widget and expose the standard `open()`, `close()`, `toggle()`, and popout-switch lifecycle through `BarWidget.qml`. The selectors are implemented by `PlayerSelector.qml`, which is loaded only inside Settings.

## Conditional bar rendering

`BarWidget.qml` reads `showPlayerIcon`, `showText`, and `showControls` from the service. The icon, metadata label, and three-button transport strip each render only when their own preference is enabled. Previous/next and play/pause buttons are disabled when the active MPRIS player does not advertise the corresponding capability. The full-width CAVA backdrop is a separate clipped layer behind the foreground; it remains visible whenever CAVA is available, regardless of playback state or those three display preferences. When `fullBarCava` is true, the pill wave fades to opacity 0 and the pill fill and border fade to fully transparent over 250 ms while the icon, text, and controls stay visible floating over the full-bar wave; the single 96-bar CAVA process keeps running with the same PID and no layout or bar-height change occurs.

The bar widget remains usable before its service is resolved through a direct MPRIS fallback for basic metadata and playback actions. Persistent settings are service-backed.

## CAVA styles

CAVA runs at a fixed 96-sample output, normalized from 0 to 255. Each visualizer slices the samples according to its own width — the pill shows a subset while the full-bar overlay uses the whole feed — recalculating the display count on resize without restarting CAVA. A perceptual gain curve lifts quiet passages into visibility while capping peaks at full scale, shared by all three renderers:

- **Wave** draws a smoothed spline crest with a soft glow, filled with a vertical gradient that dissolves toward the bottom edge.
- **Bars** distributes sharp square bars edge-to-edge as a group with hair gaps, easing height changes while opacity deepens with level.
- **Dots** distributes sample dots across the full width, scaling size and opacity with level and capping diameter by bar pitch so dense rows read as texture.

The chosen renderer is stored as `visualizerStyle` in `config.json`. When CAVA is missing or repeatedly fails to start, the plugin disables only the visualizer and keeps the rest of the UI available. Animations respect Omarchy's reduced-motion setting.

## Visualizer placement

Settings has a Visualizer placement section after Bar display with a single Full-bar visualizer toggle bound to `service.fullBarCava` (boolean, default `false`).

- Off (default): CAVA renders inside the widget pill, flush to both edges, over the themed pill fill.
- On: the plugin opens one transparent `PanelWindow` per screen (`FullBarCava.qml`, layer-shell namespace `music-toolbar-cava`), sized like the host bar, painting only the CAVA wave across its full height. The pill wave fades out and the pill fill and border fade to fully transparent, so the icon, text, and controls float over the full-bar wave.

Stacking honesty: the Omarchy plugin API exposes no bar-background hook, and the bar surface itself is opaque, so a separate surface cannot render underneath the bar's pixels. The overlay therefore stacks above the bar surface on the same Top layer and confines the wave to the bottom strip to minimize overlap with widget content.

Click-through guarantee: the overlay declares an empty input mask (`mask: Region {}`), takes no keyboard focus, reserves no exclusive zone, and contains no input handlers, so every click, scroll, and hover reaches the bar widgets behind it.

Prerequisites: a compositor with layer-shell support (Hyprland, as shipped by Omarchy). Toggling never writes `shell.json`, never restarts the shell or rescans plugins, and never restarts CAVA: one 96-bar process keeps running and both renderers slice its feed independently.

## Lyrics flow, LRC parsing, and cache

1. The service reads title, artist, album, and supported duration from the active MPRIS player. Requests start only when title and artist are available.
2. A 500 ms debounce lets MPRIS metadata settle before a request is sent. Requests are sequential: the plugin queries LRCLIB's exact-match `/api/get` endpoint first, adding album and a valid duration when available.
3. An LRCLIB instrumental result is displayed and cached. If `syncedLyrics` is available, the LRC parser extracts one or more `[mm:ss.fraction]` timestamps per line, normalizes one-, two-, and three-digit fractions, skips blank rows, and sorts the resulting timestamp/text pairs.
4. The lyric matching line follows MPRIS playback position. Position is refreshed every 250 ms only while the main popup is open and the selected player is playing; the highlight scrolls into view.
5. When LRCLIB has no usable synced lines, the plugin waits 300 ms, then requests plain lyrics from `https://api.lyrics.ovh/v1/{artist}/{title}`. If lyrics.ovh returns no usable text, LRCLIB `plainLyrics` is used as a fallback.
6. Track results, including not-found and instrumental outcomes, use a session-only FIFO cache capped at 100 entries. Revisiting a cached track avoids another request during that shell session.
7. On HTTP 429, the plugin honors LRCLIB's `Retry-After` value, displays a countdown, and does not retry LRCLIB before the delay expires. Invalid or missing values receive a conservative fallback delay.

LRCLIB requests identify the client with a User-Agent and use no API key. The services receive the track metadata required to find lyrics. No lyric data is sent to this plugin's repository.

## Theme and accessibility

The QML uses Omarchy's `Commons.Color`, `Style`, `Border`, and `Util` singletons and theme-aware UI components such as `KeyboardPanel`, `PanelSectionHeader`, `Toggle`, `Button`, `BorderSurface`, `PanelSlider`, and `PanelSeparator`. Colors, typography, spacing, borders, and animation timing derive from the active Omarchy theme; the plugin defines no alternate palette.

Interactive controls provide the Omarchy pointing-hand cursor and focus states. The panels support Escape, keyboard panel navigation, and reduced-motion behavior for continuous and pulsing animations.

## IPC

The service registers the `music-toolbar` target. Examples (called directly on the target; `shell call` only reaches panel loaders and returns `"unknown"` for service methods):

```sh
omarchy-shell music-toolbar getPlayers
omarchy-shell music-toolbar setPlayer spotify
omarchy-shell music-toolbar setPlayer auto
omarchy-shell music-toolbar setVisualizerStyle dots
omarchy-shell music-toolbar setFullBarCava true
omarchy-shell music-toolbar getFullBarCava
omarchy-shell music-toolbar status
omarchy-shell music-toolbar playPause
```

`getPlayers` returns detected normalized keys, identities, desktop entries, and playback state as JSON. `setPlayer auto` selects automatic mode. `setVisualizerStyle` accepts `wave`, `bars`, or `dots`. `setFullBarCava` accepts a boolean and `getFullBarCava` returns `"true"` or `"false"`. `status` also includes the saved bar display preferences and `fullBarCava`.

## Preferences and persistence

Preferences are stored at:

```text
~/.config/music-toolbar/config.json
```

This plugin-owned file is intentionally separate from Omarchy's host-managed bar layout, and intentionally outside `~/.config/omarchy/plugins/`: the shell watches the plugins directory with inotify and reloads the whole plugin on every write there, so keeping runtime preferences inside it would blink the entire bar on each toggle. Runtime property changes update QML bindings immediately and persist only to this preferences file; they never rewrite the host layout or request a shell restart. The host layout is managed only during installation and removal.

Versions before this change stored preferences at `~/.config/omarchy/plugins/music-toolbar/config.json`. On startup the service migrates that legacy file once to the new location and never writes to it again (the stale copy can be deleted manually).

Example:

```json
{
  "selectedPlayerKey": "spotify",
  "visualizerStyle": "wave",
  "showText": true,
  "showControls": false,
  "showPlayerIcon": true,
  "fullBarCava": false
}
```

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `visualizerStyle` | string | `"wave"` | `"wave"`, `"bars"`, or `"dots"` |
| `selectedPlayerKey` | string | `""` | Normalized player key; empty = Auto |
| `showText` | bool | `true` | Show track title/artist in the bar |
| `showControls` | bool | `false` | Show previous/play-pause/next in the bar |
| `showPlayerIcon` | bool | `true` | Show the leading player icon in the bar |
| `fullBarCava` | bool | `false` | Render the CAVA wave in a transparent full-topbar overlay and turn the pill transparent |

The service debounces preference saves by 250 ms. `config_store.py` validates the allowed player key, CAVA styles, and boolean settings. It reads at most 64 KiB through a no-follow file descriptor and rejects symlinks and non-regular files. Preference writes use a private same-directory temporary file, fsync, and atomic rename; a newly created settings file is mode `0600`, and an existing file's mode is preserved. The same helper stages the fixed 96-bar CAVA config with no-follow checks and atomic replacement, once at service startup. QML never reopens the preferences path directly. If Python 3 is unavailable at runtime, settings remain in memory and a warning is logged rather than bypassing the safe file path.

## Uninstall

From the project directory or the installed plugin directory, run:

```sh
bash uninstall.sh
```

The uninstaller removes Music Toolbar from every bar section, restores the saved `omarchy.media` entry or entries at their previous placement, and restores whether `omarchy.media` was previously in `disabledPlugins`. It moves the plugin directory to `plugin/` and the runtime preferences (`~/.config/music-toolbar/`) to `runtime-config/` inside a timestamped backup under `~/.config/omarchy/plugin-backups/`, rescans plugin discovery, and completes the one-time shell restart needed to finish uninstalling. If no restart facility exists, it prints a manual restart notice. Nothing is deleted: the backup retains plugin files, preferences, and install state.

## References

- Omarchy plugin development guide: <https://plugins.omarchy.org/develop.html>
- Omarchy Music Flow reference: <https://github.com/Clifford-Baidoo/Omarchy-music-flow>
- LRCLIB API documentation: <https://lrclib.net/docs>
- lyrics.ovh: <https://lyrics.ovh>
- CAVA: <https://github.com/karlstav/cava>
- Omarchy Quickshell and theme-aware UI components: <https://github.com/omacom/omarchy>

Music Toolbar is distributed under the MIT License. See `LICENSE`.

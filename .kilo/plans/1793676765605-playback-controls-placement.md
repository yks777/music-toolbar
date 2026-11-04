# Plan: fixed widget structure icon → title → playback buttons; icon source = app icon or album art

## Goal
Make the bar widget foreground a fixed, non-configurable row ordered strictly as: **icon → track title → playback buttons**. Replace the per-element left/center/right alignment feature (just implemented) with a single user choice: the leading icon is either the **player's app icon** (default) or the **current album artwork**. All alignment settings (`showIconAlignment`, `showTextAlignment`, `showControlsAlignment`) are removed; visibility toggles (`showPlayerIcon`, `showText`, `showControls`) remain.

## Context (current committed state in `78a6a5b` + my previous turn)
- `showControlsAlignment` exists in Service.qml, config_store.py, BarWidget.qml, SettingsPanel.qml, README (committed `78a6a5b`).
- My previous turn added `showIconAlignment`/`showTextAlignment` to Service.qml, config_store.py, BarWidget.qml, SettingsPanel.qml, README and reworked `foregroundLayer` into independently-positioned elements (`BarWidget.qml:380-495`).
- Buttons are wired (`performPrevious`/`performPlayPause`/`performNext` → service with MPRIS fallback), uniformly sized at `space(28)`, gated by `showControls` and player capability.
- `BarWidget.qml` has `playerIcon` (app-icon glyph) but no `artworkUrl`; `Service.qml` exposes `artUrl` and `activePlayer.trackArtUrl` exists in fallback.

## Decisions
1. **Fixed order**: `foregroundLayer` becomes a single `Row` with fixed children order: icon element, spacing, track label, spacing, controlRow. No alignment properties; no per-element `x` binding; no lead/trail spacers.
2. **Icon source toggle**: new Service property `showIconAsAlbum` (bool, default `false`). When `true`, the leading element shows album artwork (Image, rounded); when `false`, it shows the app-icon glyph (current `playerIcon` text). Persisted to config.json.
3. **Remove alignments**: delete `showIconAlignment`, `showTextAlignment`, `showControlsAlignment` from Service.qml, config_store.py, SettingsPanel.qml, README. Keep `showControls` (already exists) as the controls visibility toggle.
4. **Artwork in BarWidget**: add `readonly property string artworkUrl` resolved from `musicService.artUrl` or fallback `activePlayer.trackArtUrl`.
5. **Album art element**: an `Image` (`fillMode: Image.PreserveAspectCrop`, rounded radius) shown only when `showIconAsAlbum && showPlayerIcon && artworkUrl`; otherwise the `Text` glyph. Both gated by `showPlayerIcon`.
6. **Defaults unchanged**: all alignments removed; `showIconAsAlbum` defaults `false` (backward compatible: app icon).
7. SettingsPanel: replace the three alignment chooser sections with a single toggle "Show album as icon" (or similar label) under Bar display.

## Files to change
1. `config_store.py` — remove `showIconAlignment`/`showTextAlignment` validation/defaults; add `showIconAsAlbum` boolean validation + default; remove from read-settings fallback.
2. `Service.qml` — remove `showIconAlignment`/`showTextAlignment` properties/setters/IPC/status/saveConfig/applyConfigurationText/change handlers; add `showIconAsAlbum` property + setter + persistence + status + IPC (`setShowIconAsAlbum`/`getShowIconAsAlbum`) + change handler.
3. `BarWidget.qml` — add `artworkUrl` property; rework `foregroundLayer` into fixed-order Row; replace icon `x`-binding with conditional Image/Text; remove `iconAlignment`/`textAlignment`/`controlsAlignment` properties and all spacer/lead-trail logic; keep `trackLabel` width animation and `Behavior on implicitWidth`.
4. `SettingsPanel.qml` — remove `iconAlignment`/`textAlignment`/`controlAlignment` properties and the three alignment chooser sections; add "Icon source" toggle (app icon vs album) bound to `service.showIconAsAlbum`, gated on `showPlayerIcon`.
5. `README.md` — remove alignment preferences/IPC/docs; document `showIconAsAlbum` toggle and fixed icon → title → buttons order.

## Tasks
1. Revert alignment code in `config_store.py`; add `showIconAsAlbum`.
2. Revert alignment code in `Service.qml`; add `showIconAsAlbum` property/persistence/IPC.
3. Rework `BarWidget.qml` foregroundLayer: fixed Row icon→title→buttons; artwork-url property; album-as-icon Image element.
4. Replace alignment choosers in `SettingsPanel.qml` with icon-source toggle.
5. Update `README.md` (preferences table, Controls section, IPC examples, conditional bar rendering).
6. Validate: `omarchy plugin validate <plugin dir>` exit 0; `qmllint` clean of new errors; reload shell; toggle icon source between app icon and album; verify fixed order icon→title→buttons; verify config.json persists and survives reload.

## Open questions
- Setting label text for the icon-source toggle (English per codebase convention): e.g. "Show album as icon" vs "Icon source: album". Recommend "Show album as icon".
- Album art element size: match icon height (`space(28)`) with radius; recommend square size equal to icon height.

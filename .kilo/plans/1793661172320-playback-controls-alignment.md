# Plan: uniform playback buttons with left/center/right alignment

## Goal
Make the bar-widget playback controls (Previous / Play-Pause / Next) the same size, horizontally positionable (left / center / right) inside the widget pill, and user-configurable with persistence.

## Context
- Controls live in `BarWidget.qml` (`controlRow`/`controlButtons`, lines 412-470): Previous 24×24, Play-Pause 28×28, Next 24×24 — different sizes, left-aligned in the pill.
- Alignment is not a setting; `showControls` (bool) only toggles visibility.
- Settings are persisted via `config_store.py` (validates a fixed key set) → `Service.qml` → `~/.config/music-toolbar/config.json`.
- Validation: `qmllint` + `omarchy plugin validate` (README) + manual functional check; there is no test suite/package.json.

## Decisions (recommended)
1. Common button size: all three buttons = `Style.space(28)` width × height, unified `iconSize: Style.font.icon`.
2. New Service property `showControlsAlignment`: `"left" | "center" | "right"`, default `"left"` (preserves current rendered behavior; user can switch to center/right). Stored in config.
3. `foregroundLayer` uses leading/trailing alignment spacers mirroring the existing `foregroundSpacer` free-width binding: left ⇒ free space trailing; right ⇒ free space leading; center ⇒ split evenly. Spacers gated by `visible: width > 0`.
4. Settings chooser: under "Bar display", a row of three `Button`s (Left / Center / Right) bound to `service.showControlsAlignment` with active-state styling (fallback: segmented/pill control if `qs.Ui` provides one).
5. Config keys: add `showControlsAlignment` to `config_store.py` validation/defaults and to `Service.qml` (`applyConfigurationText`, `saveConfig`, `statusJson`, `onShowControlsAlignmentChanged`, IPC `setShowControlsAlignment`/`getShowControlsAlignment`).
6. README: update Preferences table + Controls section + IPC examples.

## Files to change
1. `config_store.py` — alignment validation + default.
2. `Service.qml` — property, persistence, status, IPC.
3. `BarWidget.qml` — unified button size + alignment positioning.
4. `SettingsPanel.qml` — alignment chooser UI.
5. `README.md` — docs.

## Validation
- `qmllint` on the five QML files (per README).
- `omarchy plugin validate <plugin dir>`.
- Reload shell; enable showControls; cycle alignment left → center → right; verify buttons are equal size and position changes; verify config.json persists and survives reload.

## Notes / risks
- Mirror the existing `foregroundSpacer` free-width formula (BarWidget.qml:473-481); verify no double spacing when an alignment spacer becomes visible.
- Default alignment ("left" for backward compat vs "center" per request) is one property default and can be flipped.
- UI text stays in English per README convention.

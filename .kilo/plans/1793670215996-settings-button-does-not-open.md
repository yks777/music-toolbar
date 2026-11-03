# Plan: Fix settings panel not opening after playback-controls alignment changes

## Goal
Restore the ability to open the Settings panel from the main popup's gear button, which broke after adding the playback-control alignment chooser to `SettingsPanel.qml`.

## Root cause hypothesis
`SettingsPanel.qml` likely fails to load at runtime because the new `Button` elements use `text`, `fontFamily`, and `font.pixelSize` properties. No existing `Button` (from `qs.Ui`) in the codebase uses `text` — all use `iconText`. `fontFamily`/`font.pixelSize` are also not used on any existing `Button`. qmllint cannot resolve `qs.Ui.Button` ("Button was not found" warnings), so it did not catch invalid properties.

When `SettingsPanel.qml` fails to load, `settingsLoader.item` stays `null`. In `BarWidget.qml:openSettings()`:
```qml
if (settingsLoader.item) settingsLoader.item.open()
```
the guard fails, so the settings panel never opens.

## Files to change
1. `SettingsPanel.qml` — replace the three `Button`-based alignment chooser with a compatible approach (e.g. `MouseArea` + `Text`, or `Button` using only `iconText`/`iconSize`/`foreground`/`background`). Keep the three left/center/right choices and active-state styling.

## Decisions
- Keep `readonly property string controlAlignment` and `readonly property bool controlControlsVisible` on `SettingsPanel.qml` root (they are fine; they bind to service properties).
- Keep the `PanelSectionHeader` "Control alignment" (uses `text`/`fontFamily`, which are already used on `PanelSectionHeader` elsewhere).
- Replace the `Button` row with controls that are known to work in this codebase pattern.
- Alignment buttons disabled when `!settingsReady || !controlControlsVisible` (same as before).

## Validation
- `qmllint` on `SettingsPanel.qml` (expect no new errors; pre-existing `unqualified` / `property-override` warnings are acceptable).
- `omarchy plugin validate <plugin dir>` exit 0.
- Runtime: open popup, click gear icon, confirm settings panel opens; alignment row visible and buttons enabled only when "Show playback controls" is on.
- Confirm `showControlsAlignment` persists in `~/.config/music-toolbar/config.json` and survives shell reload.

## Rollback
If the replacement approach also fails, revert `SettingsPanel.qml` to its pre-change state (remove the alignment section entirely) to confirm settings opens, then iterate.

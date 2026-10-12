#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_ID="music-toolbar"
STOCK_PLUGIN_ID="omarchy.media"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME:?HOME must be set}/.config}"
OMARCHY_CONFIG_DIR="$CONFIG_HOME/omarchy"
PLUGIN_ROOT="$OMARCHY_CONFIG_DIR/plugins"
TARGET_DIR="$PLUGIN_ROOT/$PLUGIN_ID"
SHELL_JSON="$OMARCHY_CONFIG_DIR/shell.json"
STATE_PATH="$TARGET_DIR/.install-state.json"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'Music Toolbar installer: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "Python 3 with its standard library is required for safe JSON editing."
command -v omarchy >/dev/null 2>&1 || fail "Omarchy commands were not found. Run this installer from an Omarchy session."
command -v omarchy-shell >/dev/null 2>&1 || fail "omarchy-shell was not found. Start the Omarchy shell, then retry."

printf 'Choose the bar placement: Left, Center, or Right (default: Center): '
IFS= read -r placement || placement=""
case "${placement,,}" in
  ""|c|center) BAR_SECTION="center" ;;
  l|left) BAR_SECTION="left" ;;
  r|right) BAR_SECTION="right" ;;
  *) fail "Choose Left, Center, or Right." ;;
esac

for directory in "$CONFIG_HOME" "$OMARCHY_CONFIG_DIR" "$PLUGIN_ROOT" "$TARGET_DIR"; do
  [[ ! -L "$directory" ]] || fail "Refusing to use a symbolic-link directory: $directory"
done
mkdir -p -- "$PLUGIN_ROOT" "$TARGET_DIR"

files=(
  manifest.json
  Service.qml
  BarWidget.qml
  Panel.qml
  SettingsPanel.qml
  LyricsFetcher.qml
  CavaVisualizer.qml
  PlayerSelector.qml
  cava.ini
  config_store.py
  scripts/configure_bar.py
  install.sh
  uninstall.sh
  README.md
  LICENSE
  assets/preview.svg
)

for relative_path in "${files[@]}"; do
  source_path="$SCRIPT_DIR/$relative_path"
  target_path="$TARGET_DIR/$relative_path"
  [[ -f "$source_path" && ! -L "$source_path" ]] || fail "Required project file is missing or unsafe: $relative_path"

  target_parent="$(dirname -- "$target_path")"
  [[ ! -L "$target_parent" ]] || fail "Refusing to write through a symbolic-link directory: $target_parent"
  mkdir -p -- "$target_parent"
  [[ ! -L "$target_path" ]] || fail "Refusing to replace a symbolic-link file: $target_path"

  case "$relative_path" in
    *.sh|*.py) install -m 0755 -- "$source_path" "$target_path" ;;
    *) install -m 0644 -- "$source_path" "$target_path" ;;
  esac
done

omarchy plugin validate "$TARGET_DIR"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID"

# Reapply the prompted placement after Omarchy's enable command, which adds a
# bar widget to its manifest default section when one is not already present.
"$TARGET_DIR/scripts/configure_bar.py" \
  --action enable \
  --config "$SHELL_JSON" \
  --template "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" \
  --state "$STATE_PATH" \
  --plugin-id "$PLUGIN_ID" \
  --stock-id "$STOCK_PLUGIN_ID" \
  --section "$BAR_SECTION"

omarchy-shell shell rescanPlugins

if command -v omarchy-restart-shell >/dev/null 2>&1; then
  omarchy-restart-shell
else
  omarchy restart shell
fi

printf 'Music Toolbar is installed and enabled in the %s section.\n' "$BAR_SECTION"
printf 'omarchy.media is disabled in disabledPlugins; its prior placement and disabled state were saved for uninstall.\n'
printf 'CAVA is optional. Python 3 standard-library support is used for safe atomic JSON edits; no pip packages are required.\n'

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
RUNTIME_CONFIG_DIR="$CONFIG_HOME/music-toolbar"
BACKUP_ROOT="$OMARCHY_CONFIG_DIR/plugin-backups"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'Music Toolbar uninstaller: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail "Python 3 with its standard library is required for safe JSON editing."

for directory in "$CONFIG_HOME" "$OMARCHY_CONFIG_DIR" "$PLUGIN_ROOT" "$TARGET_DIR"; do
  [[ ! -L "$directory" ]] || fail "Refusing to use a symbolic-link directory: $directory"
done

CONFIG_TOOL="$SCRIPT_DIR/scripts/configure_bar.py"
if [[ ! -f "$CONFIG_TOOL" || -L "$CONFIG_TOOL" ]]; then
  CONFIG_TOOL="$TARGET_DIR/scripts/configure_bar.py"
fi
[[ -f "$CONFIG_TOOL" && ! -L "$CONFIG_TOOL" ]] || fail "The safe shell.json editor was not found."

# Zip copies and fresh clones may lose the executable bit; prefer direct
# execution but fall back to python3 explicitly.
if [[ -x "$CONFIG_TOOL" ]]; then
  CONFIG_CMD=("$CONFIG_TOOL")
else
  CONFIG_CMD=(python3 -- "$CONFIG_TOOL")
fi

if [[ -f "$SHELL_JSON" ]]; then
  "${CONFIG_CMD[@]}" \
    --action disable \
    --config "$SHELL_JSON" \
    --state "$STATE_PATH" \
    --plugin-id "$PLUGIN_ID" \
    --stock-id "$STOCK_PLUGIN_ID"
else
  printf 'No shell.json was found; the bar layout was left unchanged.\n'
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins || true
fi

[[ ! -L "$BACKUP_ROOT" ]] || fail "Refusing to use a symbolic-link backup directory: $BACKUP_ROOT"

backup_path=""
if [[ -d "$TARGET_DIR" || -d "$RUNTIME_CONFIG_DIR" ]]; then
  mkdir -p -- "$BACKUP_ROOT"
  backup_path="$BACKUP_ROOT/music-toolbar-$(date '+%Y%m%d-%H%M%S')"
  suffix=1
  while [[ -e "$backup_path" || -L "$backup_path" ]]; do
    backup_path="$BACKUP_ROOT/music-toolbar-$(date '+%Y%m%d-%H%M%S')-$suffix"
    suffix=$((suffix + 1))
  done
  mkdir -p -- "$backup_path"
fi

if [[ -d "$TARGET_DIR" ]]; then
  mv -T -- "$TARGET_DIR" "$backup_path/plugin"
  printf 'Plugin files and settings were backed up to: %s/plugin\n' "$backup_path"
fi

# Runtime preferences live outside the plugin dir (so saves never trigger a
# shell reload). Move them into the same backup instead of deleting.
if [[ -d "$RUNTIME_CONFIG_DIR" && ! -L "$RUNTIME_CONFIG_DIR" ]]; then
  mv -T -- "$RUNTIME_CONFIG_DIR" "$backup_path/runtime-config"
  printf 'Runtime preferences were backed up to: %s/runtime-config\n' "$backup_path"
fi

if command -v omarchy-restart-shell >/dev/null 2>&1; then
  omarchy-restart-shell
elif command -v omarchy >/dev/null 2>&1; then
  omarchy restart shell
elif command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins || true
  printf 'The shell was rescanned; restart it manually to finish uninstalling.\n'
else
  printf 'Omarchy restart commands were not found; restart the shell manually to finish uninstalling.\n'
fi

printf 'Music Toolbar was removed. The saved omarchy.media placement and disabled state were restored when an install record was available.\n'

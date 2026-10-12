#!/usr/bin/env bash
# Sync this project dir to the installed plugin dir in one shot,
# so omarchy-shell hot-reloads only once instead of once per save.
# Edite aqui em Projects/, rode ./sync-dev.sh, teste. Nunca edite
# ~/.config/omarchy/plugins/music-toolbar direto durante desenvolvimento.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/music-toolbar"

[[ -d "$SCRIPT_DIR" ]] || { echo "project dir missing" >&2; exit 1; }
mkdir -p -- "$TARGET_DIR"

# Preserva o legado config.json / .install-state.json no destino: o service
# migra o config legado uma única vez para ~/.config/music-toolbar/ no startup.
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'config.json' \
  --exclude '.install-state.json' \
  --exclude '.git/' \
  "$SCRIPT_DIR/" "$TARGET_DIR/"

chmod 0755 "$TARGET_DIR/sync-dev.sh" 2>/dev/null || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$TARGET_DIR"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  # Um único rescan = um único reload, em vez de N reloads (um por arquivo salvo).
  omarchy-shell shell rescanPlugins
  echo "Synced + rescan done (1 reload)."
else
  echo "Synced. Restart the shell manually to test."
fi

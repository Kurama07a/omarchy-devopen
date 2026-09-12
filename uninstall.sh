#!/bin/bash
# Remove what install.sh added. Your config at ~/.config/devopen is left alone
# unless you pass --purge.

set -euo pipefail

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/devopen"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devopen"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/devopen"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/prakhar.devopen"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"

PURGE=0
[[ ${1-} == "--purge" ]] && PURGE=1

say() { printf '  %s\n' "$*"; }

rm -f "$BIN_DIR/devopen" && say "removed $BIN_DIR/devopen"
rm -rf "$DATA_DIR" && say "removed $DATA_DIR"
rm -f "$PLUGIN_DIR" && say "removed $PLUGIN_DIR"
rm -rf "$CACHE_DIR" && say "removed $CACHE_DIR"

if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1; then
  if jq -e '[.. | objects | select(.id == "prakhar.devopen")] | length > 0' "$SHELL_JSON" >/dev/null 2>&1; then
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    tmp=$(mktemp)
    jq '(.bar.layout | to_entries | map(.value |= map(select(.id != "prakhar.devopen"))) | from_entries) as $l
        | .bar.layout = $l' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
    say "removed bar widget from shell.json"
  fi
fi

if [[ -f $BINDINGS ]] && grep -q 'devopen menu' "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  sed -i '/-- devopen: pick a tool/d; /devopen menu/d' "$BINDINGS"
  say "removed keybinding from bindings.lua"
fi

if ((PURGE)); then
  rm -rf "$CONFIG_DIR" && say "removed $CONFIG_DIR"
else
  say "kept $CONFIG_DIR (use --purge to remove)"
fi

echo "Done."

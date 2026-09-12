#!/bin/bash
# Install devopen: the CLI, the default config, the Omarchy bar widget,
# and (optionally) the SUPER+D keybinding.
#
# Everything is symlinked out of this checkout, so `git pull` here updates the
# installed copy. Re-running the installer is safe.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/devopen"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devopen"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/prakhar.devopen"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"

WITH_BAR=1
WITH_KEYBINDING=1
KEY="SUPER + D"

while (($#)); do
  case "$1" in
    --no-bar) WITH_BAR=0 ;;
    --no-keybinding) WITH_KEYBINDING=0 ;;
    --key) shift; KEY="${1:?--key needs a value}" ;;
    -h|--help)
      sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      echo
      echo "Usage: ./install.sh [--no-bar] [--no-keybinding] [--key 'SUPER + D']"
      exit 0
      ;;
    *) echo "install.sh: unknown option $1" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '  %s\n' "$*"; }

echo "Installing devopen from $REPO"

# --- 1. CLI ------------------------------------------------------------------
mkdir -p "$BIN_DIR"
ln -sfn "$REPO/bin/devopen" "$BIN_DIR/devopen"
say "cli        $BIN_DIR/devopen -> $REPO/bin/devopen"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "NOTE: $BIN_DIR is not on your PATH; add it to your shell profile." ;;
esac

# --- 2. default config -------------------------------------------------------
mkdir -p "$DATA_DIR" "$CONFIG_DIR"
ln -sfn "$REPO/config/config.default.json" "$DATA_DIR/config.default.json"
say "defaults   $DATA_DIR/config.default.json"

if [[ -f "$CONFIG_DIR/config.json" ]]; then
  say "config     $CONFIG_DIR/config.json (kept, not overwritten)"
else
  cp "$REPO/config/config.default.json" "$CONFIG_DIR/config.json"
  say "config     $CONFIG_DIR/config.json (created)"
fi

# --- 3. Omarchy bar widget ---------------------------------------------------
if ((WITH_BAR)); then
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  ln -sfn "$REPO/plugin/prakhar.devopen" "$PLUGIN_DIR"
  say "plugin     $PLUGIN_DIR"

  if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '[.. | objects | select(.id == "prakhar.devopen")] | length > 0' "$SHELL_JSON" >/dev/null 2>&1; then
      say "bar        already in shell.json"
    else
      cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
      tmp=$(mktemp)
      jq '.bar.layout.left += [{"id":"prakhar.devopen"}]' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
      say "bar        added to shell.json left section (backup alongside)"
    fi
  fi
fi

# --- 4. keybinding -----------------------------------------------------------
if ((WITH_KEYBINDING)); then
  if [[ -f $BINDINGS ]]; then
    if grep -q 'devopen menu' "$BINDINGS"; then
      say "keybind    already in bindings.lua"
    else
      cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
      {
        echo ""
        echo "-- devopen: pick a tool (editor / agent / preset), then a project directory."
        echo "o.bind(\"$KEY\", \"Open project\", \"devopen menu\")"
      } >>"$BINDINGS"
      say "keybind    $KEY -> devopen menu (backup alongside)"
    fi
  else
    say "keybind    $BINDINGS not found; add manually:"
    say "           o.bind(\"$KEY\", \"Open project\", \"devopen menu\")"
  fi
fi

echo
echo "Done. Try:"
echo "  devopen doctor     # check config, dependencies and what was found"
echo "  devopen            # open the picker"
echo "  $KEY               # same, from anywhere"

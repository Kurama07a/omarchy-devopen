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
PLUGIN_ID="io.github.kurama07a.devopen"
PLUGINS_ROOT="$HOME/.config/omarchy/plugins"
PLUGIN_DIR="$PLUGINS_ROOT/$PLUGIN_ID"
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
  mkdir -p "$PLUGINS_ROOT"

  if [[ "$REPO" == "$PLUGIN_DIR" ]]; then
    # Installed with `omarchy plugin add`: this checkout already is the plugin.
    say "plugin     already in place ($PLUGIN_DIR)"
  elif [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
    say "plugin     $PLUGIN_DIR exists and is not a link; leaving it alone"
  else
    ln -sfn "$REPO" "$PLUGIN_DIR"
    say "plugin     $PLUGIN_DIR -> $REPO"
  fi

  if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1; then
    if jq -e --arg id "$PLUGIN_ID" '[.. | objects | select(.id == $id)] | length > 0' "$SHELL_JSON" >/dev/null 2>&1; then
      say "bar        already in shell.json"
    else
      cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
      tmp=$(mktemp)
      jq --arg id "$PLUGIN_ID" '.bar.layout.left += [{"id":$id}]' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
      say "bar        added to shell.json left section (backup alongside)"
    fi
  fi

  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
fi

# --- 4. keybinding -----------------------------------------------------------
# The block is fenced with markers so uninstall removes exactly what was added
# here and never a binding you wrote yourself.
MARK_START="-- >>> devopen (managed by install.sh) >>>"
MARK_END="-- <<< devopen (managed by install.sh) <<<"

if ((WITH_KEYBINDING)); then
  if [[ -f $BINDINGS ]]; then
    if grep -qF -e "$MARK_START" "$BINDINGS"; then
      say "keybind    already in bindings.lua"
    else
      cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
      {
        echo ""
        echo "$MARK_START"
        echo "-- Pick a tool (editor / agent / preset), then a project directory."
        echo "-- Bound by full path, so the key runs this checkout and not"
        echo "-- whatever else a shell profile might put on PATH as \"devopen\"."
        echo "o.bind(\"$KEY\", \"Open project\", \"$REPO/bin/devopen menu\")"
        echo "$MARK_END"
      } >>"$BINDINGS"
      say "keybind    $KEY -> $REPO/bin/devopen menu (backup alongside)"
    fi
  else
    say "keybind    $BINDINGS not found; add manually:"
    say "           o.bind(\"$KEY\", \"Open project\", \"$REPO/bin/devopen menu\")"
  fi
fi

echo
echo "Done. Try:"
echo "  devopen doctor     # check config, dependencies and what was found"
echo "  devopen            # open the picker"
echo "  $KEY               # same, from anywhere"

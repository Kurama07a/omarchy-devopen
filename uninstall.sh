#!/bin/bash
# Remove what install.sh added. Your config at ~/.config/devopen is left alone
# unless you pass --purge.

set -euo pipefail

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/devopen"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devopen"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/devopen"
PLUGIN_ID="io.github.kurama07a.devopen"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"

PURGE=0
[[ ${1-} == "--purge" ]] && PURGE=1

say() { printf '  %s\n' "$*"; }

rm -f "$BIN_DIR/devopen" && say "removed $BIN_DIR/devopen"
rm -rf "$DATA_DIR" && say "removed $DATA_DIR"
rm -rf "$CACHE_DIR" && say "removed $CACHE_DIR"

# Only ever remove the link this installer made. A real directory there was put
# by `omarchy plugin add`, and removing it is that command's job.
if [[ -L $PLUGIN_DIR ]]; then
  rm -f "$PLUGIN_DIR" && say "removed $PLUGIN_DIR"
elif [[ -d $PLUGIN_DIR ]]; then
  say "NOTE: $PLUGIN_DIR is a real checkout (added with 'omarchy plugin add')."
  say "      Remove it with: omarchy plugin remove $PLUGIN_ID"
fi

if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null 2>&1; then
  if jq -e --arg id "$PLUGIN_ID" '[.. | objects | select(.id == $id)] | length > 0' "$SHELL_JSON" >/dev/null 2>&1; then
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    tmp=$(mktemp)
    jq --arg id "$PLUGIN_ID" \
      '(.bar.layout | to_entries | map(.value |= map(select(.id != $id))) | from_entries) as $l
       | .bar.layout = $l' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
    say "removed bar widget from shell.json"
  fi
fi

MARK_START="-- >>> devopen (managed by install.sh) >>>"
MARK_END="-- <<< devopen (managed by install.sh) <<<"

if [[ -f $BINDINGS ]] && grep -qF -e "$MARK_START" "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  # Only the fenced block installed by install.sh; any binding you added
  # yourself is left exactly as it is. One blank line is held back so the
  # separator install.sh writes before the block goes with it, leaving the
  # file byte-identical to what it was before installing.
  awk -v s="$MARK_START" -v e="$MARK_END" '
    index($0,s) { held=0; skip=1; next }
    index($0,e) { skip=0; next }
    skip { next }
    {
      if (held) { print ""; held=0 }
      if ($0 ~ /^[[:space:]]*$/) { held=1; next }
      print
    }
    END { if (held) print "" }
  ' "$BINDINGS" >"$BINDINGS.tmp" && mv "$BINDINGS.tmp" "$BINDINGS"
  say "removed keybinding block from bindings.lua"
elif [[ -f $BINDINGS ]] && grep -q 'devopen menu' "$BINDINGS"; then
  say "NOTE: bindings.lua mentions devopen but has no managed block;"
  say "      leaving it alone — remove the o.bind line yourself if you want."
fi

if ((PURGE)); then
  rm -rf "$CONFIG_DIR" && say "removed $CONFIG_DIR"
else
  say "kept $CONFIG_DIR (use --purge to remove)"
fi

echo "Done."

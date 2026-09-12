#!/bin/bash
# devopen test suite.
#
#   ./tests/run.sh            run everything
#   ./tests/run.sh security   run only the groups whose name matches
#
# Every test runs against a throwaway XDG root and a throwaway directory tree,
# so nothing here touches the real config, cache, or your projects. Launches go
# through stub binaries that record what they were asked to do instead of
# opening windows.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVOPEN="$REPO/bin/devopen"
FILTER="${1-}"

PASS=0 FAIL=0 SKIP=0
declare -a FAILURES=()
GROUP=""

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; OFF=$'\e[0m'
[[ -t 1 ]] || { RED=""; GREEN=""; YELLOW=""; BOLD=""; DIM=""; OFF=""; }

group() {
  GROUP="$1"
  if [[ -n $FILTER && $GROUP != *"$FILTER"* ]]; then GROUP="__skip__"; return; fi
  printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"
}

ok()   { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
no()   { FAIL=$((FAIL+1)); FAILURES+=("$GROUP / $1"$'\n'"      $2"); printf '  %s✗%s %s\n      %s%s%s\n' "$RED" "$OFF" "$1" "$DIM" "$2" "$OFF"; }
skip() { SKIP=$((SKIP+1)); printf '  %s-%s %s %s(%s)%s\n' "$YELLOW" "$OFF" "$1" "$DIM" "$2" "$OFF"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  [[ $GROUP == "__skip__" ]] && return 0
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "expected: $(printf '%q' "$2")  got: $(printf '%q' "$3")"; fi
}

# assert_contains <name> <needle> <haystack>
assert_contains() {
  [[ $GROUP == "__skip__" ]] && return 0
  if [[ "$3" == *"$2"* ]]; then ok "$1"; else no "$1" "expected to contain: $(printf '%q' "$2")  got: $(printf '%q' "$3")"; fi
}

# assert_not_contains <name> <needle> <haystack>
assert_not_contains() {
  [[ $GROUP == "__skip__" ]] && return 0
  if [[ "$3" != *"$2"* ]]; then ok "$1"; else no "$1" "expected NOT to contain: $(printf '%q' "$2")"; fi
}

# assert_rc <name> <expected-rc> <cmd...>
assert_rc() {
  [[ $GROUP == "__skip__" ]] && return 0
  local name="$1" want="$2"; shift 2
  local out rc
  out=$("$@" 2>&1); rc=$?
  if (( rc == want )); then ok "$name"; else no "$name" "expected rc=$want got rc=$rc; output: ${out:0:200}"; fi
}

assert_file() {
  [[ $GROUP == "__skip__" ]] && return 0
  if [[ -e $2 ]]; then ok "$1"; else no "$1" "missing file: $2"; fi
}

assert_no_file() {
  [[ $GROUP == "__skip__" ]] && return 0
  if [[ ! -e $2 ]]; then ok "$1"; else no "$1" "file should not exist: $2"; fi
}

# ---------------------------------------------------------------- fixtures --

TMP=$(mktemp -d "${TMPDIR:-/tmp}/devopen-tests.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

STUB="$TMP/stub"
TREE="$TMP/tree"
LOG="$TMP/launch.log"

mkdir -p "$STUB" "$TREE"

# Stub launchers: run the real command so cwd and quoting are genuinely
# exercised, but keep it to appending a line to a log.
cat >"$STUB/omarchy-launch-tui" <<'EOF'
#!/bin/bash
case "$1" in --app-id=*) APPID="${1#--app-id=}"; shift;; *) APPID="";; esac
echo "TUI appid=$APPID" >>"$DEVOPEN_TEST_LOG"
exec "$@"
EOF
cat >"$STUB/uwsm-app" <<'EOF'
#!/bin/bash
[ "$1" = "--" ] && shift
echo "GUI" >>"$DEVOPEN_TEST_LOG"
exec "$@"
EOF
cat >"$STUB/setsid" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$STUB/omarchy-notification-send" <<'EOF'
#!/bin/bash
echo "NOTIFY $*" >>"$DEVOPEN_TEST_LOG"
EOF
chmod +x "$STUB"/*

export DEVOPEN_TEST_LOG="$LOG"
export PATH="$STUB:$PATH"

# A project tree with ordinary and hostile names.
mkdir -p "$TREE/plain/nested/deep"
mkdir -p "$TREE/repo-a/.git" "$TREE/repo-b/sub/.git"
mkdir -p "$TREE/node_modules/junk"
mkdir -p "$TREE/space dir"
mkdir -p "$TREE/quote'sq\"dq"
mkdir -p "$TREE/semi;touch HOSTILE_SEMI"
mkdir -p "$TREE/\$(touch HOSTILE_SUB)"
mkdir -p "$TREE/\`touch HOSTILE_TICK\`"
mkdir -p "$TREE/amp&&touch HOSTILE_AMP"
mkdir -p "$TREE/uni-café-日本"
mkdir -p "$TREE/$(printf 'tab\tname')"

# Fresh XDG sandbox + config for one test.
new_env() { # new_env <config-json>
  ENVDIR="$TMP/env.$RANDOM"
  mkdir -p "$ENVDIR/config/devopen" "$ENVDIR/cache" "$ENVDIR/data"
  export XDG_CONFIG_HOME="$ENVDIR/config"
  export XDG_CACHE_HOME="$ENVDIR/cache"
  export XDG_DATA_HOME="$ENVDIR/data"
  if [[ -n ${1-} ]]; then printf '%s' "$1" >"$ENVDIR/config/devopen/config.json"; fi
}

basic_config() {
  jq -n --arg tree "$TREE" '{
    scan: { roots: [{path:$tree, depth:2}], gitRepos:true, allDirs:true, zoxide:false, cacheTtl:120,
            ignore:["node_modules"] },
    pinned: [],
    tools: {
      rec:  {label:"Rec",  icon:"R", description:"records cwd", type:"tui", appId:"test.rec",
             command:"pwd >> \($tree)/../cwd.log"},
      gui:  {label:"Gui",  icon:"G", description:"gui tool",    type:"gui",
             command:"pwd >> \($tree)/../cwd.log"},
      arg:  {label:"Arg",  icon:"A", description:"uses {dir}",  type:"gui",
             command:"printf \"%s\\n\" {dir} >> \($tree)/../arg.log"},
      nope: {label:"Nope", icon:"N", description:"missing bin", type:"gui",
             command:"definitely-not-installed-xyz {dir}"}
    },
    presets: {
      both:    {label:"Both",    icon:"B", description:"two steps", steps:["rec","gui"]},
      blocked: {label:"Blocked", icon:"X", description:"needs missing tool", steps:["rec","nope"]}
    }
  }'
}

run() { "$DEVOPEN" "$@" 2>&1; }

# Source the script as a library to unit-test its functions.
load_lib() {
  # shellcheck disable=SC1090
  DEVOPEN_LIB_ONLY=1 source "$DEVOPEN"
}

# =============================================================== path units ==

group "paths"

  new_env "$(basic_config)"
  load_lib
  assert_eq "expand_path ~"            "$HOME"            "$(expand_path '~')"
  assert_eq "expand_path ~/x"          "$HOME/x"          "$(expand_path '~/x')"
  assert_eq "expand_path absolute"     "/etc/hosts"       "$(expand_path '/etc/hosts')"
  assert_eq "expand_path relative"     "rel/path"         "$(expand_path 'rel/path')"
  assert_eq "expand_path ~notuser"     "~notuser/x"       "$(expand_path '~notuser/x')"
  assert_eq "expand_path no eval"      '$(id)'            "$(expand_path '$(id)')"
  assert_eq "expand_path empty"        ""                 "$(expand_path '')"
  assert_eq "tilde_path home"          "~"                "$(tilde_path "$HOME")"
  assert_eq "tilde_path under home"    "~/Projects/x"     "$(tilde_path "$HOME/Projects/x")"
  assert_eq "tilde_path outside"       "/opt/thing"       "$(tilde_path '/opt/thing')"
  assert_eq "tilde_path homelike"      "/home/other/x"    "$(tilde_path '/home/other/x')"
  assert_eq "roundtrip spaces"         "$HOME/a b/c"      "$(expand_path "$(tilde_path "$HOME/a b/c")")"
  assert_eq "roundtrip unicode"        "$HOME/café/日本"   "$(expand_path "$(tilde_path "$HOME/café/日本")")"


# ==================================================================== config ==

group "config"

  new_env ""
  out=$(run version)
  assert_eq "auto-creates config"   "0" "$([[ -f $XDG_CONFIG_HOME/devopen/config.json ]] && echo 0 || echo 1)"
  assert_contains "version prints"  "devopen" "$out"

  new_env "$(basic_config)"
  out=$(run tools)
  assert_contains "tools lists tool"    "rec"  "$out"
  assert_contains "tools lists preset"  "both" "$out"

  # malformed JSON must not crash or execute anything
  new_env '{ this is not json'
  assert_rc "malformed config: doctor still exits 0" 0 "$DEVOPEN" doctor
  out=$(run doctor)
  assert_contains "malformed config is reported" "not valid JSON" "$out"
  out=$(run dirs)
  assert_eq "malformed config yields no dirs" "" "$out"

  # empty object config
  new_env '{}'
  assert_rc "empty config: doctor ok" 0 "$DEVOPEN" doctor
  assert_rc "empty config: dirs ok"   0 "$DEVOPEN" dirs

  # config with no tools at all
  new_env '{"tools":{},"presets":{},"scan":{"roots":[]}}'
  out=$(run tools)
  assert_rc "no tools: tools cmd ok" 0 "$DEVOPEN" tools

  # jq's `//` treats false as absent, so `false` must be read back as false
  # rather than silently reverting to the default.
  new_env '{"scan":{"gitRepos":false,"allDirs":false,"zoxide":false,"cacheTtl":0},"tools":{},"presets":{}}'
  load_lib
  assert_eq "cfg_bool reads explicit false" "false" "$(cfg_bool '.scan.gitRepos' true)"
  assert_eq "cfg_bool reads explicit true"  "true"  "$(cfg_bool '.scan.nothingHere' true)"
  assert_eq "cfg_bool rejects non-boolean"  "true"  "$(cfg_bool '.scan.cacheTtl' true)"
  assert_eq "cfg_int reads zero"            "0"     "$(cfg_int '.scan.cacheTtl' 120)"
  assert_eq "cfg_int default when absent"   "120"   "$(cfg_int '.scan.nothingHere' 120)"
  assert_eq "cfg_int rejects non-numeric"   "120"   "$(cfg_int '.scan.gitRepos' 120)"


# ================================================================== scanning ==

group "scan"

  new_env "$(basic_config)"
  out=$(run dirs)
  assert_contains "finds plain dir"       "$TREE/plain"   "$out"
  assert_contains "finds git repo a"      "$TREE/repo-a"  "$out"
  assert_contains "finds nested git repo" "$TREE/repo-b/sub" "$out"
  assert_contains "marks git kind"        "git" "$(run dirs | grep -F "$TREE/repo-a")"
  assert_not_contains "honours ignore list" "node_modules" "$out"
  assert_not_contains "no .git dirs leak"   "/.git" "$out"
  assert_contains "finds unicode dir"     "uni-café-日本" "$out"
  assert_contains "finds spaced dir"      "space dir"    "$out"

  # depth is honoured: depth=2 from root reaches plain/nested but not plain/nested/deep
  assert_contains     "depth 2 includes level 2" "$TREE/plain/nested" "$out"
  assert_not_contains "depth 2 excludes level 3" "$TREE/plain/nested/deep" "$out"

  # dedup: a path must appear exactly once
  dupes=$(run dirs | awk '{$1=""; print}' | sort | uniq -d)
  assert_eq "no duplicate paths" "" "$dupes"

  # pinned first
  new_env "$(basic_config | jq --arg t "$TREE" '.pinned=[($t+"/plain/nested")]')"
  first=$(run dirs | head -1)
  assert_contains "pinned sorts first" "pinned" "$first"
  assert_contains "pinned is the right dir" "plain/nested" "$first"

  # toggles
  new_env "$(basic_config | jq '.scan.gitRepos=false')"
  assert_eq "gitRepos=false emits no git rows" "" "$(run dirs | awk '$1=="git"')"
  new_env "$(basic_config | jq '.scan.allDirs=false')"
  out=$(run dirs)
  assert_contains     "allDirs=false keeps git rows" "repo-a" "$out"
  assert_not_contains "allDirs=false drops plain dirs" "/plain/nested" "$out"

  # missing root is skipped silently
  new_env "$(basic_config | jq '.scan.roots += [{path:"/nonexistent-xyz", depth:2}]')"
  assert_rc "missing root does not fail" 0 "$DEVOPEN" dirs


# ===================================================================== cache ==

group "cache"

  new_env "$(basic_config)"
  run dirs >/dev/null
  assert_file "cache written" "$XDG_CACHE_HOME/devopen/dirs.tsv"

  before=$(run dirs | wc -l)
  mkdir -p "$TREE/brand-new-dir"
  after=$(run dirs | wc -l)
  assert_eq "cache hit ignores new dir" "$before" "$after"
  forced=$(run dirs --force | wc -l)
  assert_eq "--force picks up new dir" "$((before+1))" "$forced"
  rmdir "$TREE/brand-new-dir"

  # ttl=0 means always rescan
  new_env "$(basic_config | jq '.scan.cacheTtl=0')"
  run dirs >/dev/null
  mkdir -p "$TREE/ttl-zero-dir"
  assert_contains "cacheTtl=0 rescans" "ttl-zero-dir" "$(run dirs)"
  rmdir "$TREE/ttl-zero-dir"

  # corrupt/garbage cache must not break or leak
  new_env "$(basic_config)"
  run dirs >/dev/null
  printf 'garbage without tabs\n\n\t\n' >"$XDG_CACHE_HOME/devopen/dirs.tsv"
  assert_rc "garbage cache does not crash" 0 "$DEVOPEN" dirs
  assert_rc "sync rebuilds cache" 0 "$DEVOPEN" sync
  assert_contains "rebuilt cache has real dirs" "repo-a" "$(run dirs)"


# ============================================================ tools/presets ==

group "tools"

  new_env "$(basic_config)"
  load_lib
  assert_rc "tool_exists rec"        0 tool_exists rec
  assert_rc "tool_exists missing"    1 tool_exists nosuchtool
  assert_rc "preset_exists both"     0 preset_exists both
  assert_rc "preset_exists missing"  1 preset_exists nosuchpreset
  assert_rc "tool_available rec"     0 tool_available rec
  assert_rc "tool_available nope"    1 tool_available nope
  assert_eq "tool_binary first word" "definitely-not-installed-xyz" "$(tool_binary nope)"

  out=$(run doctor)
  assert_contains "doctor flags missing binary" "missing: definitely-not-installed-xyz" "$out"
  assert_contains "doctor lists available tool" "available" "$out"


# ==================================================================== launch ==

group "launch"

  new_env "$(basic_config)"
  : >"$LOG"; rm -f "$TMP/cwd.log" "$TMP/arg.log"

  "$DEVOPEN" open rec "$TREE/plain" >/dev/null 2>&1; sleep 0.6
  assert_contains "tui launch lands in dir"  "$TREE/plain" "$(cat "$TMP/cwd.log" 2>/dev/null)"
  assert_contains "tui launch sets app-id"   "appid=test.rec" "$(cat "$LOG")"

  : >"$LOG"; rm -f "$TMP/cwd.log"
  "$DEVOPEN" open gui "$TREE/plain" >/dev/null 2>&1; sleep 0.6
  assert_contains "gui launch goes via uwsm" "GUI" "$(cat "$LOG")"
  assert_contains "gui launch lands in dir"  "$TREE/plain" "$(cat "$TMP/cwd.log" 2>/dev/null)"

  rm -f "$TMP/arg.log"
  "$DEVOPEN" open arg "$TREE/space dir" >/dev/null 2>&1; sleep 0.6
  assert_eq "{dir} substituted, spaces intact" "$TREE/space dir" "$(cat "$TMP/arg.log" 2>/dev/null)"

  # preset runs every step
  : >"$LOG"; rm -f "$TMP/cwd.log"
  "$DEVOPEN" open both "$TREE/plain" >/dev/null 2>&1; sleep 1.2
  assert_eq "preset runs both steps" "2" "$(grep -c . "$TMP/cwd.log" 2>/dev/null || echo 0)"

  # errors
  assert_rc "open with missing args"     1 "$DEVOPEN" open rec
  assert_rc "open unknown tool"          1 "$DEVOPEN" open nosuchtool "$TREE/plain"
  assert_rc "open nonexistent dir"       1 "$DEVOPEN" open rec "/nonexistent-xyz"
  out=$(run open rec /nonexistent-xyz)
  assert_contains "nonexistent dir message" "not a directory" "$out"

  # a file is not a directory
  touch "$TMP/afile"
  assert_rc "open a file, not a dir" 1 "$DEVOPEN" open rec "$TMP/afile"

  # dry run must not launch
  : >"$LOG"; rm -f "$TMP/cwd.log"
  out=$(DEVOPEN_DRY_RUN=1 "$DEVOPEN" open rec "$TREE/plain" 2>&1)
  assert_contains  "dry run prints command" "omarchy-launch-tui" "$out"
  assert_no_file   "dry run launched nothing" "$TMP/cwd.log"


# ======================================================================= cli ==

group "cli"

  new_env "$(basic_config)"
  assert_rc "help exits 0"            0 "$DEVOPEN" help
  assert_rc "--help exits 0"          0 "$DEVOPEN" --help
  assert_rc "version exits 0"         0 "$DEVOPEN" version
  assert_rc "doctor exits 0"          0 "$DEVOPEN" doctor
  assert_rc "dirs exits 0"            0 "$DEVOPEN" dirs
  assert_rc "tools exits 0"           0 "$DEVOPEN" tools
  assert_rc "sync exits 0"            0 "$DEVOPEN" sync
  assert_rc "unknown command exits 1" 1 "$DEVOPEN" definitely-not-a-command
  out=$(run definitely-not-a-command)
  assert_contains "unknown command explains" "unknown command" "$out"
  out=$(run help)
  assert_contains "help mentions where" "devopen where" "$out"
  assert_contains "help mentions config path" "config.json" "$out"


# ================================================================== security ==

group "security"

  new_env "$(basic_config)"

  # --- command injection through directory names -------------------------
  rm -f "$TREE"/HOSTILE_* "$TMP"/HOSTILE_* HOSTILE_* 2>/dev/null
  for d in "$TREE/semi;touch HOSTILE_SEMI" "$TREE/\$(touch HOSTILE_SUB)" \
           "$TREE/\`touch HOSTILE_TICK\`" "$TREE/amp&&touch HOSTILE_AMP" \
           "$TREE/quote'sq\"dq"; do
    "$DEVOPEN" open rec "$d" >/dev/null 2>&1
  done
  sleep 1.2
  hostile=$(find "$TREE" "$TMP" . -maxdepth 2 -name 'HOSTILE_*' -type f 2>/dev/null | head -5)
  assert_eq "no command injection via directory name" "" "$hostile"

  # every hostile dir still opened in the correct place
  logged=$(grep -c . "$TMP/cwd.log" 2>/dev/null || echo 0)
  assert_eq "all hostile dirs launched correctly" "5" "$logged"

  # --- arithmetic injection through config values ------------------------
  #
  # Bash evaluates array subscripts inside (( )) and $(( )), so an unvalidated
  # config value reaching arithmetic is remote code execution. `set -u` blocks
  # the `x[$(cmd)]` form only because `x` is unset — an always-defined array
  # like PIPESTATUS walks straight past it, so that is what these use.
  payload() { printf 'PIPESTATUS[$(touch %s)]' "$1"; }

  # cacheTtl is only compared once a cache exists, so this must run twice.
  rm -f "$TMP/ARITH_TTL"
  new_env "$(basic_config | jq --arg v "$(payload "$TMP/ARITH_TTL")" '.scan.cacheTtl = $v')"
  "$DEVOPEN" dirs >/dev/null 2>&1
  "$DEVOPEN" dirs >/dev/null 2>&1
  assert_no_file "no RCE via scan.cacheTtl" "$TMP/ARITH_TTL"

  rm -f "$TMP/ARITH_DEPTH"
  new_env "$(basic_config | jq --arg v "$(payload "$TMP/ARITH_DEPTH")" '.scan.roots[0].depth = $v')"
  "$DEVOPEN" dirs >/dev/null 2>&1
  assert_no_file "no RCE via scan.roots[].depth" "$TMP/ARITH_DEPTH"

  # dirMaxHeight is read inside pick_dir, so exercise it where it is used.
  rm -f "$TMP/ARITH_HEIGHT"
  new_env "$(basic_config | jq --arg v "$(payload "$TMP/ARITH_HEIGHT")" '.menu.dirMaxHeight = $v')"
  DEVOPEN_LIB_ONLY=1 bash -c "source '$DEVOPEN'
    height=\$(cfg_int '.menu.dirMaxHeight' 0); (( height > 0 )); true" 2>/dev/null
  assert_no_file "no RCE via menu.dirMaxHeight" "$TMP/ARITH_HEIGHT"

  rm -f "$TMP/ARITH_WIDTH"
  new_env "$(basic_config | jq --arg v "$(payload "$TMP/ARITH_WIDTH")" '.menu.toolWidth = $v')"
  DEVOPEN_LIB_ONLY=1 bash -c "source '$DEVOPEN'
    w=\$(cfg_int '.menu.toolWidth' 440); (( w > 0 )); true" 2>/dev/null
  assert_no_file "no RCE via menu.toolWidth" "$TMP/ARITH_WIDTH"

  rm -f "$TMP/ARITH_ZOX"
  new_env "$(basic_config | jq --arg v "$(payload "$TMP/ARITH_ZOX")" '.scan.zoxideLimit = $v | .scan.zoxide = true')"
  "$DEVOPEN" dirs >/dev/null 2>&1
  assert_no_file "no RCE via scan.zoxideLimit" "$TMP/ARITH_ZOX"

  # a non-numeric value must fall back to the default, not crash
  new_env "$(basic_config | jq '.scan.cacheTtl = "not-a-number" | .scan.roots[0].depth = "abc"')"
  assert_rc "non-numeric config values fall back safely" 0 "$DEVOPEN" dirs

  # --- the TSV row protocol ----------------------------------------------
  new_env "$(basic_config)"
  load_lib
  # A directory whose basename contains a tab must not desync the row format:
  # the row must still have exactly 3 fields so the path survives round-trip.
  tabdir="$TREE/$(printf 'tab\tname')"
  if [[ -d $tabdir ]]; then
    row=$(menu_row "󰉋" "$(basename "$tabdir")" "$(tilde_path "$tabdir")")
    fields=$(awk -F'\t' '{print NF}' <<<"$row")
    assert_eq "tab in dirname keeps 3-field row" "3" "$fields"
  else
    skip "tab in dirname keeps 3-field row" "could not create tab dir"
  fi
  assert_eq "newline in name is flattened" "a b" "$(flatten "$(printf 'a\nb')")"
  assert_eq "cr in name is flattened"      "a b" "$(flatten "$(printf 'a\rb')")"
  assert_eq "menu_row always 3 fields"     "3" \
    "$(awk -F'\t' '{print NF}' <<<"$(menu_row "$(printf 'i\tx')" "$(printf 'l\tx')" "$(printf 's\tx')")")"

  # a newline in a directory name must not become a bogus picker entry
  nldir="$TREE/$(printf 'nl\nname')"
  if mkdir -p "$nldir" 2>/dev/null; then
    new_env "$(basic_config)"
    bad=$("$DEVOPEN" dirs --force 2>/dev/null | awk '$2 !~ /^\// && NF' | head -3)
    assert_eq "newline dirname yields no malformed rows" "" "$bad"
    rm -rf "$nldir"
  else
    skip "newline dirname yields no malformed rows" "could not create newline dir"
  fi

  # --- path traversal / absolute escapes ---------------------------------
  new_env "$(basic_config)"
  assert_rc "traversal to nonexistent is rejected" 1 "$DEVOPEN" open rec "$TREE/../../nonexistent-xyz"

  # --- the cache file is not world-writable ------------------------------
  new_env "$(basic_config)"
  "$DEVOPEN" dirs >/dev/null 2>&1
  perms=$(stat -c %a "$XDG_CACHE_HOME/devopen/dirs.tsv" 2>/dev/null)
  if [[ ${perms: -1} =~ [2367] ]]; then
    no "cache file not world-writable" "perms=$perms"
  else
    ok "cache file not world-writable"
  fi

  # --- config is not executed as shell ------------------------------------
  rm -f "$TMP/CFG_EXEC"
  new_env "$(basic_config | jq --arg p "$TMP/CFG_EXEC" '.tools.rec.label = "$(touch \($p))"')"
  "$DEVOPEN" tools >/dev/null 2>&1
  "$DEVOPEN" doctor >/dev/null 2>&1
  assert_no_file "tool label is not shell-evaluated" "$TMP/CFG_EXEC"


# =================================================================== picker ==
#
# Drives the full keybinding flow with the menu stubbed out: the stub records
# the rows it was offered and replies with a chosen one, exactly as the real
# omarchy-menu-select does (label, or label<TAB>subtext).

group "picker"

  cat >"$STUB/omarchy-menu-select" <<'EOF'
#!/bin/bash
prompt="$1"; shift
opts=(); while (($#)); do [[ $1 == "--" ]] && break; opts+=("$1"); shift; done
(( ${#opts[@]} == 0 )) && mapfile -t opts
printf '%s\n' "${opts[@]}" >"$DEVOPEN_ROWS_FILE.$(tr -dc a-z </dev/urandom|head -c4)"
printf '%s\n' "${opts[@]}" >>"$DEVOPEN_ROWS_FILE"
# Reply with the row whose label matches DEVOPEN_PICK_<n>, dropping the glyph.
want="$DEVOPEN_PICK"
[[ $prompt == Where* ]] && want="$DEVOPEN_PICK_DIR"
for o in "${opts[@]}"; do
  rest="${o#*$'\t'}"                 # drop glyph -> "label<TAB>subtext"
  label="${rest%%$'\t'*}"
  [[ $label == "$want" ]] && { printf '%s\n' "$rest"; exit 0; }
done
exit 1
EOF
  cat >"$STUB/omarchy-menu-input" <<'EOF'
#!/bin/bash
printf '%s\n' "$DEVOPEN_TYPED"
EOF
  chmod +x "$STUB/omarchy-menu-select" "$STUB/omarchy-menu-input"
  export DEVOPEN_ROWS_FILE="$TMP/rows.txt"

  new_env "$(basic_config)"
  : >"$DEVOPEN_ROWS_FILE"; rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="plain" "$DEVOPEN" menu >/dev/null 2>&1
  sleep 0.6
  assert_contains "menu flow launches chosen tool in chosen dir" \
    "$TREE/plain" "$(cat "$TMP/cwd.log" 2>/dev/null)"

  # every offered row must carry exactly three tab-separated fields
  bad=$(awk -F'\t' 'NF!=3' "$DEVOPEN_ROWS_FILE" | head -3)
  assert_eq "every menu row has 3 fields" "" "$bad"

  # unavailable tools and presets needing them are hidden
  rowsfile=$(cat "$DEVOPEN_ROWS_FILE")
  assert_not_contains "missing tool hidden from picker"   "Nope"    "$rowsfile"
  assert_not_contains "preset needing it hidden"          "Blocked" "$rowsfile"
  assert_contains     "available preset offered"          "Both"    "$rowsfile"

  # a tab in a directory name must still open that exact directory
  tabdir="$TREE/$(printf 'tab\tname')"
  if [[ -d $tabdir ]]; then
    : >"$DEVOPEN_ROWS_FILE"; rm -f "$TMP/cwd.log"
    DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="tab name" "$DEVOPEN" menu >/dev/null 2>&1
    sleep 0.6
    got=$(cat "$TMP/cwd.log" 2>/dev/null)
    assert_eq "tab-named dir resolves to the real path" "$tabdir" "$got"
  else
    skip "tab-named dir resolves to the real path" "no tab dir"
  fi

  # cancelling the tool picker must launch nothing
  rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="__nothing__" DEVOPEN_PICK_DIR="plain" "$DEVOPEN" menu >/dev/null 2>&1
  sleep 0.4
  assert_no_file "cancelling tool picker launches nothing" "$TMP/cwd.log"

  # cancelling the directory picker must launch nothing
  rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="__nothing__" "$DEVOPEN" menu >/dev/null 2>&1
  sleep 0.4
  assert_no_file "cancelling dir picker launches nothing" "$TMP/cwd.log"

  # "Type a path…" routes to the input prompt
  rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="Type a path…" DEVOPEN_TYPED="$TREE/repo-a" \
    "$DEVOPEN" menu >/dev/null 2>&1
  sleep 0.6
  assert_contains "typed path is opened" "$TREE/repo-a" "$(cat "$TMP/cwd.log" 2>/dev/null)"

  # a typed path that does not exist is refused, not launched
  rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="Type a path…" DEVOPEN_TYPED="/nonexistent-xyz" \
    "$DEVOPEN" menu >/dev/null 2>&1
  sleep 0.4
  assert_no_file "typed nonexistent path launches nothing" "$TMP/cwd.log"

  # reverse order flow
  rm -f "$TMP/cwd.log"
  DEVOPEN_PICK="Rec" DEVOPEN_PICK_DIR="repo-a" "$DEVOPEN" where >/dev/null 2>&1
  sleep 0.6
  assert_contains "where flow works" "$TREE/repo-a" "$(cat "$TMP/cwd.log" 2>/dev/null)"

  rm -f "$STUB/omarchy-menu-select" "$STUB/omarchy-menu-input"

# ================================================================== install ==

group "install"

  FAKE="$TMP/fakehome"
  mkdir -p "$FAKE/.config/omarchy/plugins" "$FAKE/.config/hypr" "$FAKE/.local/bin"
  jq -n '{bar:{layout:{left:[{id:"omarchy.menu"}],center:[],right:[]}}}' \
    >"$FAKE/.config/omarchy/shell.json"
  cat >"$FAKE/.config/hypr/bindings.lua" <<'EOF'
-- my own bindings
o.bind("SUPER + A", "App switcher", "app-switch")
o.bind("SUPER + Z", "My own devopen menu alias", "devopen menu")
EOF
  cp "$FAKE/.config/hypr/bindings.lua" "$TMP/bindings.orig"

  inst() { env HOME="$FAKE" XDG_BIN_HOME="$FAKE/.local/bin" \
                XDG_DATA_HOME="$FAKE/.local/share" XDG_CONFIG_HOME="$FAKE/.config" \
                bash "$REPO/install.sh" "$@" 2>&1; }
  uninst() { env HOME="$FAKE" XDG_BIN_HOME="$FAKE/.local/bin" \
                  XDG_DATA_HOME="$FAKE/.local/share" XDG_CONFIG_HOME="$FAKE/.config" \
                  bash "$REPO/uninstall.sh" "$@" 2>&1; }

  out=$(inst)
  assert_file "install: cli symlinked"    "$FAKE/.local/bin/devopen"
  assert_file "install: plugin linked"    "$FAKE/.config/omarchy/plugins/io.github.kurama07a.devopen"
  assert_file "install: config created"   "$FAKE/.config/devopen/config.json"
  assert_eq   "install: bar widget added" "1" \
    "$(jq '[.bar.layout.left[] | select(.id=="io.github.kurama07a.devopen")] | length' "$FAKE/.config/omarchy/shell.json")"
  assert_contains "install: keybind block added" ">>> devopen" "$(cat "$FAKE/.config/hypr/bindings.lua")"
  assert_eq "install: shell.json still valid json" "0" \
    "$(jq -e . "$FAKE/.config/omarchy/shell.json" >/dev/null 2>&1; echo $?)"

  # running it twice must not duplicate anything
  out=$(inst)
  assert_eq "reinstall: no duplicate bar entry" "1" \
    "$(jq '[.bar.layout.left[] | select(.id=="io.github.kurama07a.devopen")] | length' "$FAKE/.config/omarchy/shell.json")"
  assert_eq "reinstall: no duplicate keybind" "1" \
    "$(grep -cF '>>> devopen' "$FAKE/.config/hypr/bindings.lua")"
  assert_contains "reinstall: keeps existing config" "kept" "$out"

  # a user's own binding that merely mentions devopen must survive uninstall
  out=$(uninst)
  assert_no_file "uninstall: cli removed"     "$FAKE/.local/bin/devopen"
  assert_no_file "uninstall: plugin removed"  "$FAKE/.config/omarchy/plugins/io.github.kurama07a.devopen"
  assert_file    "uninstall: config kept"     "$FAKE/.config/devopen/config.json"
  assert_eq "uninstall: bar entry removed" "0" \
    "$(jq '[.. | objects | select(.id=="io.github.kurama07a.devopen")] | length' "$FAKE/.config/omarchy/shell.json")"
  assert_contains "uninstall: user's own binding survives" \
    'o.bind("SUPER + Z", "My own devopen menu alias", "devopen menu")' \
    "$(cat "$FAKE/.config/hypr/bindings.lua")"
  assert_not_contains "uninstall: managed block gone" ">>> devopen" \
    "$(cat "$FAKE/.config/hypr/bindings.lua")"
  assert_eq "uninstall: other bindings untouched" "0" \
    "$(diff <(grep -v 'devopen (managed' "$TMP/bindings.orig") \
            <(cat "$FAKE/.config/hypr/bindings.lua") >/dev/null 2>&1; echo $?)"
  assert_eq "uninstall: shell.json still valid json" "0" \
    "$(jq -e . "$FAKE/.config/omarchy/shell.json" >/dev/null 2>&1; echo $?)"

  # --purge drops the config too
  inst >/dev/null
  uninst --purge >/dev/null
  assert_no_file "uninstall --purge removes config" "$FAKE/.config/devopen"

# =================================================================== report ==

printf '\n%s────────────────────────────────────────%s\n' "$DIM" "$OFF"
printf '%s%d passed%s' "$GREEN" "$PASS" "$OFF"
(( FAIL )) && printf ', %s%d failed%s' "$RED" "$FAIL" "$OFF"
(( SKIP )) && printf ', %s%d skipped%s' "$YELLOW" "$SKIP" "$OFF"
printf '\n'

if (( FAIL )); then
  printf '\n%sFailures:%s\n' "$BOLD" "$OFF"
  for f in "${FAILURES[@]}"; do printf '  • %s\n' "$f"; done
  exit 1
fi
exit 0

# devopen

Open an editor, a coding agent, or a saved combination of both in any project
directory — from one keypress, through Omarchy's own menu.

Press <kbd>SUPER</kbd>+<kbd>D</kbd>:

1. **What do you want to open?** VS Code, Claude Code, Codex, Neovim, a
   terminal, the file manager, or one of your presets.
2. **Where?** A searchable list of your projects — recently visited folders
   first, then every git repo under your configured roots, then plain
   directories. Type to fuzzy-filter; pick `Type a path…` for anything else.

That's it. The tool launches in that directory.


## Why it works this way

Omarchy's menu supports a `provider:` field in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, but the provider list is
hardcoded in the shipped `Menu.qml` (`fonts`, `power-profiles`, and the native
`apps`) — a custom provider name is silently ignored. Rather than fork the menu
plugin or generate thousands of static JSONC rows, devopen drives the menu's
**`select` mode** through `omarchy-menu-select`. You get the real Omarchy menu,
themed and fuzzy-searchable, with a list computed fresh at open time.

## Install

Requires Omarchy, plus `jq` and `fd`. `zoxide` is optional but recommended —
it is what puts the folder you were just in at the top of the list.

```bash
omarchy plugin add https://github.com/Kurama07a/omarchy-devopen --enable
```

That installs the bar widget, and the widget works immediately: it runs the
`devopen` script from inside the plugin folder, so nothing needs to be on your
`PATH` first.

To also get the `devopen` command and the <kbd>SUPER</kbd>+<kbd>D</kbd>
keybinding, run the installer from the plugin folder:

```bash
cd ~/.config/omarchy/plugins/io.github.kurama07a.devopen
./install.sh
```

### Or from a checkout

```bash
git clone https://github.com/Kurama07a/omarchy-devopen ~/Projects/omarchy-devopen
cd ~/Projects/omarchy-devopen
./install.sh
```

This symlinks the CLI into `~/.local/bin`, links the checkout in as the plugin,
adds the widget to your bar, and binds <kbd>SUPER</kbd>+<kbd>D</kbd>. Everything
points back at the checkout, so `git pull` updates the installed copy.

```bash
./install.sh --no-bar              # CLI + keybinding only
./install.sh --no-keybinding       # skip the Hyprland binding
./install.sh --key "SUPER ALT + O" # use a different key
./uninstall.sh                     # undo it (--purge also drops your config)
```

The keybinding is written into `bindings.lua` inside a fenced
`>>> devopen` block, and `uninstall.sh` removes exactly that block — a binding
you wrote yourself that happens to mention devopen is left alone. Both scripts
back up any file they touch before editing it.

Check everything resolved:

```bash
devopen doctor
```

## Usage

| Command | What it does |
|---|---|
| `devopen` | Pick a tool, then a directory (the default) |
| `devopen where` | Pick the directory first, then the tool |
| `devopen open claude ~/Projects/app` | Skip the menu entirely |
| `devopen dirs` | Print the directories it found, with their kind |
| `devopen tools` | Print configured tools and presets |
| `devopen sync` | Rebuild the directory cache now |
| `devopen config` | Open the config in your editor |
| `devopen doctor` | Config, dependencies, roots, tools, and a count |

The bar widget does the same: left-click for tool-first, right-click for
directory-first.

Set `DEVOPEN_DRY_RUN=1` to print the command that would run instead of
launching it.

## Configuration

`~/.config/devopen/config.json`. Paths may use `~`.

### Where it looks for directories

```json
"scan": {
  "roots": [
    { "path": "~/Projects", "depth": 2 },
    { "path": "~/Work",     "depth": 2 }
  ],
  "gitRepos": true,
  "allDirs": true,
  "zoxide": true,
  "zoxideLimit": 40,
  "cacheTtl": 120,
  "ignore": ["node_modules", "target", ".venv"]
}
```

Three sources are merged, deduplicated, and shown in this order:

1. `pinned` — a hand-kept list, always first.
2. `zoxide` — your most frecent directories, so where you were working
   yesterday is one keystroke away.
3. `gitRepos` — every repo under the roots, found with `fd`.
4. `allDirs` — remaining directories up to each root's `depth`.

`depth` is per root and counts from that root. The `fd` sweep is cached for
`cacheTtl` seconds; zoxide is always read live.

### Tools

```json
"claude": {
  "label": "Claude Code",
  "icon": "󰪩",
  "description": "Coding agent in a terminal",
  "type": "tui",
  "appId": "org.omarchy.agent",
  "command": "claude --permission-mode bypassPermissions"
}
```

- `type: "gui"` launches via `uwsm-app`; `type: "tui"` opens Omarchy's terminal
  via `omarchy-launch-tui`.
- `command` is a shell command line. `{dir}` is replaced with the chosen
  directory, already quoted. It also runs *in* that directory, so `nvim .` and
  `code {dir}` both work.
- `appId` sets the window class for TUI tools, so Hyprland window rules can
  target them.
- A tool whose binary is missing is hidden from the menu automatically.

### Presets

A preset is just an ordered list of tools, launched together:

```json
"presets": {
  "code-claude": {
    "label": "VS Code + Claude",
    "icon": "󱓞",
    "description": "Editor, and Claude in a terminal beside it",
    "steps": ["code", "claude"]
  }
}
```

A preset only appears when every one of its steps is installed.

> **On "Claude inside the VS Code terminal":** VS Code has no CLI flag to run a
> command in its integrated terminal, and the only ways to force it — a
> generated `.vscode/tasks.json` with `runOn: folderOpen`, or a helper
> extension — write into your repo or need something installed per machine.
> `code-claude` therefore opens VS Code and a separate Omarchy terminal in the
> same directory. Tile them and it is the same workflow without touching your
> project files. Give the agent terminal its own `appId` and a Hyprland window
> rule if you want it to always land in a particular spot.

## Tests

```bash
./tests/run.sh            # everything
./tests/run.sh security   # one group
```

131 checks covering path handling, config parsing, scanning, caching, the
launch path, both picker flows, install/uninstall, and a security group. They
run against a throwaway XDG root and a throwaway directory tree, with the menu
and the launchers stubbed — nothing touches your real config or opens a window.

## Security notes

Everything below is enforced by a test in the `security` group.

- **Directory names are never interpolated into a shell command.** Paths reach
  the launcher through `printf %q`, so a directory called
  `` `touch owned` `` or `$(id)` or `a;rm -rf ~` opens normally and executes
  nothing. The suite creates directories with all of those names and asserts
  both halves: no side effect, and the right directory opened.
- **Numeric config values are validated before use.** Bash evaluates array
  subscripts inside `(( ))` and `$(( ))`, so an unchecked value like
  `PIPESTATUS[$(cmd)]` in `cacheTtl`, `depth`, `zoxideLimit`, or a menu width
  would be remote code execution. Note that `set -u` does *not* save you here:
  it blocks the `x[$(cmd)]` form only because `x` happens to be unset, and an
  always-defined array walks straight past it. Every such value is required to
  match `^[0-9]+$` and falls back to its default otherwise.
- **The menu's row format cannot be desynced by a crafted name.** Display text
  is flattened (tabs, newlines, carriage returns become spaces) so every row
  has exactly three fields, and the chosen directory is recovered from a lookup
  table rather than by re-parsing what the menu returned — a tab inside a
  directory name cannot redirect the launch somewhere else.
- **The config file is data, not code.** Labels, descriptions and paths are
  read with `jq` and never evaluated. A malformed config is reported by
  `devopen doctor` instead of crashing.

`devopen` runs entirely as your user, launches only what your config names, and
makes no network calls.

## License

MIT

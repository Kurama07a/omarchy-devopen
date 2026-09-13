import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Bar entry point for devopen. The picking, scanning and launching all live in
// the `devopen` shell script; this is only a button that runs it, so the bar
// and the keybinding stay exactly the same feature.
//
// The script is addressed by its path inside this plugin folder rather than by
// name, so the widget works as soon as the plugin is added — before install.sh
// has put `devopen` on PATH, and regardless of what PATH the shell inherited.
//
// How it is started matters as much as what is started. Three things are wrong
// with the obvious `bar.run("… menu")`, and each is fixed here:
//
//   * bar.run() takes a command *string* and hands it to `bash -lc`, a login
//     shell that sources your profile. Passing an argv array means no shell
//     parses this line at all — no quoting to get right, no profile sourced.
//
//   * Letting the script's own `#!` line start bash is already too late to
//     clean the environment. LD_PRELOAD is acted on by the dynamic loader
//     before bash's first instruction, and BASH_ENV is sourced by bash before
//     the script's first line. A seal *inside* the script cannot undo either.
//     So a fixed, root-owned interpreter is named explicitly here, and the
//     script is passed to it as an argument.
//
//   * clearEnvironment plus an explicit environment means that interpreter
//     starts from nothing but the variables named below. Nothing inherited
//     from whatever shell launched Quickshell reaches it.
//
// The script keeps its own internal seal and absolute tool resolution as
// defence in depth — this widget is the outer layer, not a replacement.
BarWidget {
  id: root
  moduleName: "io.github.kurama07a.devopen"

  readonly property string cli: Qt.resolvedUrl("bin/devopen").toString().replace(/^file:\/\//, "")

  // Root-owned, and the same interpreter the script's shebang asks for.
  readonly property string interpreter: "/usr/bin/bash"

  readonly property string trustedPath:
    "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

  // The session plumbing devopen needs to reach the omarchy menu and the app
  // daemon, named one by one. Anything not on this list — the loader
  // variables, BASH_ENV, everything else — is never forwarded.
  readonly property var sessionVars: [
    "HOME", "USER", "LOGNAME", "LANG",
    "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME",
    "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE",
    "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DISPLAY", "XAUTHORITY",
    "DBUS_SESSION_BUS_ADDRESS",
    // omarchy-menu-select shells out to omarchy-shell, which refuses to start
    // without OMARCHY_PATH — without it the picker silently never appears.
    "OMARCHY_PATH", "OMARCHY_SHELL_IPC_TIMEOUT"
  ]

  function launchEnvironment() {
    var env = { "PATH": root.trustedPath }

    for (var i = 0; i < root.sessionVars.length; i++) {
      var name = root.sessionVars[i]
      var value = Quickshell.env(name)
      if (value !== undefined && value !== null && value !== "") env[name] = value
    }

    // Your PATH, forwarded under a name of our own. devopen uses it for one
    // thing only: answering "which of *your* editors and agents are installed"
    // when it builds the picker, since those live in ~/.local/bin or a version
    // manager's shim directory. It never resolves anything devopen itself
    // runs. See the trust model at the top of bin/devopen.
    var userPath = Quickshell.env("PATH")
    if (userPath) env["DEVOPEN_USER_PATH"] = userPath

    return env
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: launcher
    clearEnvironment: true
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘔"
    horizontalMargin: 7.5
    tooltipText: "Open a project — right-click to pick the folder first"

    onPressed: function(mouseButton) {
      launcher.environment = root.launchEnvironment()
      launcher.command = [
        root.interpreter,
        root.cli,
        mouseButton === Qt.RightButton ? "where" : "menu"
      ]
      launcher.startDetached()
    }
  }
}

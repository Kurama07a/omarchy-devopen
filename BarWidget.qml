import QtQuick
import Quickshell
import qs.Ui

// Bar entry point for devopen. The picking, scanning and launching all live in
// the `devopen` shell script; this is only a button that runs it, so the bar
// and the keybinding stay exactly the same feature.
//
// The script is addressed by its path inside this plugin folder rather than by
// name, so the widget works as soon as the plugin is added — before install.sh
// has put `devopen` on PATH, and regardless of what PATH the shell inherited.
//
// It is started with execDetached's argv form rather than bar.run(), because
// bar.run() takes a command *string* and hands it to `bash -lc` — a login shell
// that sources your profile, and so resolves everything downstream through
// whatever PATH that profile builds. Passing argv means no shell parses this
// line at all: no quoting to get right, no profile sourced, and nothing between
// the click and the script.
BarWidget {
  id: root
  moduleName: "io.github.kurama07a.devopen"

  readonly property string cli: Qt.resolvedUrl("bin/devopen").toString().replace(/^file:\/\//, "")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘔"
    horizontalMargin: 7.5
    tooltipText: "Open a project — right-click to pick the folder first"

    onPressed: function(mouseButton) {
      Quickshell.execDetached([root.cli, mouseButton === Qt.RightButton ? "where" : "menu"])
    }
  }
}

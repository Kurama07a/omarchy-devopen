import QtQuick
import qs.Ui

// Bar entry point for devopen. The picking, scanning and launching all live in
// the `devopen` shell script; this is only a button that runs it, so the bar
// and the SUPER+D keybinding stay exactly the same feature.
BarWidget {
  id: root
  moduleName: "prakhar.devopen"

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
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) root.bar.run("devopen where")
      else root.bar.run("devopen menu")
    }
  }
}

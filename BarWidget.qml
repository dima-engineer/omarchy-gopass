import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.dima-engineer.gopass"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    tooltipText: "Gopass"
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.dima-engineer.gopass")
    }
  }
}

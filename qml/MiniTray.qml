import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick

// system tray icons for the mini dashboard (FunShell Tray.qml port).
// left click activates (or opens the menu for onlyMenu items like Discord),
// middle click secondary-activates, right click opens the context menu.
Row {
  id: root
  spacing: 8
  Repeater {
    model: SystemTray.items
    delegate: Item {
      id: item
      required property var modelData
      width: 16
      height: 16

      IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: item.modelData.icon
      }

      QsMenuAnchor {
        id: menuAnchor
        menu: item.modelData.menu
        anchor {
          item: item
          edges: Edges.Top | Edges.Left
          gravity: Edges.Bottom | Edges.Left
          margins.top: 4
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
            if (item.modelData.hasMenu) {
              menuAnchor.anchor.updateAnchor()
              menuAnchor.open()
            }
          } else if (mouse.button === Qt.MiddleButton) {
            item.modelData.secondaryActivate()
          } else if (item.modelData.onlyMenu && item.modelData.hasMenu) {
            menuAnchor.anchor.updateAnchor()
            menuAnchor.open()
          } else {
            item.modelData.activate()
          }
        }
      }
    }
  }
}

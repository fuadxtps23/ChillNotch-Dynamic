import QtQuick
import QtQuick.Layouts

Item {
  id: root
  property bool active: false
  property var notif: null

  anchors.centerIn: parent
  opacity: active ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: 150 } }

  RowLayout {
    anchors.centerIn: parent
    spacing: 10

    Text {
      text: String.fromCodePoint(0xf0f3)
      color: Theme.fg
      font { family: Theme.nerdFontFamily; pixelSize: 15 }
      visible: notifIcon.status !== Image.Ready
    }

    Image {
      id: notifIcon
      Layout.preferredWidth: 30 * box.dpi
      Layout.preferredHeight: 30 * box.dpi
      Layout.maximumWidth: 30 * box.dpi
      Layout.maximumHeight: 30 * box.dpi
      Layout.alignment: Qt.AlignVCenter
      fillMode: Image.PreserveAspectCrop
      clip: true
      source: {
        if (root.notif && root.notif.image) return root.notif.image
        if (root.notif && root.notif.appIcon) {
          return root.notif.appIcon.startsWith("/") 
            ? "file://" + root.notif.appIcon 
            : "image://icon/" + root.notif.appIcon
        }
        return ""
      }
      sourceSize: Qt.size(30 * box.dpi, 30 * box.dpi)
      visible: status === Image.Ready
    }

    ColumnLayout {
      spacing: 3
      Text {
        text: root.notif ? root.notif.summary : ""
        textFormat: Text.PlainText
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: 10; weight: 700 }
        elide: Text.ElideRight
        Layout.maximumWidth: 220
      }

      Text {
        text: root.notif ? root.notif.body.replace(
          /\[([^\]]+)\]\(["']?([^)"']+)["']?\)/g,
          '<a href="$2">$1</a>'
        ) : ""
        textFormat: Text.StyledText
        linkColor: Theme.accent
        color: "#9b9b9b"
        font { family: Theme.fontFamily; pixelSize: 9 }
        elide: Text.ElideRight
        Layout.maximumWidth: 220
        visible: text !== ""
      }
    }
  }
}

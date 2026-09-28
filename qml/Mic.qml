import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// microphone volume module (ported from FunShell Microphone.qml):
// default source volume as icon + percent, click toggles mute.
RowLayout {
  id: root
  spacing: 4 * Config.paddingScale

  readonly property var src: Pipewire.defaultAudioSource
  readonly property bool ready: src && src.ready
  readonly property bool muted: ready && src.audio.muted
  readonly property int micVol: ready ? Math.round(src.audio.volume * 100) : 0

  property string fg: Theme.fg
  property string mutedFg: "#fb2a2a"

  property string icon: {
    if (!ready) return String.fromCodePoint(0xf131)
    if (muted) return String.fromCodePoint(0xf131)
    return String.fromCodePoint(0xf130)
  }

  function toggleMute() {
    if (ready) src.audio.muted = !src.audio.muted
  }

  // icon
  Text {
    text: root.icon
    color: (root.muted || !root.ready) ? root.mutedFg : root.fg
    font.family: Theme.nerdFontFamily
    font.pixelSize: 10 * Config.pillScale
  }

  MouseArea {
    id: micMute
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onClicked: root.toggleMute()
  }

  // percentage
  Text {
    text: root.ready ? (root.muted ? "0%" : root.micVol + "%") : "-"
    color: root.fg
    font {
      pixelSize: 10 * Config.pillScale
      family: Theme.fontFamily
      weight: 500
    }
  }

  PwObjectTracker {
    objects: [root.src]
  }
}

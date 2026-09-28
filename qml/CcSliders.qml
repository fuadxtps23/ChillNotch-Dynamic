import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

Column {
  id: sliderColumnRoot
  spacing: 5

  // exposed properties
  property real sliderHeight: 4
  property real sliderRadius: 4
  property string sliderColor: "gray"
  property real sliderHitSlop: 8

  property string volIcon: ""
  property bool volMuted: false
  property real volPercent: 0   // 0-100
  property real volMax: 100

  property string brightnessIcon: ""
  property real brightnessPercent: 0  // 0-1

  // mic (read directly from Pipewire default source)
  readonly property var micSrc: Pipewire.defaultAudioSource
  readonly property bool micReady: micSrc && micSrc.ready
  readonly property bool micMuted: micReady ? micSrc.audio.muted : false
  readonly property real micPercent: micReady ? Math.min(micSrc.audio.volume, 1.0) : 0
  PwObjectTracker { objects: [sliderColumnRoot.micSrc] }

  property bool nightlightOn: false
  property real nightTemp: 5300  // 2500-6500

  signal volumeChangeRequested(real fraction)
  signal brightnessChangeRequested(real fraction)
  signal nightTempChangeRequested(real fraction)

  Timer { id: brightnessThrottle; interval: 80; repeat: false }

  // volume
  RowLayout {
    width: parent.width
    spacing: 14

    Text {
      id: volIconText
      text: volIcon
      color: volMuted ? "#fd2222" : Theme.fg
      font.family: Theme.nerdFontFamily
      font.pixelSize: 13
      Behavior on color { ColorAnimation { duration: 100 } }

      onTextChanged: volPulse.restart()
      scale: 1.0
      SequentialAnimation {
          id: volPulse
          NumberAnimation { target: volIconText; property: "scale"; to: 1.15; duration: 60 }
          NumberAnimation { target: volIconText; property: "scale"; to: 1.0; duration: 100 }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: sliderColumnRoot.sliderHeight
      radius: sliderColumnRoot.sliderRadius
      color: Theme.bg5

      Rectangle {
        width: parent.width * Math.min(volPercent / volMax, 1.0)
        height: parent.height
        radius: sliderColumnRoot.sliderRadius
        color: sliderColumnRoot.sliderColor
        Behavior on width {
          SpringAnimation {
            spring: 15.5
            damping: 1.8
            epsilon: 0.40
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -sliderColumnRoot.sliderHitSlop
        anchors.bottomMargin: -sliderColumnRoot.sliderHitSlop
        onClicked: (mouse) => {
          volumeChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
        }
        onPositionChanged: (mouse) => {
          if (pressed)
            volumeChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
        }
      }
    }

    Text {
      id: volVal
      text: volMuted ? "muted" : Math.round(volPercent) + "%"
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: 10
      Layout.minimumWidth: 35
      onTextChanged: valPulse.restart()
      SequentialAnimation {
        id: valPulse
        NumberAnimation { target: volVal; property: "scale"; to: 0.9; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: volVal; property: "scale"; to: 1.0; duration: 120; easing.type: Easing.OutQuad }
      }
    }
  }

  // mic
  RowLayout {
    width: parent.width
    spacing: 14

    Text {
      id: micIconText
      text: sliderColumnRoot.micMuted || !sliderColumnRoot.micReady
        ? String.fromCodePoint(0xf131) : String.fromCodePoint(0xf130)
      color: (sliderColumnRoot.micMuted || !sliderColumnRoot.micReady) ? "#fb2a2a" : Theme.fg
      font.family: Theme.nerdFontFamily
      font.pixelSize: 13
      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Rectangle {
      Layout.fillWidth: true
      height: sliderColumnRoot.sliderHeight
      radius: sliderColumnRoot.sliderRadius
      color: Theme.bg5

      Rectangle {
        width: parent.width * sliderColumnRoot.micPercent
        height: parent.height
        radius: sliderColumnRoot.sliderRadius
        color: sliderColumnRoot.sliderColor
        Behavior on width {
          SpringAnimation {
            spring: 15.5
            damping: 1.8
            epsilon: 0.40
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -sliderColumnRoot.sliderHitSlop
        anchors.bottomMargin: -sliderColumnRoot.sliderHitSlop
        onClicked: (mouse) => {
          if (sliderColumnRoot.micReady)
            sliderColumnRoot.micSrc.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
        }
        onPositionChanged: (mouse) => {
          if (pressed && sliderColumnRoot.micReady)
            sliderColumnRoot.micSrc.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
        }
      }
    }
    Text {
      text: !sliderColumnRoot.micReady ? "-"
        : (sliderColumnRoot.micMuted ? "muted" : Math.round(sliderColumnRoot.micSrc.audio.volume * 100) + "%")
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: 10
      Layout.minimumWidth: 35
    }
  }

  // brightness
  RowLayout {
    width: parent.width
    spacing: 14

    Text {
      id: blIcon
      text: brightnessIcon
      color: Theme.fg
      font.family: Theme.nerdFontFamily
      font.pixelSize: 13

      onTextChanged: blPulse.restart()
      scale: 1.0
      SequentialAnimation {
          id: blPulse
          NumberAnimation { target: blIcon; property: "scale"; to: 1.15; duration: 60 }
          NumberAnimation { target: blIcon; property: "scale"; to: 1.0; duration: 100 }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: sliderColumnRoot.sliderHeight
      radius: sliderColumnRoot.sliderRadius
      color: Theme.bg5

      Rectangle {
        width: parent.width * brightnessPercent
        height: parent.height
        radius: sliderColumnRoot.sliderRadius
        color: sliderColumnRoot.sliderColor
        Behavior on width {
          SpringAnimation {
            spring: 15.5
            damping: 1.8
            epsilon: 0.40
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -sliderColumnRoot.sliderHitSlop
        anchors.bottomMargin: -sliderColumnRoot.sliderHitSlop
        onClicked: (mouse) => {
          brightnessChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
        }
        onPositionChanged: (mouse) => {
          if (pressed && !brightnessThrottle.running) {
            brightnessChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
            brightnessThrottle.start()
          }
        }
      }
    }

    Text {
      id: btVal
      text: Math.round(brightnessPercent * 100) + "%"
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: 10
      Layout.minimumWidth: 35
      onTextChanged: btPulse.restart()
      SequentialAnimation {
          id: btPulse
          NumberAnimation { target: btVal; property: "scale"; to: 0.9; duration: 60; easing.type: Easing.OutQuad }
          NumberAnimation { target: btVal; property: "scale"; to: 1.0; duration: 120; easing.type: Easing.OutQuad }
      }
    }
  }

  // night light temperature (only when night light is on)
  RowLayout {
    width: parent.width
    spacing: 14
    visible: sliderColumnRoot.nightlightOn

    Text {
      text: "\uf186"
      color: "#ff922b"
      font.family: Theme.nerdFontFamily
      font.pixelSize: 13
    }
    Rectangle {
      Layout.fillWidth: true
      height: sliderColumnRoot.sliderHeight
      radius: sliderColumnRoot.sliderRadius
      color: Theme.bg5

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, (sliderColumnRoot.nightTemp - 2500) / 4000))
        height: parent.height
        radius: sliderColumnRoot.sliderRadius
        color: "#ff922b"
        Behavior on width {
          SpringAnimation {
            spring: 15.5
            damping: 1.8
            epsilon: 0.40
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -sliderColumnRoot.sliderHitSlop
        anchors.bottomMargin: -sliderColumnRoot.sliderHitSlop
        onClicked: (mouse) => {
          nightTempChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
        }
        onPositionChanged: (mouse) => {
          if (pressed)
            nightTempChangeRequested(Math.max(0, Math.min(1, mouse.x / width)))
        }
      }
    }
    Text {
      text: Math.round(sliderColumnRoot.nightTemp) + "K"
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: 10
      Layout.minimumWidth: 35
    }
  }
}

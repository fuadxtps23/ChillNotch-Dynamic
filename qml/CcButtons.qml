import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import IslandBackend

ColumnLayout {
  id: root
  spacing: 8 * root.dpi

  readonly property real dpi: Config.dpiScale

  property real buttonWidth
  property real buttonHeight
  property real buttonRadius
  property color buttonBgOff
  property color buttonFgOff

  property bool notificationPopup: false
  property bool controlCenterOpen: false
  property bool mediaAutoOpened: false
  property bool wifiPanelOpened: false
  property bool btPanelOpened: false
  property bool hasPlayer: false
  property real playerHeight: 0

  anchors.top: parent.top
  anchors.topMargin: hasPlayer ? playerHeight + 93 : 5
  anchors.left: parent.left
  anchors.right: parent.right
  anchors.leftMargin: 3 * dpi
  anchors.rightMargin: 5 * dpi

  // keyboard (wvkbd on-screen keyboard)
  property bool oskVisible: false
  // idle inhibitor
  property bool inhibitorActive: false
  // night light (hyprsunset)
  property bool nightlightOn: false
  property int nightTemp: 5300

  function toggleOsk() {
    if (oskVisible) {
      Quickshell.execDetached(["pkill", "-USR1", "-x", "wvkbd-mobintl"])
      oskVisible = false
    } else {
      // start it (hidden) if not already running, then show
      Quickshell.execDetached(["/bin/sh", "-c",
        "pgrep -x wvkbd-mobintl >/dev/null 2>&1 || (wvkbd-mobintl --hidden -L 280 &)"])
      Quickshell.execDetached(["pkill", "-USR2", "-x", "wvkbd-mobintl"])
      oskVisible = true
    }
  }

  function toggleInhibitor() {
    inhibitorActive = !inhibitorActive
    if (inhibitorActive)
      Quickshell.execDetached(["systemd-inhibit", "--what=idle:handle-lid-switch",
        "--mode=block", "/bin/sh", "-c", "sleep infinity"])
    else
      Quickshell.execDetached(["pkill", "-f", "systemd-inhibit.*idle"])
  }

  function startNightlight() {
    Quickshell.execDetached(["/bin/sh", "-c",
      `if pgrep -x hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset temperature ${nightTemp} >/dev/null 2>&1; else nohup hyprsunset --temperature ${nightTemp} >/dev/null 2>&1 & fi`])
  }

  function stopNightlight() {
    Quickshell.execDetached(["/bin/sh", "-c",
      "hyprctl hyprsunset identity >/dev/null 2>&1; pkill -x hyprsunset"])
  }

  function setNightTemp(t) {
    nightTemp = Math.max(2500, Math.min(6500, t))
    nightTempTimer.restart()
  }

  Timer { id: nightTempTimer; interval: 500; onTriggered: if (root.nightlightOn) root.startNightlight() }

  // real state checks (running processes) so stale local state never lingers
  Process {
    id: nlProc
    command: ["pgrep", "-x", "hyprsunset"]
    running: false
    stdout: StdioCollector { onStreamFinished: root.nightlightOn = text.trim().length > 0 }
  }
  Process {
    id: inhProc
    command: ["pgrep", "-f", "systemd-inhibit.*idle"]
    running: false
    stdout: StdioCollector { onStreamFinished: root.inhibitorActive = text.trim().length > 0 }
  }

  onControlCenterOpenChanged: {
    if (!controlCenterOpen) { root.wifiPanelOpened = false; root.btPanelOpened = false }
    else { nlProc.running = true; inhProc.running = true; mirrorProc.running = true }
  }

  onNotificationPopupChanged: {
    if (root.notificationPopup) root.wifiPanelOpened = false; root.btPanelOpened = false
  }

      RowLayout {
        id: buttonRow
        Layout.fillWidth: true
        spacing: 6 * root.dpi

  // wifi
  Rectangle {
    id: wifiBtn
    implicitWidth: root.buttonWidth
    implicitHeight: root.buttonHeight
    radius: root.buttonRadius
    visible: root.controlCenterOpen && !root.mediaAutoOpened
    color: WifiController.enabled
            ? (wifiHover.hovered ? Qt.lighter("#212529", 1.2) : "#212529")
            : (wifiHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
    scale: wifiMouse.pressed ? 0.93 : 1.0
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    MarqueeText {
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        icon: "\uf1eb"
        iconColor: WifiController.enabled ? "#4282e9" : root.buttonFgOff
        iconFontFamily: Theme.nerdFontFamily
        iconPixelSize: 12

        text: !WifiController.enabled ? "Off"
            : WifiController.currentSsid.length > 0 ? WifiController.currentSsid
            : (WifiController.statusText.length > 0 ? WifiController.statusText : "Not connected")
        color: WifiController.enabled ? Theme.fg : root.buttonFgOff
        font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        maxWidth: 50
    }

    HoverHandler { id: wifiHover }
    MouseArea {
      id: wifiMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
          root.wifiPanelOpened = !root.wifiPanelOpened
          if (root.wifiPanelOpened && WifiController.enabled) WifiController.refreshNetworks(true)
          return
        }
        WifiController.setEnabled(!WifiController.enabled)
      }
    }
  }

  Rectangle {
    id: dndBtn
    implicitWidth: root.buttonWidth
    implicitHeight: root.buttonHeight
    radius: root.buttonRadius
    visible: root.controlCenterOpen && !root.mediaAutoOpened
    color: notificationModule.dndEnabled
    ? (dndHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
    : (dndHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
    scale: dndMouse.pressed ? 0.93 : 1.0
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

    RowLayout {
      anchors.centerIn: parent
      spacing: 5 * root.dpi
      Text {
        text: String.fromCodePoint(0xf1f6)
        color: notificationModule.dndEnabled ? "#fff9eb" : root.buttonFgOff
        font { family: Theme.nerdFontFamily; pixelSize: 13 }
      }
      Text {
        text: "DND"
        color: notificationModule.dndEnabled ? Theme.fg : root.buttonFgOff
        font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
      }
    }
    HoverHandler { id: dndHover }
    MouseArea {
      id: dndMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: notificationModule.dndEnabled = !notificationModule.dndEnabled
    }
  }

  // timer / countdown
  Rectangle {
    id: timerBtn
    implicitWidth: root.buttonWidth
    implicitHeight: root.buttonHeight
    radius: root.buttonRadius
    color: countdownModule.running
           ? (timerHover.hovered ? Qt.lighter("#212529", 1.2) : "#212529")
           : (timerHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
    scale: timerMouse.pressed ? 0.93 : 1.0
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
    property int selectedMinutes: 1
    property bool burstTriggered: false
    property bool bursting: false
    readonly property var burstPalette: ["#ffd43b", "#ff6b6b", "#4490ee", "#b197fc", "#f783ac", "#63e6be"]

    // hold to burst the running timer with a small explosion
    function burst() {
      if (!countdownModule.running && countdownModule.remainingSeconds <= 0) return
      burstTriggered = true
      bursting = true
      burstEndTimer.start()
      countdownModule.reset()
      burstFlashAnim.restart()
      timerRowPop.restart()
      for (var i = 0; i < burstParticles.count; ++i) burstParticles.itemAt(i).burst()
    }

    Timer {
      id: burstHoldTimer
      interval: 500
      repeat: false
      onTriggered: timerBtn.burst()
    }

    Timer {
      id: burstEndTimer
      interval: 560
      repeat: false
      onTriggered: timerBtn.bursting = false
    }

    RowLayout {
      id: timerRow
      anchors.centerIn: parent
      spacing: 5 * root.dpi
      transformOrigin: Item.Center
      Text {
        text: {
          if (countdownModule.running) return String.fromCodePoint(0xf1ade)
          if (countdownModule.remainingSeconds > 0) return String.fromCodePoint(0xf1ae0)
          return String.fromCodePoint(0xf13ab)
        }
        color: timerBtn.bursting ? "#ff922b" : (countdownModule.running ? "#4490ee" : root.buttonFgOff)
        font { family: Theme.nerdFontFamily; pixelSize: 14 }
      }
      Text {
        text: countdownModule.running || countdownModule.remainingSeconds > 0
            ? countdownModule.formatted() : timerBtn.selectedMinutes + "m"
        color: timerBtn.bursting ? "#ff922b" : (countdownModule.running ? Theme.fg : root.buttonFgOff)
        font { family: Theme.fontFamily; pixelSize: 10; weight: 400 }
      }
    }

    // quick orange flash on the button face
    Rectangle {
      id: burstFlash
      anchors.fill: parent
      radius: root.buttonRadius
      color: "#ff922b"
      visible: false
      opacity: 0
    }

    SequentialAnimation {
      id: burstFlashAnim
      running: false
      onStarted: burstFlash.visible = true
      NumberAnimation { target: burstFlash; property: "opacity"; from: 0.85; to: 0; duration: 400; easing.type: Easing.OutQuad }
      ScriptAction { script: burstFlash.visible = false }
    }

    // the timer glyph pops and vanishes
    SequentialAnimation {
      id: timerRowPop
      running: false
      ParallelAnimation {
        NumberAnimation { target: timerRow; property: "scale"; to: 1.8; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: timerRow; property: "opacity"; to: 0; duration: 240; easing.type: Easing.OutQuad }
      }
      ScriptAction { script: { timerRow.scale = 1; timerRow.opacity = 1 } }
    }

    // debris flying out from the center
    Repeater {
      id: burstParticles
      anchors.centerIn: parent
      model: 10
      delegate: Rectangle {
        id: p
        property real tx: 0
        property real ty: 0
        width: (3 + Math.random() * 4) * root.dpi
        height: width
        radius: width / 2
        color: timerBtn.burstPalette[index % timerBtn.burstPalette.length]
        x: -width / 2
        y: -height / 2
        visible: false
        opacity: 0
        function burst() {
          var d = (22 + Math.random() * 48) * root.dpi
          var a = Math.random() * 2 * Math.PI
          tx = Math.cos(a) * d
          ty = Math.sin(a) * d
          visible = true
          fly.restart()
        }
        SequentialAnimation {
          id: fly
          running: false
          ParallelAnimation {
            NumberAnimation { target: p; property: "x"; from: -p.width / 2; to: p.tx; duration: 500; easing.type: Easing.OutCubic }
            NumberAnimation { target: p; property: "y"; from: -p.height / 2; to: p.ty; duration: 500; easing.type: Easing.OutCubic }
            NumberAnimation { target: p; property: "opacity"; from: 1; to: 0; duration: 500; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    HoverHandler { id: timerHover }
    MouseArea {
      id: timerMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onPressed: (mouse) => {
        if (mouse.button !== Qt.LeftButton) return
        timerBtn.burstTriggered = false
        if (countdownModule.running || countdownModule.remainingSeconds > 0) {
          burstHoldTimer.start()
        }
      }
      onReleased: (mouse) => {
        if (mouse.button !== Qt.LeftButton) return
        burstHoldTimer.stop()
      }
      onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton && timerBtn.burstTriggered) return
        if (mouse.button === Qt.MiddleButton) { countdownModule.reset(); return }
        if (mouse.button === Qt.RightButton) {
          if (countdownModule.running || countdownModule.remainingSeconds > 0) return
          const presets = Config.timerPresets
          const idx = presets.indexOf(timerBtn.selectedMinutes)
          timerBtn.selectedMinutes = presets[(idx + 1) % presets.length]
          return
        }
        if (countdownModule.running) { countdownModule.pause(); return }
        if (countdownModule.remainingSeconds > 0) { countdownModule.resume(); return }
        countdownModule.start(timerBtn.selectedMinutes)
      }
    }
  }

  // bluetooth
  Rectangle {
    id: btBtn
    implicitWidth: root.buttonWidth
    implicitHeight: root.buttonHeight
    radius: root.buttonRadius
    visible: root.controlCenterOpen && !root.mediaAutoOpened
    color: BluetoothController.enabled
            ? (btHover.hovered ? Qt.lighter("#212529", 1.2) : "#212529")
            : (btHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
    scale: btMouse.pressed ? 0.93 : 1.0
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
    RowLayout {
      anchors.centerIn: parent
      spacing: 5 * root.dpi
      Text {
        text: "\uf294"
        color: BluetoothController.enabled ? "#4282e9" : root.buttonFgOff
        font { family: Theme.nerdFontFamily; pixelSize: 15 }
      }
      MarqueeText {
        text: !BluetoothController.enabled ? "Off"
            : BluetoothController.currentDeviceName.length > 0 ? BluetoothController.currentDeviceName
            : (BluetoothController.statusText.length > 0 ? BluetoothController.statusText : "Not connected")
        color: BluetoothController.enabled ? Theme.fg : root.buttonFgOff
        font { family: Theme.fontFamily; pixelSize: 10; weight: 400 }
        maxWidth: 50
      }
    }
    HoverHandler { id: btHover }
    MouseArea {
      id: btMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
          root.btPanelOpened = !root.btPanelOpened
          if (root.btPanelOpened && BluetoothController.enabled) BluetoothController.refreshDevices(true)
          return
        }
        BluetoothController.setEnabled(!BluetoothController.enabled)
      }
    }
  }

  } // buttonRow

  // row 2: keyboard, inhibitor, night light (ported from FunShell)
  RowLayout {
    id: sysRow
    Layout.fillWidth: true
    spacing: 6 * root.dpi
    visible: root.controlCenterOpen && !root.mediaAutoOpened

    // keyboard toggle (wvkbd)
    Rectangle {
      id: kbBtn
      Layout.fillWidth: true
      Layout.preferredHeight: root.buttonHeight
      radius: root.buttonRadius
      color: root.oskVisible
        ? (kbHover.hovered ? Qt.lighter("#212529", 1.2) : "#212529")
        : (kbHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: kbMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      RowLayout {
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          text: String.fromCodePoint(0xf11c)
          color: root.oskVisible ? "#4282e9" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: "Keyboard"
          color: root.oskVisible ? Theme.fg : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }
      HoverHandler { id: kbHover }
      MouseArea {
        id: kbMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleOsk()
      }
    }

    // idle inhibitor
    Rectangle {
      id: inhBtn
      Layout.fillWidth: true
      Layout.preferredHeight: root.buttonHeight
      radius: root.buttonRadius
      color: root.inhibitorActive
        ? (inhHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
        : (inhHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: inhMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      RowLayout {
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          text: "󰈈"
          color: root.inhibitorActive ? "#ff922b" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: "Inhibit"
          color: root.inhibitorActive ? Theme.fg : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }
      HoverHandler { id: inhHover }
      MouseArea {
        id: inhMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleInhibitor()
      }
    }

    // night light toggle
    Rectangle {
      id: nlBtn
      Layout.fillWidth: true
      Layout.preferredHeight: root.buttonHeight
      radius: root.buttonRadius
      color: root.nightlightOn
        ? (nlHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
        : (nlHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: nlMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      RowLayout {
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          text: "\uf186"
          color: root.nightlightOn ? "#ff922b" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: root.nightlightOn ? root.nightTemp + "K" : "Night"
          color: root.nightlightOn ? Theme.fg : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }
      HoverHandler { id: nlHover }
      MouseArea {
        id: nlMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.nightlightOn = !root.nightlightOn
          if (root.nightlightOn) root.startNightlight()
          else root.stopNightlight()
        }
      }
    }

    // screen mirror (from FunShell MirrorScreen.qml): mirrors HDMI-A-1 onto eDP-1
    Rectangle {
        id: mirrorBtn
        Layout.fillWidth: true
        Layout.preferredHeight: root.buttonHeight
        radius: root.buttonRadius
        property bool hdmiConnected: false
        property bool mirrorActive: false
        color: mirrorBtn.mirrorActive
          ? (mirrorHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
          : (mirrorHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
        scale: mirrorMouse.pressed ? 0.93 : 1.0
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
        opacity: hdmiConnected ? 1.0 : 0.45
        Behavior on opacity { NumberAnimation { duration: 150 } }

        RowLayout {
          anchors.centerIn: parent
          spacing: 5 * root.dpi
          Text {
            text: mirrorBtn.mirrorActive ? String.fromCodePoint(0xf0119)
                : mirrorBtn.hdmiConnected ? String.fromCodePoint(0xf0118)
                : String.fromCodePoint(0xf078a)
            color: mirrorBtn.mirrorActive ? "#4282e9" : root.buttonFgOff
            font { family: Theme.nerdFontFamily; pixelSize: 13 }
          }
          Text {
            text: "Mirror"
            color: mirrorBtn.mirrorActive ? Theme.fg : root.buttonFgOff
            font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
          }
        }
        HoverHandler { id: mirrorHover }
        MouseArea {
          id: mirrorMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!mirrorBtn.hdmiConnected) return
            if (mirrorBtn.mirrorActive)
              Quickshell.execDetached(["hyprctl", "reload"])
            else
              Quickshell.execDetached(["hyprctl", "eval",
                'hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })'])
            mirrorStatusTimer.restart()
          }
        }

        // Hyprland applies monitor changes async - re-check shortly after
        Timer { id: mirrorStatusTimer; interval: 800; onTriggered: mirrorProc.running = true }

        Process {
          id: mirrorProc
          command: ["hyprctl", "-j", "monitors", "all"]
          running: false
          stdout: StdioCollector {
            onStreamFinished: {
              try {
                const mons = JSON.parse(text)
                let hdmi = null
                for (const m of mons) { if (m.name === "HDMI-A-1") { hdmi = m; break } }
                mirrorBtn.hdmiConnected = hdmi !== null && !hdmi.disabled
                mirrorBtn.mirrorActive = hdmi !== null && hdmi.mirrorOf !== "none"
              } catch (e) {}
            }
          }
        }
        Component.onCompleted: mirrorProc.running = true
    }
  }
}

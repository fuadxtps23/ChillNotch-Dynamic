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
  // record options panel (right slot — mutually exclusive with btPanel)
  property bool recordPanelOpened: false
  // recording options, shared with RecordPanel (both reference this instance)
  property int recordFramerate: 30 // 15 / 24 / 30 / 60
  property string recordQuality: "Medium" // Low / Medium / High / Lossless
  property string recordCodec: "libx264" // wf-recorder encoder name (see codecLabel)
  // encoders probed as usable on this system (fallback list until the probe finishes)
  property var recordCodecs: ["libx264", "libx265", "libvpx-vp9"]
  property bool recordAudio: true
  property bool recordRegionMode: false // false = full screen, true = slurp region
  property bool recordNotifyOnStop: true

  // ---- screen-recorder codec helpers ----
  readonly property var codecLabels: ({
    "libx264": "H.264", "libx265": "H.265", "libvpx": "VP8", "libvpx-vp9": "VP9",
    "libsvtav1": "AV1",
    "h264_vaapi": "H.264 (VAAPI)", "hevc_vaapi": "H.265 (VAAPI)",
    "av1_vaapi": "AV1 (VAAPI)", "vp9_vaapi": "VP9 (VAAPI)",
    "h264_qsv": "H.264 (QSV)", "hevc_qsv": "H.265 (QSV)",
    "av1_qsv": "AV1 (QSV)", "vp9_qsv": "VP9 (QSV)",
    "h264_nvenc": "H.264 (NVENC)", "hevc_nvenc": "H.265 (NVENC)", "av1_nvenc": "AV1 (NVENC)",
    "h264_amf": "H.264 (AMF)", "hevc_amf": "H.265 (AMF)", "av1_amf": "AV1 (AMF)"
  })
  // display order: software first, then hardware families
  readonly property var codecOrder: [
    "libx264", "libx265", "libvpx-vp9", "libvpx", "libsvtav1",
    "h264_vaapi", "hevc_vaapi", "av1_vaapi", "vp9_vaapi",
    "h264_qsv", "hevc_qsv", "av1_qsv", "vp9_qsv",
    "h264_nvenc", "hevc_nvenc", "av1_nvenc",
    "h264_amf", "hevc_amf", "av1_amf"
  ]

  function codecLabel(enc) { return codecLabels[enc] !== undefined ? codecLabels[enc] : enc }
  function codecEnc(label) {
    for (var k in codecLabels) if (codecLabels[k] === label) return k
    return "libx264"
  }
  function codecChoiceLabels() { return recordCodecs.map(function(e) { return codecLabel(e) }) }
  // RecordPanel's region toggle calls this: slurp -> auto-start recording
  function startRegionPick() { recBtn.pickRegion() }

  // Probe every candidate encoder with a 0.2s test encode (parallel, ~4s wall).
  // libaom-av1 is deliberately absent: it probes OK in ffmpeg but hangs
  // wf-recorder's SIGINT finalize — SVT-AV1 is the AV1 path instead.
  Process {
    id: codecProbe
    running: false
    command: ["/bin/sh", "-c", `
dev=$(ls /dev/dri/renderD* 2>/dev/null | head -1)
probe() {
  enc="$1"; pre="$2"; post="$3"
  timeout 4 ffmpeg -v error $pre -f lavfi -i color=c=black:s=64x64:r=5:d=0.2 $post -c:v "$enc" -frames:v 1 -f null - >/dev/null 2>&1 && echo "$enc"
}
for e in libx264 libx265 libvpx libvpx-vp9 libsvtav1 h264_nvenc hevc_nvenc av1_nvenc h264_amf hevc_amf av1_amf h264_qsv hevc_qsv av1_qsv vp9_qsv; do
  probe "$e" "" "" &
done
if [ -n "$dev" ]; then
  for e in h264_vaapi hevc_vaapi av1_vaapi vp9_vaapi; do
    probe "$e" "-vaapi_device $dev" "-vf format=nv12,hwupload" &
  done
fi
wait
`]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = text.split("\n").map(function(s) { return s.trim() })
          .filter(function(s) { return s.length > 0 })
        if (found.length === 0) return
        const ordered = root.codecOrder.filter(function(e) { return found.indexOf(e) !== -1 })
        root.recordCodecs = ordered
        if (ordered.indexOf(root.recordCodec) === -1) root.recordCodec = ordered[0]
      }
    }
  }
  Component.onCompleted: codecProbe.running = true
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
  // power profile (powerprofilesctl): "" until first poll
  property string powerProfile: ""
  // touchscreen (hyprland input:touchdevice:enabled): false until first poll
  property bool touchscreenOn: false
  readonly property var powerProfileOrder: ["power-saver", "balanced", "performance"]

  function powerProfileLabel(p) {
    if (p === "performance") return "Perf"
    if (p === "power-saver") return "Save"
    return "Bal"
  }

  // dir +1 = forward (power-saver -> balanced -> performance), -1 = backward
  function cycleProfile(dir) {
    let i = powerProfileOrder.indexOf(root.powerProfile)
    if (i === -1) i = 1 // unknown -> treat as balanced
    i = (i + dir + powerProfileOrder.length) % powerProfileOrder.length
    const next = powerProfileOrder[i]
    root.powerProfile = next // optimistic; poll on next CC open re-syncs
    Quickshell.execDetached(["powerprofilesctl", "set", next])
  }

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
  Process {
    id: ppGetProc
    command: ["powerprofilesctl", "get"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const v = text.trim()
        if (v.length > 0) root.powerProfile = v
      }
    }
  }

  Process {
    id: touchGetProc
    command: ["hyprctl", "getoption", "input:touchdevice:enabled", "-j"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.touchscreenOn = !!JSON.parse(text).bool } catch (e) {}
      }
    }
  }

  // hyprctl 0.56: keyword is gone, options are set via Lua eval
  function setTouchscreen(on) {
    root.touchscreenOn = on // optimistic
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({input={touchdevice={enabled=" + (on ? "true" : "false") + "}}})"])
  }

  onControlCenterOpenChanged: {
    if (!controlCenterOpen) {
      root.wifiPanelOpened = false; root.btPanelOpened = false; root.recordPanelOpened = false
    } else {
      nlProc.running = true; inhProc.running = true; mirrorProc.running = true
      ppGetProc.running = true
      touchGetProc.running = true
      if (pollProc) pollProc.running = true // refresh recording state on open
    }
  }

  onNotificationPopupChanged: {
    if (root.notificationPopup) {
      root.wifiPanelOpened = false; root.btPanelOpened = false; root.recordPanelOpened = false
    }
  }

      RowLayout {
        id: buttonRow
        Layout.fillWidth: true
        spacing: 6 * root.dpi

  // wifi
  Rectangle {
    id: wifiBtn
    implicitWidth: root.buttonWidth // preferred base; row width distributed by flex
    Layout.fillWidth: true
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
    implicitWidth: root.buttonWidth // preferred base; row width distributed by flex
    Layout.fillWidth: true
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
    implicitWidth: root.buttonWidth // preferred base; row width distributed by flex
    Layout.fillWidth: true
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
    implicitWidth: root.buttonWidth // preferred base; row width distributed by flex
    Layout.fillWidth: true
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
          if (root.btPanelOpened) {
            root.recordPanelOpened = false // record panel owns the same right slot
            if (BluetoothController.enabled) BluetoothController.refreshDevices(true)
          }
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

  // row 3: screen recorder (ported from FunShell RecordButton)
  // left click toggles wf-recorder, right click opens RecordPanel
  // (right slot — replaces an open bluetooth panel)
  RowLayout {
    id: recRow
    Layout.fillWidth: true
    spacing: 6 * root.dpi
    visible: root.controlCenterOpen && !root.mediaAutoOpened

    Rectangle {
      id: recBtn
      // 2 grid cells + internal gap: first gap lands on the panel centerline
      // (row = Record[2] Power[1] Touch[1], 3 gaps -> (W-3g)/2 + g)
      Layout.preferredWidth: (recRow.width - 3 * recRow.spacing) / 2 + recRow.spacing
      Layout.fillWidth: true
      implicitHeight: root.buttonHeight
      radius: root.buttonRadius
      color: recBtn.recording
        ? (recHover.hovered ? Qt.lighter("#e32626", 1.15) : "#e32626")
        : (recHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: recMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      property bool recording: false
      property int elapsedSec: 0
      readonly property string outputDir: (Quickshell.env("HOME") || "/home/notfuad") + "/Videos/Record"

      RowLayout {
        id: recContent
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          text: recBtn.recording ? String.fromCodePoint(0xf04db) : String.fromCodePoint(0xf03d1)
          color: recBtn.recording ? "#ffffff" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: recBtn.recording ? recBtn.formatElapsed(recBtn.elapsedSec) : "Record"
          color: recBtn.recording ? "#ffffff" : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }

      HoverHandler { id: recHover }
      MouseArea {
        id: recMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
            root.recordPanelOpened = !root.recordPanelOpened
            if (root.recordPanelOpened) root.btPanelOpened = false // panel replaces bt
            return
          }
          if (recBtn.recording) recBtn.stopRecording()
          else recBtn.startRecording()
        }
      }

      function formatElapsed(s) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const sec = s % 60
        const pad = (n) => String(n).padStart(2, "0")
        return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`
      }

      // Shell-quote a literal string. Anything passed through this must be
      // fully resolved in JS first — a quoted '$(...)' would be taken
      // literally by the shell instead of expanding.
      function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
      }

      function timestamp() {
        const d = new Date()
        const pad = (n) => String(n).padStart(2, "0")
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
          `_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`
      }

      // quality -> encoder param for wf-recorder -p, per encoder family.
      // Verified against this ffmpeg: crf (libav codecs), global_quality (QSV),
      // rc_mode=CQP+qp (VAAPI), cq (NVENC), qp_i/qp_p (AMF).
      function qualityParams(enc, quality) {
        const crfTable = { "Low": 32, "Medium": 23, "High": 18, "Lossless": 0 }
        const wideTable = { "Low": 40, "Medium": 32, "High": 24, "Lossless": 12 }
        const qpTable = { "Low": 40, "Medium": 26, "High": 18, "Lossless": 8 }
        const t = (name) => {
          const tbl = (enc === "libvpx" || enc === "libvpx-vp9") ? wideTable
                    : (enc.indexOf("_vaapi") !== -1 || enc.indexOf("_qsv") !== -1
                       || enc.indexOf("_nvenc") !== -1 || enc.indexOf("_amf") !== -1) ? qpTable
                    : crfTable
          return tbl[name] !== undefined ? tbl[name] : tbl["Medium"]
        }
        if (enc === "libx264" || enc === "libx265" || enc === "libsvtav1"
            || enc === "libvpx" || enc === "libvpx-vp9")
          return `-p crf=${t(quality)}`
        if (enc.indexOf("_vaapi") !== -1) return `-p rc_mode=CQP -p qp=${t(quality)}`
        if (enc.indexOf("_qsv") !== -1) return `-p global_quality=${t(quality)}`
        if (enc.indexOf("_nvenc") !== -1) return `-p cq=${t(quality)}`
        if (enc.indexOf("_amf") !== -1) return `-p qp_i=${t(quality)} -p qp_p=${t(quality)}`
        return ""
      }

      function startRecording(geometry) {
        const enc = root.recordCodec
        const qargs = recBtn.qualityParams(enc, root.recordQuality)
        // .mkv tolerates any codec AND abrupt SIGINT far better than .mp4,
        // whose moov atom can end up unfinalized/corrupt
        const file = `${recBtn.outputDir}/record_${recBtn.timestamp()}.mkv`
        const audioFlag = root.recordAudio ? "-a" : ""

        const launch = (geometry) => {
          const geomFlag = geometry ? `-g ${recBtn.shq(geometry)}` : ""
          // `exec` replaces this shell with wf-recorder itself (same PID,
          // process name "wf-recorder") — that's what pgrep/pkill -x below
          // rely on to find/stop it exactly
          const cmd = `mkdir -p ${recBtn.shq(recBtn.outputDir)} && exec wf-recorder` +
            ` -f ${recBtn.shq(file)} -r ${root.recordFramerate}` +
            ` -c ${enc} ${qargs} ${audioFlag} ${geomFlag}`
          Quickshell.execDetached(["/bin/sh", "-c", cmd])
          // optimistic: next poll tick (within 1s) confirms from real process
          recBtn.recording = true
          recBtn.elapsedSec = 0
          pollTimer.start()
        }

        if (geometry) { launch(geometry); return }
        if (root.recordRegionMode) {
          recBtn.pickRegion()
        } else {
          launch("")
        }
      }

      // slurp -> wf-recorder -g; used by region mode and the panel's
      // "Select region" toggle (which starts recording right after cropping)
      function pickRegion() {
        if (recBtn.recording) return
        // slurp's stdout is already wf-recorder's "-g" format (X,Y WxH);
        // Esc/right-click cancels slurp with empty stdout -> do nothing
        slurpProc.onGeometry = (g) => recBtn.startRecording(g)
        slurpProc.running = true
      }

      function stopRecording() {
        // SIGINT (not TERM/KILL): wf-recorder only finalizes the file on a
        // Ctrl+C-equivalent signal. `-x` (exact PROCESS NAME) not `pgrep -f`:
        // a -f match also hits the wrapping shell whose cmdline contains the
        // search pattern (self-match showed "recording" with nothing running)
        Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"])
        if (root.recordNotifyOnStop) notifyTimer.start()
      }

      // give wf-recorder a moment to flush before announcing "saved"
      Timer {
        id: notifyTimer
        interval: 600
        onTriggered: Quickshell.execDetached(["notify-send", "-a", "Screen Recorder",
          "Recording saved", recBtn.outputDir])
      }

      Process {
        id: slurpProc
        command: ["slurp"]
        running: false
        property var onGeometry: null
        stdout: StdioCollector {
          onStreamFinished: {
            const g = text.trim()
            if (g.length > 0 && slurpProc.onGeometry) slurpProc.onGeometry(g)
          }
        }
      }

      // single poll does double duty: detects wf-recorder alive AND (via
      // `ps -o etimes=`) how long it's been running, so the elapsed label is
      // correct even right after a shell reload mid-recording
      Process {
        id: pollProc
        command: ["/bin/sh", "-c",
          "ps -o etimes= -p $(pgrep -x wf-recorder | head -1) 2>/dev/null"]
        running: true
        stdout: StdioCollector {
          onStreamFinished: {
            const t = text.trim()
            if (/^\d+$/.test(t)) {
              recBtn.recording = true
              recBtn.elapsedSec = parseInt(t, 10)
              pollTimer.start()
            } else {
              recBtn.recording = false
              recBtn.elapsedSec = 0
              pollTimer.stop()
            }
          }
        }
      }

      Timer {
        id: pollTimer
        interval: 1000
        repeat: true
        onTriggered: pollProc.running = true
      }
    }
    // power profile (powerprofilesctl): left click cycles forward,
    // right click cycles backward (power-saver <-> balanced <-> performance)
    Rectangle {
      id: ppBtn
      // one grid cell (Record keeps 2 cells, gap stays on the panel centerline)
      Layout.preferredWidth: (recRow.width - 3 * recRow.spacing) / 4
      Layout.fillWidth: true
      Layout.preferredHeight: root.buttonHeight
      radius: root.buttonRadius
      readonly property bool active: root.powerProfile !== "" && root.powerProfile !== "balanced"
      color: ppBtn.active
        ? (ppHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
        : (ppHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: ppMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      RowLayout {
        id: ppContent
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          // leaf = power-saver, scale = balanced, speedometer = performance
          text: root.powerProfile === "performance" ? String.fromCodePoint(0xf04c5)
              : root.powerProfile === "power-saver" ? String.fromCodePoint(0xf032a)
              : String.fromCodePoint(0xf05d1)
          color: root.powerProfile === "performance" ? "#e32626"
              : root.powerProfile === "power-saver" ? "#2f9e44"
              : ppBtn.active ? "#4282e9" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: root.powerProfile === "" ? "Power" : root.powerProfileLabel(root.powerProfile)
          color: ppBtn.active ? Theme.fg : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }
      HoverHandler { id: ppHover }
      MouseArea {
        id: ppMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => root.cycleProfile(mouse.button === Qt.RightButton ? -1 : 1)
      }
    }

    // touchscreen toggle (hyprland input:touchdevice:enabled)
    Rectangle {
      id: touchBtn
      // one grid cell, same as ppBtn
      Layout.preferredWidth: (recRow.width - 3 * recRow.spacing) / 4
      Layout.fillWidth: true
      Layout.preferredHeight: root.buttonHeight
      radius: root.buttonRadius
      color: root.touchscreenOn
        ? (touchHover.hovered ? Qt.lighter("#262626", 1.2) : "#262626")
        : (touchHover.hovered ? Qt.lighter(root.buttonBgOff, 1.3) : root.buttonBgOff)
      scale: touchMouse.pressed ? 0.93 : 1.0
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

      RowLayout {
        id: touchContent
        anchors.centerIn: parent
        spacing: 5 * root.dpi
        Text {
          text: String.fromCodePoint(0xf0741) // md-gesture_tap
          color: root.touchscreenOn ? "#4282e9" : root.buttonFgOff
          font { family: Theme.nerdFontFamily; pixelSize: 13 }
        }
        Text {
          text: "Touch"
          color: root.touchscreenOn ? Theme.fg : root.buttonFgOff
          font { family: Theme.fontFamily; pixelSize: 10; weight: 500 }
        }
      }
      HoverHandler { id: touchHover }
      MouseArea {
        id: touchMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setTouchscreen(!root.touchscreenOn)
      }
    }

  }
}

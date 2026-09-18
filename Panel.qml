import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "galza.wwan"
  ipcTarget: "galza.wwan"
  manageIpc: false

  property var status: Model.emptyStatus()
  property string action: ""
  property string lastError: ""
  property bool cursorActive: false
  property bool passwordVisible: false
  property bool presenceKnown: false
  readonly property bool busy: statusProc.running || actionProc.running
  readonly property bool connected: status.connected === true
  readonly property bool present: status.present === true
  readonly property bool recoverable: status.recoverable === true
  readonly property var share: status.share || Model.emptyShare()
  readonly property bool sharing: share.active === true
  readonly property string icon: Model.iconFor(status)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: present && connected ? foreground : dim
  readonly property string toggleHint: connected ? "Turn mobile data off" : "Turn mobile data on"
  readonly property string shareHint: sharing
    ? "Stop sharing over Wi-Fi"
    : "Broadcast mobile data over Wi-Fi"
  readonly property bool headerHasCursor: cursorActive
  readonly property string helperPath: {
    var url = Qt.resolvedUrl("wwan-ctl").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = ["python3", helperPath, "status"]
    statusProc.running = true
  }

  function applyStatus(raw, fromAction) {
    var parsed = Model.parseStatus(raw)
    status = parsed
    presenceKnown = true
    var shareError = parsed.share && parsed.share.error ? parsed.share.error : ""
    if (fromAction && (parsed.error || shareError)) lastError = parsed.error || shareError
    else if (!parsed.error && !shareError) lastError = ""
  }

  function toggleMobile() {
    if (busy) return
    if (!present) {
      if (recoverable) recoverModem()
      return
    }
    lastError = ""
    action = connected ? "disconnect" : "connect"
    actionProc.command = ["python3", helperPath, action]
    actionProc.running = true
  }

  function recoverModem() {
    if (busy) return
    lastError = ""
    action = "recover"
    actionProc.command = ["python3", helperPath, "recover"]
    actionProc.running = true
  }

  function toggleShare() {
    if (busy) return
    lastError = ""
    action = sharing ? "share-off" : "share-on"
    actionProc.command = ["python3", helperPath, action]
    actionProc.running = true
  }

  function copySharePassword() {
    if (!share.password) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + JSON.stringify(share.password) + " | wl-copy"])
  }

  function summonShareQr() {
    if (!root.bar || !root.bar.shell) return
    var payload = {
      iface: share.iface || "",
      ssid: share.ssid || "WWAN"
    }
    root.close()
    root.bar.shell.summon("omarchy.wifiqr", JSON.stringify(payload))
  }

  function setHeaderCursor() {
    cursorActive = true
  }

  readonly property bool showOnBar: presenceKnown && (present || recoverable)
  implicitWidth: showOnBar ? button.implicitWidth : 0
  implicitHeight: showOnBar ? button.implicitHeight : 0
  visible: showOnBar

  onOpenedChanged: if (opened) {
    cursorActive = false
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProc
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.applyStatus(statusOut.text, false)
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      root.action = ""
      var raw = actionOut.text && actionOut.text.length ? actionOut.text : actionErr.text
      root.applyStatus(raw, true)
      if (code !== 0 && root.lastError === "") root.lastError = "Mobile data action failed"
      root.refresh()
    }
  }

  Timer {
    interval: root.opened ? 3000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!root.busy) root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function connect(): string { if (!root.connected) root.toggleMobile(); return "ok" }
    function disconnect(): string { if (root.connected) root.toggleMobile(); return "ok" }
    function shareOn(): string { if (!root.sharing) root.toggleShare(); return "ok" }
    function shareOff(): string { if (root.sharing) root.toggleShare(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    dimmed: !root.present || !root.connected
    tooltipText: root.sharing
      ? "WWAN sharing"
      : (root.present ? (root.connected ? "WWAN connected" : "WWAN ready") : "WWAN")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleMobile()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (root.opened) root.close()
      else root.open()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function() { root.cursorActive = true }
      onActivateRequested: root.toggleMobile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === " " || t === "t" || t === "T") root.toggleMobile()
        else if (t === "s" || t === "S") root.toggleShare()
        else if (t === "u" || t === "U") root.recoverModem()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool ringVisible: root.headerHasCursor
          function focusHero() { root.setHeaderCursor() }

          PanelHero {
            id: hero
            width: parent.width
            title: "WWAN"
            meta: Model.heroMeta(root.status, root.busy, root.action)
            detail: Model.detail(root.status)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.present && root.connected ? 1.0 : 0.55
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.icon
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: root.present
                checked: root.connected
                busy: root.busy
                hasCursor: header.ringVisible
                foreground: hero.foreground
                onHovered: function(on) { if (on) header.focusHero() }
                onToggled: root.toggleMobile()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.toggleHint
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        Item {
          width: parent.width
          implicitHeight: shareSwitch.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.right: shareSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Share over Wi-Fi"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          ToggleSwitch {
            id: shareSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.sharing
            busy: root.busy && (root.action === "share-on" || root.action === "share-off")
            foreground: root.foreground
            onToggled: root.toggleShare()

            PanelToolTip {
              visible: shareSwitch.containsMouse
              text: root.shareHint
              fontFamily: root.fontFamily
            }
          }
        }

        Text {
          width: parent.width
          text: root.sharing
            ? (root.share.ssid + " · 2.4 GHz · " + (root.share.clients === 1 ? "1 client" : (root.share.clients + " clients")))
            : "Broadcasts this SIM. Uses the Wi-Fi radio, so this laptop will not join office Wi-Fi at the same time."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        GridLayout {
          visible: root.share.password !== ""
          width: parent.width
          columns: 3
          columnSpacing: Style.space(8)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { text: "SSID" }
          InfoValue { text: root.share.ssid || "--"; Layout.columnSpan: 2 }
          InfoLabel { text: "Password" }
          Text {
            textFormat: Text.PlainText
            text: root.share.password
              ? (root.passwordVisible ? root.share.password : "••••••••")
              : "--"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.passwordVisible = !root.passwordVisible
            }
          }
          Row {
            spacing: Style.space(4)
            PanelActionButton {
              iconText: "󰆏"
              tooltipText: "Copy password"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.copySharePassword()
            }
            PanelActionButton {
              iconText: "󰐲"
              tooltipText: "QR code"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.sharing
              onClicked: root.summonShareQr()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { text: "Operator" }
          InfoValue { text: root.status.operator || "--" }
          InfoLabel { text: "Status" }
          InfoValue { text: root.status.state || "--" }
          InfoLabel { text: "Signal" }
          InfoValue { text: root.status.signal > 0 ? (root.status.signal + "%") : "--" }
          InfoLabel { text: "APN" }
          InfoValue { text: root.status.apn || "--" }
          InfoLabel { text: "IP Address" }
          InfoValue { text: root.status.ip || "--" }
        }

        Text {
          width: parent.width
          visible: !root.present
          text: root.recoverable
            ? "The modem is still on the bus but firmware is not answering. Common after sleep on PCIe LTE cards. Recover restarts ModemManager. If it stays dead, shut the machine down fully (not reboot)."
            : "No modem is visible to ModemManager."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Rectangle {
          visible: root.recoverable && !root.present
          width: parent.width
          height: recoverBtn.implicitHeight + Style.space(8)
          color: "transparent"

          PanelActionButton {
            id: recoverBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            enabled: !root.busy
            iconText: "󰑐"
            tooltipText: "Recover modem"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.recoverModem()
          }

          Text {
            anchors.left: parent.left
            anchors.right: recoverBtn.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy && root.action === "recover" ? "Power-cycling WWAN…" : "Recover"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.recoverModem()
          }
        }
      }
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}

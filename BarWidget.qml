import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "music-toolbar"

  property var service: null
  property bool fallbackShowText: true
  property bool fallbackShowControls: false
  property bool fallbackShowPlayerIcon: true

  readonly property var musicService: {
    if (service) return service
    if (bar && bar.shell && typeof bar.shell.serviceFor === "function") {
      var ownService = bar.shell.serviceFor("music-toolbar")
      if (ownService) return ownService
    }
    return null
  }

  readonly property var fallbackPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var fallbackActivePlayer: {
    var players = fallbackPlayers || []
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].isPlaying) return players[i]
    }
    for (var j = 0; j < players.length; j++) {
      if (players[j] && (players[j].trackTitle || players[j].trackArtist)) return players[j]
    }
    return players.length > 0 ? players[0] : null
  }

  // serviceFor() is the normal path. The direct MPRIS fallback keeps the bar
  // useful if the service has not finished loading or a host facade is absent.
  readonly property var activePlayer: musicService ? musicService.activePlayer : fallbackActivePlayer
  readonly property bool isPlaying: musicService
    ? musicService.isPlaying === true
    : Boolean(activePlayer && activePlayer.isPlaying)
  readonly property bool isWaiting: musicService ? musicService.isWaiting === true : false
  readonly property string title: musicService
    ? String(musicService.title || "")
    : String(activePlayer ? (activePlayer.trackTitle || "") : "")
  readonly property string artist: musicService
    ? String(musicService.artist || "")
    : String(activePlayer ? (activePlayer.trackArtist || "") : "")
  readonly property string playerKey: musicService
    ? String(musicService.activePlayerKey || musicService.selectedPlayerKey || "")
    : String(activePlayer ? (activePlayer.desktopEntry || activePlayer.identity || "") : "")
  readonly property string playerIcon: musicService && typeof musicService.sourceIconForKey === "function"
    ? musicService.sourceIconForKey(playerKey)
    : fallbackIcon(playerKey)
  readonly property string displayLabel: {
    if (isWaiting) return "Waiting for " + (musicService ? musicService.selectedPlayerLabel : "player")
    if (!title) return "No music playing"
    return artist ? title + " — " + artist : title
  }
  readonly property color widgetForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property var visualizerBars: musicService ? musicService.cavaBars : [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ]

  // Foreground elements bind directly to Service settings; CAVA is a
  // bottom-anchored strip independent of those toggles. Full-bar mode mutes
  // the pill wave (opacity 0) and clears the pill fill so only the floating
  // foreground sits over the FullBarCava overlay. The bar keeps one CAVA
  // process; only the renderers fade, over ~250 ms, with no layout change.
  readonly property bool fullBarMode: musicService ? musicService.fullBarCava === true : false
  readonly property int foregroundItemCount: (playerIconLabel.visible ? 1 : 0)
    + (trackLabel.visible ? 1 : 0)
    + (controlRow.visible ? 1 : 0)
  readonly property real foregroundItemsWidth: playerIconLabel.width + trackLabel.width + controlRow.width
  readonly property real foregroundNaturalWidth: foregroundItemsWidth
    + Style.space(8) * Math.max(0, foregroundItemCount - 1)
  readonly property real pillTargetWidth: Math.max(
    Style.space(120), foregroundNaturalWidth + Style.space(16))

  readonly property bool opened: Boolean(
    (panelLoader.item && panelLoader.item.opened === true)
    || (settingsLoader.item && settingsLoader.item.opened === true))
  readonly property bool popoutSwitchClosing: Boolean(
    (panelLoader.item && panelLoader.item.popoutSwitchClosing === true)
    || (settingsLoader.item && settingsLoader.item.popoutSwitchClosing === true))

  function fallbackIcon(key) {
    var normalized = String(key || "").toLowerCase().replace(/[^a-z0-9]/g, "")
    if (normalized.indexOf("spotify") !== -1) return "󰓇"
    if (normalized.indexOf("firefox") !== -1 || normalized.indexOf("zen") !== -1) return "󰈹"
    if (normalized.indexOf("chrom") !== -1 || normalized.indexOf("brave") !== -1 || normalized.indexOf("edge") !== -1) return "󰊯"
    if (normalized.indexOf("mpv") !== -1 || normalized.indexOf("vlc") !== -1 || normalized.indexOf("celluloid") !== -1) return "󰐹"
    if (normalized.indexOf("youtube") !== -1) return "󰗃"
    return "󰝚"
  }

  function refreshService() {
    if (root.service || !root.bar || !root.bar.shell || typeof root.bar.shell.serviceFor !== "function") return
    var ownService = root.bar.shell.serviceFor("music-toolbar")
    if (ownService) root.service = ownService
  }

  function open() {
    if (settingsLoader.item && settingsLoader.item.opened) settingsLoader.item.close()
    if (panelLoader.item) panelLoader.item.open()
  }

  function openSettings() {
    if (panelLoader.item && panelLoader.item.opened) panelLoader.item.close()
    if (settingsLoader.item) settingsLoader.item.open()
  }

  function openMainPanel() {
    if (settingsLoader.item && settingsLoader.item.opened) settingsLoader.item.close()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
    if (settingsLoader.item) settingsLoader.item.close()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    if (settingsLoader.item) settingsLoader.item.closeForPopoutSwitch()
  }

  function fallbackPlayPause() {
    var player = activePlayer
    if (!player) return false
    if (player.canTogglePlaying && typeof player.togglePlaying === "function") {
      player.togglePlaying()
      return true
    }
    if (player.isPlaying && player.canPause && typeof player.pause === "function") {
      player.pause()
      return true
    }
    if (!player.isPlaying && player.canPlay && typeof player.play === "function") {
      player.play()
      return true
    }
    return false
  }

  function performPlayPause() {
    if (musicService && typeof musicService.playPause === "function") return musicService.playPause()
    return fallbackPlayPause()
  }

  function fallbackNext() {
    if (!activePlayer || !activePlayer.canGoNext || typeof activePlayer.next !== "function") return
    activePlayer.next()
  }

  function fallbackPrevious() {
    if (!activePlayer || !activePlayer.canGoPrevious || typeof activePlayer.previous !== "function") return
    activePlayer.previous()
  }

  function performNext() {
    if (musicService && typeof musicService.next === "function") musicService.next()
    else fallbackNext()
  }

  function performPrevious() {
    if (musicService && typeof musicService.previous === "function") musicService.previous()
    else fallbackPrevious()
  }

  function handleButtonPress(buttonCode) {
    if (buttonCode === Qt.LeftButton) {
      toggle()
    } else if (buttonCode === Qt.MiddleButton) {
      performPlayPause()
    }
  }

  function handleWheel(delta) {
    if (delta > 0) performPrevious()
    else if (delta < 0) performNext()
  }

  function injectPanels() {
    if (panelLoader.item) {
      panelLoader.item.bar = root.bar
      panelLoader.item.anchorItem = button
      panelLoader.item.hostWidget = root
      panelLoader.item.service = root.musicService
    }
    if (settingsLoader.item) {
      settingsLoader.item.bar = root.bar
      settingsLoader.item.anchorItem = button
      settingsLoader.item.hostWidget = root
      settingsLoader.item.service = root.musicService
    }
    if (fullBarLoader.item) {
      fullBarLoader.item.bar = root.bar
      fullBarLoader.item.service = root.musicService
    }
  }

  implicitWidth: root.pillTargetWidth
  implicitHeight: button.implicitHeight

  Behavior on implicitWidth {
    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
  }

  onBarChanged: {
    refreshService()
    injectPanels()
  }
  onServiceChanged: injectPanels()
  Component.onCompleted: refreshService()

  Timer {
    interval: 500
    running: root.bar !== null && !root.service
    repeat: true
    onTriggered: root.refreshService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanels()
      Qt.callLater(root.injectPanels)
    }
  }

  Loader {
    id: settingsLoader
    active: true
    source: Qt.resolvedUrl("SettingsPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanels()
      Qt.callLater(root.injectPanels)
    }
  }

  // Full-bar CAVA overlay: transparent click-through bar-sized windows, one per
  // screen. Created only while fullBarMode is on; toggling flips this binding
  // with no shell reload and no CAVA process restart.
  Loader {
    id: fullBarLoader
    active: root.fullBarMode
    source: Qt.resolvedUrl("FullBarCava.qml")
    onLoaded: {
      root.injectPanels()
      Qt.callLater(root.injectPanels)
    }
  }

  // The WidgetButton handles pointer gestures. It sits below the clipped surface
  // so the CAVA backdrop and foreground can use the same pill. BarWidget owns
  // the width via pillTargetWidth; button follows without a circular binding.
  WidgetButton {
    id: button
    width: root.implicitWidth
    height: parent.height
    z: 0
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: "Left-click to open; middle-click to play or pause; scroll to change track; right-click to toggle track text"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.musicService) root.musicService.showText = !root.musicService.showText
        else root.fallbackShowText = !root.fallbackShowText
      } else {
        root.handleButtonPress(buttonCode)
      }
    }
    onWheelMoved: function(delta) { root.handleWheel(delta) }
  }

  Item {
    id: capsuleMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Commons.Color.foreground
      antialiasing: true
    }
  }

  BorderSurface {
    id: capsule
    anchors.fill: parent
    padding: 0
    z: 1
    clip: true
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: capsuleMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
    radius: Style.cornerRadius
    // In full-bar mode the pill goes fully transparent (fill and border) so
    // only the icon, text, and controls float over the full-bar wave. The
    // cross-fade matches the pill visualizer fade below.
    color: root.fullBarMode
      ? "transparent"
      : root.opened
        ? Style.selectedFillFor(root.widgetForeground, Commons.Color.accent)
        : capsuleHover.hovered
          ? Style.hoverFillFor(root.widgetForeground, Commons.Color.accent)
          : Style.normalFillFor(root.widgetForeground, Commons.Color.accent)
    borderSpec: root.fullBarMode
      ? Border.none()
      : root.opened
        ? Border.controlSpec("normal", root.widgetForeground, Commons.Color.accent)
        : Border.none()

    Behavior on color {
      ColorAnimation { duration: 250 }
    }

    HoverHandler {
      id: capsuleHover
    }

    // The visualizer fills the whole pill behind the foreground, clipped to
    // the capsule shape. Opacity 0 in full-bar mode mutes the pill wave
    // without touching layout; the single CAVA process keeps running.
    CavaVisualizer {
      id: barVisualizer
      anchors.fill: parent
      bars: root.visualizerBars
      visualizerStyle: root.musicService ? root.musicService.visualizerStyle : "wave"
      accentColor: Commons.Color.accent
      active: root.isPlaying
      visible: root.musicService ? root.musicService.cavaAvailable === true : false
      opacity: root.fullBarMode ? 0 : (root.isPlaying ? 0.35 : 0.15)

      Behavior on opacity {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
      }
    }

    // Foreground-only margins preserve readable spacing without shrinking CAVA.
    Row {
      id: foregroundLayer
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)
      z: 1

      Text {
        id: playerIconLabel
        textFormat: Text.PlainText
        text: root.playerIcon
        visible: root.musicService ? root.musicService.showPlayerIcon === true : root.fallbackShowPlayerIcon
        width: visible ? implicitWidth : 0
        color: root.widgetForeground
        opacity: root.isWaiting ? 0.45 : 1.0
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: trackLabel
        textFormat: Text.PlainText
        visible: root.musicService ? root.musicService.showText === true : root.fallbackShowText
        text: root.displayLabel
        width: visible ? Math.min(Style.space(220), implicitWidth) : 0
        clip: true
        color: root.widgetForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
        anchors.verticalCenter: parent.verticalCenter

        // Animate the collapse/expand so the pill width (bound to this width)
        // glides instead of jumping a frame when the text is toggled.
        Behavior on width {
          NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
      }

      Row {
        id: controlRow
        visible: root.musicService ? root.musicService.showControls === true : root.fallbackShowControls
        width: visible ? controlButtons.implicitWidth : 0
        height: Style.space(28)
        spacing: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter

        Row {
          id: controlButtons
          spacing: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter

          Button {
            width: Style.space(24)
            height: Style.space(24)
            iconText: "󰒮"
            tooltipText: "Previous track"
            iconSize: Style.font.iconSmall
            foreground: root.widgetForeground
            accent: Commons.Color.accent
            background: "transparent"
            focusable: true
            enabled: root.activePlayer ? root.activePlayer.canGoPrevious === true : false
            onClicked: root.performPrevious()
          }

          Button {
            width: Style.space(28)
            height: Style.space(28)
            iconText: root.isPlaying ? "󰏤" : "󰐊"
            tooltipText: root.isPlaying ? "Pause" : "Play"
            iconSize: Style.font.icon
            foreground: root.widgetForeground
            accent: Commons.Color.accent
            background: "transparent"
            focusable: true
            enabled: root.activePlayer
              ? root.activePlayer.canTogglePlaying === true
                || root.activePlayer.canPause === true
                || root.activePlayer.canPlay === true
              : false
            onClicked: root.performPlayPause()
          }

          Button {
            width: Style.space(24)
            height: Style.space(24)
            iconText: "󰒭"
            tooltipText: "Next track"
            iconSize: Style.font.iconSmall
            foreground: root.widgetForeground
            accent: Commons.Color.accent
            background: "transparent"
            focusable: true
            enabled: root.activePlayer ? root.activePlayer.canGoNext === true : false
            onClicked: root.performNext()
          }
        }
      }

      Item {
        id: foregroundSpacer
        width: Math.max(0,
          foregroundLayer.width
          - root.foregroundItemsWidth
          - Style.space(8) * root.foregroundItemCount)
        visible: width > 0
        height: Style.space(1)
      }
    }
  }
}

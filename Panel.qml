import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "music-toolbar"
  ipcTarget: "music-toolbar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property real haloPhase: 0

  // Popup metadata and playback controls bind to the shared Service, so QML
  // propagates source and playback changes in place without a manual refresh.

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
  readonly property var activePlayer: service ? service.activePlayer : fallbackActivePlayer
  readonly property bool isPlaying: service
    ? service.isPlaying === true
    : Boolean(activePlayer && activePlayer.isPlaying)
  readonly property string trackTitle: service
    ? String(service.title || (service.isWaiting ? "Waiting for " + service.selectedPlayerLabel : "No music playing"))
    : String(activePlayer ? (activePlayer.trackTitle || "No music playing") : "No music playing")
  readonly property string trackArtist: service
    ? String(service.artist || "")
    : String(activePlayer ? (activePlayer.trackArtist || "") : "")
  readonly property string trackAlbum: service
    ? String(service.album || "")
    : String(activePlayer ? (activePlayer.trackAlbum || "") : "")
  readonly property string trackPublisher: service ? String(service.publisher || "") : ""
  readonly property string artworkUrl: service
    ? String(service.artUrl || "")
    : String(activePlayer ? (activePlayer.trackArtUrl || "") : "")
  readonly property real playbackPosition: service
    ? Number(service.position) || 0
    : Number(activePlayer ? activePlayer.position : 0) || 0
  readonly property real trackDuration: service
    ? Number(service.duration) || 0
    : Number(activePlayer && activePlayer.lengthSupported ? activePlayer.length : 0) || 0
  readonly property var lyricsFetcher: service ? service.lyrics : null
  readonly property var lyricLines: lyricsFetcher ? lyricsFetcher.lyricLines : []
  readonly property int activeLineIndex: lyricsFetcher ? lyricsFetcher.currentLineIndex : -1
  readonly property color contentForeground: bar ? bar.barForeground : Commons.Color.foreground

  function open() {
    root.controller.show()
  }

  function setServicePanelVisibility(value) {
    if (service && typeof service.setPanelVisible === "function")
      service.setPanelVisible(value)
  }

  function close() {
    setServicePanelVisibility(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function openSettings() {
    if (root.hostWidget && typeof root.hostWidget.openSettings === "function")
      root.hostWidget.openSettings()
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var remainder = value % 60
    return minutes + ":" + String(remainder).padStart(2, "0")
  }

  function performPlayPause() {
    if (service && typeof service.playPause === "function") {
      service.playPause()
      return
    }
    var player = activePlayer
    if (!player) return
    if (player.canTogglePlaying && typeof player.togglePlaying === "function") player.togglePlaying()
    else if (player.isPlaying && player.canPause && typeof player.pause === "function") player.pause()
    else if (!player.isPlaying && player.canPlay && typeof player.play === "function") player.play()
  }

  function performPrevious() {
    if (service && typeof service.previous === "function") {
      service.previous()
      return
    }
    if (activePlayer && activePlayer.canGoPrevious && typeof activePlayer.previous === "function") activePlayer.previous()
  }

  function performNext() {
    if (service && typeof service.next === "function") {
      service.next()
      return
    }
    if (activePlayer && activePlayer.canGoNext && typeof activePlayer.next === "function") activePlayer.next()
  }

  function seek(position) {
    if (service && typeof service.seek === "function") {
      service.seek(position)
      return
    }
    if (activePlayer && activePlayer.canSeek && activePlayer.positionSupported)
      activePlayer.position = Math.max(0, Math.min(trackDuration, Number(position) || 0))
  }

  onOpenedChanged: setServicePanelVisibility(opened)
  onServiceChanged: setServicePanelVisibility(opened)
  Component.onDestruction: setServicePanelVisibility(false)

  Timer {
    interval: 250
    running: root.opened && !root.service && root.isPlaying
    repeat: true
    onTriggered: {
      if (root.activePlayer) {
        try { root.activePlayer.positionChanged() } catch (error) { }
      }
    }
  }

  Timer {
    interval: 1000 / 30
    running: root.opened && root.isPlaying
    repeat: true
    onTriggered: root.haloPhase = (root.haloPhase + 0.18) % (Math.PI * 2)
  }

  // The main popup is a three-column layout: circular artwork and its animated
  // halo on the left, metadata and transport controls in the center, and synced
  // lyrics on the right. Source/style selectors live only in SettingsPanel.qml.
  KeyboardPanel {
    id: panelSurface
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(16)
    contentWidth: panelSurface.fittedContentWidth(Style.space(520))
    contentHeight: panelSurface.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Row {
          id: popupHeader
          width: parent.width
          height: settingsButton.height

          Text {
            textFormat: Text.PlainText
            width: parent.width - settingsButton.width
            height: parent.height
            text: "Now Playing"
            color: root.contentForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }

          Button {
            id: settingsButton
            width: Style.space(32)
            height: Style.space(32)
            iconText: "󰒓"
            tooltipText: "Open settings"
            iconSize: Style.font.icon
            foreground: root.contentForeground
            accent: Commons.Color.accent
            background: "transparent"
            focusable: true
            onClicked: root.openSettings()
          }
        }

        Row {
          id: mainArea
          width: parent.width
          height: Style.space(156)
          spacing: Style.space(16)

          readonly property real columnsWidth: width - spacing * 2
          readonly property real leftWidth: columnsWidth * 0.34
          readonly property real centerWidth: columnsWidth * 0.32

          Item {
            id: artworkColumn
            width: mainArea.leftWidth
            height: parent.height

            Item {
              id: artHalo
              readonly property real diameter: Math.min(parent.width, parent.height)
              readonly property real rayRadius: artBacking.width / 2 + Style.space(8)
              readonly property real intensity: root.service ? root.service.cavaIntensity : 0
              width: diameter
              height: diameter
              anchors.centerIn: parent

              Repeater {
                model: 48

                delegate: Rectangle {
                  required property int index
                  readonly property real angle: index * (360 / 48) * Math.PI / 180
                  width: Style.space(2)
                  height: Style.space(12)
                  radius: width / 2
                  x: artHalo.width / 2 + Math.cos(angle) * artHalo.rayRadius - width / 2
                  y: artHalo.height / 2 + Math.sin(angle) * artHalo.rayRadius - height / 2
                  rotation: index * (360 / 48) + 90
                  transformOrigin: Item.Center
                  color: Commons.Color.accent
                  opacity: 0.16 + artHalo.intensity * (0.28 + 0.42 * (0.5 + 0.5 * Math.sin(angle + root.haloPhase)))

                  Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                }
              }

              BorderSurface {
                id: artBacking
                width: Math.max(Style.space(72), artHalo.width - Style.space(32))
                height: width
                anchors.centerIn: parent
                radius: width / 2
                color: Style.normalFillFor(root.contentForeground, Commons.Color.accent)
                borderSpec: Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)
              }

              Image {
                id: artSource
                width: artBacking.width
                height: artBacking.height
                anchors.centerIn: parent
                source: root.artworkUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                visible: false
              }

              Item {
                id: artMask
                width: artBacking.width
                height: artBacking.height
                anchors.centerIn: parent
                visible: false
                layer.enabled: true

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: Commons.Color.foreground
                  antialiasing: true
                }
              }

              // QtQuick.Effects applies a circular alpha mask to the artwork.
              MultiEffect {
                width: artBacking.width
                height: artBacking.height
                anchors.centerIn: parent
                source: artSource
                maskEnabled: true
                maskSource: artMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                visible: artSource.status === Image.Ready
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: artBacking
                visible: artSource.status !== Image.Ready
                text: "󰝚"
                color: root.contentForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.displayLarge
              }
            }
          }

          Column {
            id: centerColumn
            width: mainArea.centerWidth
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.trackTitle
              color: root.contentForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              maximumLineCount: 1
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.trackArtist !== ""
              text: root.trackArtist
              color: Commons.Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              maximumLineCount: 1
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.trackAlbum !== ""
              text: root.trackAlbum
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              maximumLineCount: 1
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.trackPublisher !== ""
              text: root.trackPublisher
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              maximumLineCount: 1
              elide: Text.ElideRight
            }

            Item { width: Style.space(1); height: Style.space(2) }

            Row {
              width: parent.width
              height: playButton.height
              spacing: Style.space(8)
              anchors.horizontalCenter: parent.horizontalCenter

              Button {
                id: previousButton
                width: Style.space(32)
                height: Style.space(32)
                iconText: "󰒮"
                tooltipText: "Previous track"
                iconSize: Style.font.icon
                foreground: root.contentForeground
                accent: Commons.Color.accent
                background: "transparent"
                enabled: root.activePlayer ? root.activePlayer.canGoPrevious === true : false
                onClicked: root.performPrevious()
              }

              Button {
                id: playButton
                width: Style.space(40)
                height: Style.space(40)
                radius: width / 2
                iconText: root.isPlaying ? "󰏤" : "󰐊"
                tooltipText: root.isPlaying ? "Pause" : "Play"
                iconSize: Style.font.iconLarge
                foreground: Commons.Color.background
                accent: Commons.Color.background
                background: Commons.Color.accent
                enabled: root.activePlayer
                  ? root.activePlayer.canTogglePlaying === true
                    || root.activePlayer.canPause === true
                    || root.activePlayer.canPlay === true
                  : false
                onClicked: root.performPlayPause()
              }

              Button {
                id: nextButton
                width: Style.space(32)
                height: Style.space(32)
                iconText: "󰒭"
                tooltipText: "Next track"
                iconSize: Style.font.icon
                foreground: root.contentForeground
                accent: Commons.Color.accent
                background: "transparent"
                enabled: root.activePlayer ? root.activePlayer.canGoNext === true : false
                onClicked: root.performNext()
              }
            }

            Row {
              id: progressRow
              width: parent.width
              height: Style.space(24)
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                width: Style.space(32)
                height: parent.height
                text: root.formatTime(root.playbackPosition)
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                verticalAlignment: Text.AlignVCenter
              }

              PanelSlider {
                id: progressSlider
                width: Math.max(Style.space(52), parent.width - Style.space(32) * 2 - parent.spacing * 2)
                height: parent.height
                bar: root.bar
                minimum: 0
                maximum: Math.max(1, root.trackDuration)
                value: Math.min(root.playbackPosition, root.trackDuration)
                step: 1
                enabled: root.activePlayer
                  ? root.activePlayer.canSeek === true
                    && root.activePlayer.positionSupported === true
                    && root.trackDuration > 0
                  : false
                onReleased: function(value) { root.seek(value) }
              }

              Text {
                textFormat: Text.PlainText
                width: Style.space(32)
                height: parent.height
                text: root.formatTime(root.trackDuration)
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          Column {
            id: lyricsColumn
            width: mainArea.columnsWidth - mainArea.leftWidth - mainArea.centerWidth
            height: parent.height
            spacing: Style.space(4)

            Text {
              id: lyricsHeading
              textFormat: Text.PlainText
              width: parent.width
              text: "Lyrics"
              color: root.contentForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Item {
              id: lyricsViewport
              width: parent.width
              height: parent.height - lyricsHeading.implicitHeight - lyricsFooter.implicitHeight - lyricsColumn.spacing * 3 - lyricsDivider.height

              ListView {
                id: lyricsList
                anchors.fill: parent
                visible: root.lyricLines.length > 0
                clip: true
                model: root.lyricLines
                currentIndex: root.activeLineIndex
                spacing: Style.space(8)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Text {
                  id: lyricLine
                  textFormat: Text.PlainText
                  required property int index
                  required property var modelData
                  width: lyricsList.width
                  text: modelData.text
                  color: index === root.activeLineIndex
                    ? Commons.Color.accent
                    : index < root.activeLineIndex
                      ? Qt.darker(root.contentForeground, 1.6)
                      : Qt.darker(root.contentForeground, 1.2)
                  opacity: index === root.activeLineIndex ? 1.0 : (index < root.activeLineIndex ? 0.5 : 0.7)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: index === root.activeLineIndex ? Style.font.subtitle : Style.font.bodySmall
                  font.bold: index === root.activeLineIndex
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  height: implicitHeight
                  transformOrigin: Item.Center

                  Connections {
                    target: root.lyricsFetcher
                    function onCurrentLineIndexChanged() {
                      if (lyricLine.index === root.activeLineIndex) pulseAnimation.restart()
                    }
                  }

                  SequentialAnimation {
                    id: pulseAnimation
                    NumberAnimation {
                      target: lyricLine
                      property: "scale"
                      from: 1.0
                      to: 1.05
                      duration: 120
                      easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                      target: lyricLine
                      property: "scale"
                      from: 1.05
                      to: 1.0
                      duration: 120
                      easing.type: Easing.OutCubic
                    }
                  }
                }

                onCurrentIndexChanged: {
                  if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                }

                Behavior on contentY {
                  NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)
                visible: root.lyricLines.length === 0

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(6)
                  visible: root.lyricsFetcher && root.lyricsFetcher.lyricsState === "instrumental"

                  Text {
                    textFormat: Text.PlainText
                    text: "󰝚"
                    color: Commons.Color.accent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Instrumental"
                    color: root.contentForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(6)
                  visible: root.lyricsFetcher && root.lyricsFetcher.lyricsState === "loading"

                  Text {
                    textFormat: Text.PlainText
                    text: "󰑐"
                    color: Commons.Color.accent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter

                    RotationAnimation on rotation {
                      from: 0
                      to: 360
                      duration: 900
                      loops: Animation.Infinite
                      running: root.opened
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Loading..."
                    color: root.contentForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: lyricsViewport.width
                  visible: !root.lyricsFetcher
                    || root.lyricsFetcher.lyricsState === "idle"
                    || root.lyricsFetcher.lyricsState === "not-found"
                    || root.lyricsFetcher.lyricsState === "rate-limited"
                  text: root.lyricsFetcher ? root.lyricsFetcher.statusText : "No lyrics found"
                  color: Util.alpha(root.contentForeground, 0.5)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }

            PanelSeparator {
              id: lyricsDivider
              foreground: root.contentForeground
              strength: 0.12
            }

            Text {
              id: lyricsFooter
              textFormat: Text.PlainText
              width: parent.width
              text: root.lyricsFetcher && root.lyricsFetcher.source === "lrclib"
                ? "[LRCLIB]"
                : root.lyricsFetcher && root.lyricsFetcher.source === "lyrics.ovh"
                  ? "[lyrics.ovh]"
                  : ""
              color: Qt.darker(root.contentForeground, 1.8)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

      }
    }
  }
}

import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "music-toolbar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property color contentForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property bool settingsReady: service ? service.configReady === true : false
  function close() {
    root.controller.hide()
  }

  function backToMain() {
    if (root.hostWidget && typeof root.hostWidget.openMainPanel === "function")
      root.hostWidget.openMainPanel()
    else
      root.close()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: panelSurface
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(16)
    contentWidth: panelSurface.fittedContentWidth(Style.space(460))
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
          id: settingsHeader
          width: parent.width
          height: backButton.height
          spacing: Style.space(8)

          Button {
            id: backButton
            width: Style.space(32)
            height: Style.space(32)
            iconText: "󰁍"
            tooltipText: "Back to music"
            iconSize: Style.font.icon
            foreground: root.contentForeground
            accent: Commons.Color.accent
            background: "transparent"
            focusable: true
            onClicked: root.backToMain()
          }

          Text {
            textFormat: Text.PlainText
            height: parent.height
            text: "Settings"
            color: root.contentForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
          strength: 0.12
        }

        PanelSectionHeader {
          width: parent.width
          text: "Playback source and visualizer"
          foreground: root.contentForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        // PlayerSelector contains the Auto/recent MPRIS source choice and the
        // CAVA rendering style controls. It is intentionally Settings-only.
        PlayerSelector {
          id: playerSelector
          width: parent.width
          height: Style.space(52)
          enabled: root.settingsReady
          service: root.service
          contentForeground: root.contentForeground
        }

        PanelSeparator {
          foreground: root.contentForeground
          strength: 0.12
        }

        // Toggles assign to the shared Service; its property signals persist
        // preferences while the bar and popup update through normal bindings.
        PanelSectionHeader {
          width: parent.width
          text: "Bar display"
          foreground: root.contentForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Toggle {
          id: iconToggle
          width: parent.width
          enabled: root.settingsReady
          label: "Show player icon"
          description: "Show the active player's icon in the bar widget."
          checked: root.service ? root.service.showPlayerIcon === true : true
          foreground: root.contentForeground
          accent: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: {
            if (root.service) root.service.showPlayerIcon = !root.service.showPlayerIcon
          }
        }

        Toggle {
          id: textToggle
          width: parent.width
          enabled: root.settingsReady
          label: "Show track text"
          description: "Show the current track title and artist in the bar widget."
          checked: root.service ? root.service.showText === true : true
          foreground: root.contentForeground
          accent: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: {
            if (root.service) root.service.showText = !root.service.showText
          }
        }

        Toggle {
          id: controlsToggle
          width: parent.width
          enabled: root.settingsReady
          label: "Show playback controls"
          description: "Add previous, play or pause, and next controls to the bar widget."
          checked: root.service ? root.service.showControls === true : false
          foreground: root.contentForeground
          accent: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: {
            if (root.service) root.service.showControls = !root.service.showControls
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
          strength: 0.12
        }

        // Visualizer placement owns the full-bar CAVA preference. The toggle
        // assigns a single Service property; persistence and widget updates
        // follow through normal bindings without a shell reload.
        PanelSectionHeader {
          width: parent.width
          text: "Visualizer placement"
          foreground: root.contentForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Toggle {
          id: fullBarToggle
          width: parent.width
          enabled: root.settingsReady
          label: "Full-bar visualizer"
          description: "Render the CAVA wave across the entire topbar instead of only inside the widget."
          checked: root.service ? root.service.fullBarCava === true : false
          foreground: root.contentForeground
          accent: Commons.Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: {
            if (root.service) root.service.fullBarCava = !root.service.fullBarCava
          }
        }

        // The overlay is a transparent click-through bar-sized layer, so it
        // never intercepts clicks; the pill turns transparent while it is on
        // and returns to the themed fill when it is off.
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.service ? root.service.fullBarCava === true : false
          text: "Shows the CAVA wave across the entire topbar in a transparent layer that never intercepts clicks. The widget pill turns transparent while this is on."
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

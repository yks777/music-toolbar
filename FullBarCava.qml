import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Full-bar CAVA overlay. One transparent, click-through PanelWindow per screen,
// sized like the host bar, painting only the visualizer wave. It consumes the
// same single 96-bar CAVA feed as the widget pill and never touches layout,
// input, or the shell lifecycle.
Item {
  id: root

  property var service: null
  property var bar: null

  readonly property bool isVertical: bar ? bar.vertical === true : false
  readonly property string barPosition: bar ? String(bar.position || "top") : "top"
  readonly property int barThickness: bar && bar.barSize ? bar.barSize : Style.bar.sizeHorizontal
  readonly property var waveBars: service ? service.cavaBars : []
  readonly property string waveStyle: service ? String(service.visualizerStyle || "wave") : "wave"
  readonly property bool waveActive: service ? service.isPlaying === true : false
  readonly property bool waveAvailable: service ? service.cavaAvailable === true : false
  readonly property real waveOpacity: root.waveActive ? 0.35 : 0.15

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: root.waveAvailable
        // Fully transparent: only wave pixels are painted, never a backdrop.
        color: "transparent"
        // No exclusive zone, so the bar layout never shifts when this maps.
        exclusionMode: ExclusionMode.Ignore
        // Empty input mask: every click passes through to whatever is behind.
        mask: Region {}
        WlrLayershell.namespace: "music-toolbar-cava"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: root.barPosition === "top" || root.isVertical
          bottom: root.barPosition === "bottom" || root.isVertical
          left: root.barPosition === "left" || !root.isVertical
          right: root.barPosition === "right" || !root.isVertical
        }
        implicitWidth: root.isVertical ? root.barThickness : 0
        implicitHeight: root.isVertical ? 0 : root.barThickness

        // Belt and suspenders alongside mask: this subtree never takes input.
        Item {
          anchors.fill: parent
          enabled: false

          // Horizontal bars: the wave fills the whole bar height.
          CavaVisualizer {
            visible: !root.isVertical && root.waveAvailable
            anchors.fill: parent
            bars: root.waveBars
            visualizerStyle: root.waveStyle
            accentColor: Commons.Color.accent
            active: root.waveActive
            opacity: root.waveOpacity

            Behavior on opacity {
              NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
          }

          // Vertical bars: the wave fills the whole bar height.
          CavaVisualizer {
            visible: root.isVertical && root.waveAvailable
            anchors.fill: parent
            bars: root.waveBars
            visualizerStyle: root.waveStyle
            accentColor: Commons.Color.accent
            active: root.waveActive
            opacity: root.waveOpacity

            Behavior on opacity {
              NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property string visualizerStyle: "wave"
  property var bars: []
  property color accentColor: Commons.Color.accent
  property bool active: true

  // The CAVA feed stays at a fixed high resolution (96 samples). QML slices
  // (and never upsamples) it to the current width: the pill shows a subset
  // while the full-bar overlay uses the whole feed. No process restart.
  readonly property int feedLength: (root.bars || []).length
  readonly property int displayBarCount: Math.max(8, Math.min(root.feedLength, Math.floor(width / Style.space(8))))
  readonly property var displayBars: {
    var source = bars || []
    var count = Math.min(displayBarCount, source.length)
    return source.slice(0, count)
  }
  readonly property real pitch: displayBars.length > 0 ? width / Math.max(1, displayBars.length) : 0

  function normalizedBar(index) {
    var samples = displayBars || []
    if (index < 0 || index >= samples.length) return 0
    return Math.max(0, Math.min(1, (Number(samples[index]) || 0) / 255))
  }

  // Perceptual gain shared by every renderer: lifts quiet passages into
  // visibility while capping loud peaks at 1.0 so nothing flat-tops.
  function shapedLevel(index) {
    return Math.max(0, Math.min(1, Math.pow(normalizedBar(index), 0.65) * 1.2))
  }

  // Style changes swap only this renderer; the fixed-resolution CAVA process
  // remains owned by Service and is not restarted by the Loader.
  Loader {
    anchors.fill: parent
    sourceComponent: root.visualizerStyle === "bars"
      ? barsComponent
      : root.visualizerStyle === "dots"
        ? dotsComponent
        : waveComponent
  }

  // Wave draws a smoothed spline across the full width, anchored to the
  // bottom edge: a soft glow under a crisp crest line, filled with a vertical
  // gradient that dissolves toward the bottom for a calm, harmonious read.
  Component {
    id: waveComponent

    Canvas {
      id: waveCanvas
      anchors.fill: parent
      renderTarget: Canvas.FramebufferObject
      antialiasing: true

      function samplePoints() {
        var samples = root.displayBars || []
        var count = samples.length
        var pts = []
        if (count < 2 || width <= 0 || height <= 0) return pts
        var baseY = height
        var stepX = width / (count - 1)
        for (var i = 0; i < count; i++) {
          var x = i === count - 1 ? width : i * stepX
          pts.push({ x: x, y: baseY - root.shapedLevel(i) * height * 0.9 })
        }
        return pts
      }

      // Catmull-Rom spline through the samples, stroked as cubic Beziers so
      // the crest flows instead of zig-zagging between raw sample values.
      function traceSpline(ctx, pts) {
        var n = pts.length
        ctx.moveTo(pts[0].x, pts[0].y)
        for (var i = 0; i < n - 1; i++) {
          var p0 = pts[Math.max(0, i - 1)]
          var p1 = pts[i]
          var p2 = pts[i + 1]
          var p3 = pts[Math.min(n - 1, i + 2)]
          ctx.bezierCurveTo(
            p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6,
            p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6,
            p2.x, p2.y
          )
        }
      }

      onPaint: {
        var pts = samplePoints()
        if (pts.length < 2) {
          var empty = getContext("2d")
          empty.clearRect(0, 0, width, height)
          return
        }
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        // Gradient fill dissolving toward the bottom edge.
        var fill = ctx.createLinearGradient(0, 0, 0, height)
        fill.addColorStop(0, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.42))
        fill.addColorStop(0.55, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16))
        fill.addColorStop(1, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.02))
        ctx.beginPath()
        traceSpline(ctx, pts)
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = fill
        ctx.fill()

        // Soft halo beneath the crest.
        ctx.beginPath()
        traceSpline(ctx, pts)
        ctx.strokeStyle = root.accentColor
        ctx.globalAlpha = 0.14
        ctx.lineWidth = Math.max(3, Style.spaceReal(4))
        ctx.stroke()

        // Crisp crest line on top.
        ctx.beginPath()
        traceSpline(ctx, pts)
        ctx.globalAlpha = 0.9
        ctx.lineWidth = Style.spaceReal(1.75)
        ctx.stroke()
        ctx.globalAlpha = 1.0
      }

      Connections {
        target: root
        function onDisplayBarsChanged() { waveCanvas.requestPaint() }
        function onWidthChanged() { waveCanvas.requestPaint() }
        function onHeightChanged() { waveCanvas.requestPaint() }
        function onAccentColorChanged() { waveCanvas.requestPaint() }
      }
    }
  }

  // Bars grow upward from the bottom edge as sharp squares separated by hair
  // gaps, edge-to-edge as a group. Height carries the level while opacity
  // deepens with it, so loud passages glow and quiet ones recede.
  Component {
    id: barsComponent

    Row {
      id: barRow
      anchors.fill: parent
      spacing: Style.space(2)

      Repeater {
        model: root.displayBars.length

        delegate: Item {
          required property int index
          readonly property real level: root.shapedLevel(index)
          width: (root.width - (root.displayBars.length - 1) * barRow.spacing) / Math.max(1, root.displayBars.length)
          height: root.height

          Rectangle {
            width: parent.width
            height: Math.max(Style.space(2), parent.level * root.height * 0.9)
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 0
            color: root.accentColor
            opacity: root.active ? 0.25 + parent.level * 0.75 : 0.3

            Behavior on height {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }
  }

  // Dots sit on the bottom edge across the full width. Diameter and opacity
  // both follow the level, capped by the bar pitch so dense full-bar rows
  // read as texture instead of blobs.
  Component {
    id: dotsComponent

    Item {
      anchors.fill: parent

      Repeater {
        model: root.displayBars.length

        delegate: Rectangle {
          required property int index
          readonly property real level: root.shapedLevel(index)
          readonly property real dotSize: Math.min(
            root.pitch * 0.55,
            Style.space(2) + level * Style.space(4)
          )
          width: Math.max(Style.space(1.5), dotSize)
          height: width
          x: root.displayBars.length < 2
            ? 0
            : (root.width - width) * index / (root.displayBars.length - 1)
          y: root.height - height
          radius: width / 2
          color: root.accentColor
          opacity: root.active ? 0.25 + level * 0.75 : 0.3

          Behavior on x {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
          }
          Behavior on width {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
          }
          Behavior on height {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }
}

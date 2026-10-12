import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var service: null

  readonly property string selectedPlayerKey: service ? String(service.selectedPlayerKey || "") : ""
  readonly property string selectedStyle: service ? String(service.visualizerStyle || "wave") : "wave"
  readonly property var sourceChoices: {
    var result = [{ key: "", name: "Auto", icon: "󰝚" }]
    var selected = service ? String(service.selectedPlayerKey || "") : ""
    var players = service && service.playerChoices ? service.playerChoices : []
    var selectedFound = selected === ""
    for (var i = 0; i < players.length; i++) {
      var choice = players[i]
      result.push({ key: choice.key, name: choice.name, icon: choice.icon })
      if (choice.key === selected) selectedFound = true
    }
    if (selected && !selectedFound) {
      var label = service && service.selectedPlayerLabel ? String(service.selectedPlayerLabel) : selected
      var icon = service && typeof service.sourceIconForKey === "function"
        ? service.sourceIconForKey(selected) : "󰝚"
      result.push({ key: selected, name: label + " (unavailable)", icon: icon })
    }
    return result
  }
  readonly property var styleChoices: [
    { key: "wave", name: "Wave", icon: "󰎆" },
    { key: "bars", name: "Bars", icon: "󰝛" },
    { key: "dots", name: "Dots", icon: "󰄰" }
  ]
  property color contentForeground: Commons.Color.foreground

  function revealSelectedPlayer() {
    var targetKey = selectedPlayerKey
    for (var i = 0; i < playerRepeater.count; i++) {
      var item = playerRepeater.itemAt(i)
      if (!item || item.choiceKey !== targetKey) continue
      var left = item.x
      var right = item.x + item.width
      if (left < playerFlick.contentX) playerFlick.contentX = left
      else if (right > playerFlick.contentX + playerFlick.width)
        playerFlick.contentX = right - playerFlick.width
      return
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(4)

    Row {
      id: playerRow
      width: parent.width
      height: Style.space(24)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: Style.space(42)
        height: parent.height
        text: "Player"
        color: Qt.darker(root.contentForeground, 1.2)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        verticalAlignment: Text.AlignVCenter
      }

      Flickable {
        id: playerFlick
        width: parent.width - Style.space(42) - parent.spacing
        height: parent.height
        contentWidth: playerPills.implicitWidth
        contentHeight: playerPills.height
        clip: true
        interactive: contentWidth > width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: playerPills
          spacing: Style.space(4)
          height: parent.height

          Repeater {
            id: playerRepeater
            model: root.sourceChoices

            delegate: BorderSurface {
              id: playerPill
              required property var modelData
              readonly property string choiceKey: String(modelData.key || "")
              readonly property bool selected: root.selectedPlayerKey === choiceKey
              readonly property bool hovered: playerHover.hovered
              implicitHeight: Style.space(24)
              height: Style.space(24)
              width: sourceContent.implicitWidth + Style.space(12)
              radius: Style.spacing.labelGap * 2
              padding: Style.space(0)
              color: selected
                ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                : hovered
                  ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                  : Style.normalFillFor(root.contentForeground, Commons.Color.accent)
              borderSpec: selected
                ? Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)
                : Border.none()

              Behavior on color {
                ColorAnimation { duration: 120 }
              }

              Row {
                id: sourceContent
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: modelData.icon
                  color: playerPill.selected ? Commons.Color.accent : root.contentForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconSmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: playerPill.selected ? Commons.Color.accent : root.contentForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              HoverHandler { id: playerHover }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.service) root.service.selectedPlayerKey = playerPill.choiceKey
                }
              }
            }
          }
        }

        onWidthChanged: Qt.callLater(root.revealSelectedPlayer)
      }
    }

    Row {
      id: styleRow
      width: parent.width
      height: Style.space(24)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: Style.space(42)
        height: parent.height
        text: "Style"
        color: Qt.darker(root.contentForeground, 1.2)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        verticalAlignment: Text.AlignVCenter
      }

      Row {
        spacing: Style.space(4)
        height: parent.height

        Repeater {
          model: root.styleChoices

          delegate: BorderSurface {
            id: stylePill
            required property var modelData
            readonly property bool selected: root.selectedStyle === String(modelData.key)
            readonly property bool hovered: styleHover.hovered
            implicitHeight: Style.space(24)
            height: Style.space(24)
            width: styleContent.implicitWidth + Style.space(12)
            radius: Style.spacing.labelGap * 2
            padding: Style.space(0)
            color: selected
              ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
              : hovered
                ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                : Style.normalFillFor(root.contentForeground, Commons.Color.accent)
            borderSpec: selected
              ? Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)
              : Border.none()

            Behavior on color {
              ColorAnimation { duration: 120 }
            }

            Row {
              id: styleContent
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: modelData.icon
                color: stylePill.selected ? Commons.Color.accent : root.contentForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.iconSmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.name
                color: stylePill.selected ? Commons.Color.accent : root.contentForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            HoverHandler { id: styleHover }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.service) root.service.visualizerStyle = String(stylePill.modelData.key)
              }
            }
          }
        }
      }
    }
  }

  onSelectedPlayerKeyChanged: Qt.callLater(revealSelectedPlayer)
  onSourceChoicesChanged: Qt.callLater(revealSelectedPlayer)
}

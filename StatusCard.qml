import QtQuick
import qs.Commons

Item {
  id: root

  property var cardData: null
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  implicitHeight: Style.space(26)
  height: implicitHeight

  Row {
    anchors.fill: parent

    Text {
      text: root.cardData ? root.cardData.label : "Status"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.48)
    }

    Text {
      id: statusValue
      text: root.cardData ? root.cardData.value : "--"
      color: root.cardData && root.cardData.state === "ok" ? Color.accent : root.cardData && root.cardData.state === "unknown" ? root.dim : root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      width: parent.width - Style.space(8) - Math.min(implicitWidth, parent.width * 0.48)
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { ColorAnimation { duration: 160 } }
    }
  }
}

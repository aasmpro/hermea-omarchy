import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui as Ui

Item {
  id: root

  property string label: ""
  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool showLabel: true
  property bool textStyle: false
  property bool heroStyle: false
  property bool hasCursor: false
  readonly property bool popupOpen: selectorPopup.opened

  signal changed(string value)
  signal hovered(bool isHovered)

  implicitHeight: root.heroStyle ? Style.font.title : Style.spacing.controlHeight

  function toggle() {
    if (!root.enabled || !root.options.length) return
    selectorPopup.opened ? selectorPopup.close() : selectorPopup.open()
  }

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Ui.CursorSurface {
      id: selectorSurface
      width: parent.width
      height: root.heroStyle ? Style.font.title : Style.spacing.controlHeight
      foreground: root.foreground
      bordered: false
      hasCursor: root.heroStyle ? false : root.hasCursor
      opacity: root.enabled ? 1 : 0.55
      color: root.textStyle ? "transparent" : Style.controlFill(false, selectorHover.hovered || root.hasCursor, root.foreground, Color.accent)

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.heroStyle ? 0 : Style.spacing.controlPaddingX
        anchors.rightMargin: root.heroStyle ? 0 : Style.spacing.controlPaddingX
        spacing: Style.spacing.xs

        Text {
          text: root.value || root.label
          font.family: root.fontFamily
          color: root.foreground
          font.pixelSize: root.heroStyle ? Style.font.title : root.textStyle ? Style.font.title : Style.font.body
          font.bold: root.heroStyle || root.textStyle
          elide: Text.ElideRight
          width: parent.width - chevron.width - parent.spacing
        }
        Text {
          id: chevron
          text: "󰅀"
          visible: !root.heroStyle
          color: root.enabled ? Color.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      HoverHandler {
        id: selectorHover
        onHoveredChanged: root.hovered(hovered)
      }
      MouseArea {
        anchors.fill: parent
        enabled: root.enabled && root.options.length > 0
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { selectorSurface.forceActiveFocus(); root.toggle() }
      }
    }
  }

  QQC.Popup {
    id: selectorPopup
    y: selectorSurface.height + Style.spacing.xxs
    width: selectorSurface.width
    height: Math.min(listView.contentHeight + Style.space(4), Style.space(260))
    padding: 0
    modal: false
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    background: Ui.BorderSurface {
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
      radius: Style.cornerRadius
    }
    ListView {
      id: listView
      anchors.fill: parent
      model: root.options
      clip: true
      delegate: Item {
        required property var modelData
        width: listView.width
        height: Style.spacing.popupRowHeight
        Rectangle { anchors.fill: parent; color: itemMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent" }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width - Style.space(40)
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          visible: modelData.value === root.value
          text: "󰄬"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.changed(modelData.value); selectorPopup.close() }
        }
      }
    }
  }
}

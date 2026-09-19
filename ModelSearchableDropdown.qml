import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui as Ui

Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property string placeholderText: "Search..."
  property string emptyText: "No matches"
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true
  property bool textStyle: false
  property bool heroStyle: false
  property bool hasCursor: false
  property bool popupOpen: popup.opened

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(option) { return option && typeof option === "object" ? String(option.value) : String(option) }
  function selectedOption() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return options[i]
    return null
  }
  function toggle() {
    if (!root.enabled || !root.options.length) return
    popup.opened ? popup.close() : popup.open()
  }
  function recompute() {
    var query = searchField.text.toLowerCase()
    if (!query) { filtered = options; return }
    filtered = options.filter(function(option) {
      return String(option.label || "").toLowerCase().indexOf(query) >= 0
        || String(option.description || "").toLowerCase().indexOf(query) >= 0
    })
  }

  property var filtered: options
  onOptionsChanged: recompute()
  implicitHeight: root.heroStyle
    ? Style.font.caption + Style.space(4)
    : showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

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

    Ui.BorderSurface {
      id: trigger
      width: parent.width
      height: root.heroStyle ? Style.font.caption + Style.space(4) : root.rowHeight
      radius: Style.cornerRadius
      color: root.textStyle ? "transparent" : Style.controlFill(false, triggerHover.hovered || root.hasCursor, root.foreground, root.accent)
      borderSpec: root.textStyle ? Border.none() : (triggerHover.hovered || root.hasCursor ? Border.controlSpec("hover-cursor", root.foreground, root.accent) : Border.none())
      opacity: root.enabled ? 1 : 0.55

      HoverHandler { id: triggerHover; onHoveredChanged: root.hovered(hovered) }

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.heroStyle ? 0 : Style.spacing.controlPaddingX
        anchors.rightMargin: root.heroStyle ? 0 : Style.spacing.md
        spacing: Style.spacing.controlGap

        Text {
          visible: !root.heroStyle
          text: root.selectedOption() ? root.selectedOption().icon : "󰘦"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: root.selectedOption() ? root.selectedOption().label : root.placeholderText
          color: root.heroStyle ? Qt.darker(root.foreground, 1.4) : root.selectedOption() ? root.foreground : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: root.heroStyle ? Style.font.caption : root.textStyle ? Style.font.body : Style.font.body
          font.bold: root.textStyle && !root.heroStyle
          elide: Text.ElideRight
          width: parent.width - parent.children[0].width - Style.spacing.controlGap
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.spacing.controlGap
        text: "󰅀"
        visible: !root.heroStyle
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.enabled && root.options.length > 0
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { trigger.forceActiveFocus(); root.toggle() }
      }

      QQC.Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        width: trigger.width
        height: Math.min(list.contentHeight + Style.space(52), Style.space(430))
        padding: Style.spacing.hairline
        background: Ui.BorderSurface {
          color: root.background
          borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
          radius: Style.cornerRadius
        }
        onOpened: { searchField.text = ""; root.recompute(); Qt.callLater(function() { searchField.forceActiveFocus() }) }
        onClosed: searchField.text = ""

        contentItem: Column {
          spacing: 0
          Item {
            width: parent.width
            height: Style.spacing.popupRowHeight + Style.spacing.controlPaddingX
            Ui.TextField {
              id: searchField
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              placeholderText: root.placeholderText
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: root.recompute()
            }
          }
          Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.10) }
          ListView {
            id: list
            width: parent.width
            height: popup.height - Style.spacing.popupRowHeight - Style.spacing.controlPaddingX - 1
            clip: true
            model: root.filtered
            delegate: Item {
              required property var modelData
              required property int index
              width: list.width
              height: Math.max(root.popupRowHeight, titleColumn.implicitHeight + Style.spacing.rowPaddingX)

              Rectangle {
                anchors.fill: parent
                color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              }
              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                spacing: Style.spacing.controlGap
                Text {
                  text: modelData.icon || "󰘦"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                  id: titleColumn
                  width: parent.width - Style.font.icon - Style.spacing.controlGap - (modelData.current ? Style.font.icon + Style.spacing.controlGap : 0)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs
                  Row {
                    width: parent.width
                    spacing: Style.spacing.xxs
                    Text { text: modelData.providerLabel || "Provider"; color: Qt.darker(root.foreground, 1.4); font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Text { text: "· " + (modelData.modelLabel || modelData.model || ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width - x }
                  }
                  Text { text: modelData.description || ""; color: Qt.darker(root.foreground, 1.5); font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
                }
                Text {
                  visible: !!modelData.current
                  text: "󰄬"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.value = modelData.value; root.changed(modelData.value); popup.close() }
              }
            }
            Text { visible: list.count === 0; anchors.centerIn: parent; text: root.emptyText; color: Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.body }
          }
        }
      }
    }
  }
}

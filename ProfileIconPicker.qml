import QtQuick
import qs.Commons
import qs.Ui as Ui

Ui.BorderSurface {
  id: root

  FontLoader {
    id: fontAwesomeSolid
    source: "file:///usr/share/fonts/WOFF2/fa-solid-900.woff2"
  }

  property var icons: []
  property string selectedIcon: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool opened: false

  signal selected(string glyph)

  visible: opened
  z: 1000
  width: Math.min(parent ? parent.width - Style.space(24) : Style.space(360), Style.space(360))
  height: width
  color: Color.popups.background
  borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
  radius: Style.cornerRadius

  Grid {
    id: iconGrid
    anchors.fill: parent
    anchors.margins: Style.space(10)
    columns: 5
    spacing: Style.space(6)

    Repeater {
      model: root.icons
      delegate: Ui.CursorSurface {
        required property var modelData
        width: (iconGrid.width - iconGrid.spacing * 4) / 5
        height: width
        bordered: false
        foreground: root.foreground
        current: modelData.glyph === root.selectedIcon

        Text {
          anchors.centerIn: parent
          text: modelData.fontFamily && fontAwesomeSolid.status !== FontLoader.Ready
            ? (modelData.fallbackGlyph || modelData.glyph) : modelData.glyph
          color: root.foreground
          font.family: modelData.fontFamily && fontAwesomeSolid.status === FontLoader.Ready ? modelData.fontFamily : root.fontFamily
          font.pixelSize: Style.font.display
        }
        MouseArea {
          id: iconMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(modelData.glyph)
        }
        Ui.PanelToolTip {
          visible: iconMouse.containsMouse
          text: modelData.name || "Profile icon"
          fontFamily: root.fontFamily
        }
      }
    }
  }
}

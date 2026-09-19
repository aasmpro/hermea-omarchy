import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
  id: root
  moduleName: "io.github.aasmpro.hermea"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  FontLoader {
    id: fontAwesomeSolid
    source: "file:///usr/share/fonts/WOFF2/fa-solid-900.woff2"
  }
  readonly property bool fontAwesomeAvailable: fontAwesomeSolid.status === FontLoader.Ready
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("hermes-panel.py").toString().replace(/^file:\/\//, ""))
  readonly property string dashboardPath: decodeURIComponent(Qt.resolvedUrl("open-dashboard.sh").toString().replace(/^file:\/\//, ""))
  readonly property var cardSchema: [
    { id: "gateway", label: "Gateway" }, { id: "dashboard", label: "Dashboard" },
    { id: "sessions", label: "Sessions" }, { id: "jobs", label: "Jobs" },
    { id: "version", label: "Version" }, { id: "skills", label: "Skills" }
  ]
  readonly property string fallbackProfileIcon: "󱚣"
  readonly property var iconCatalog: [
    { glyph: "󱚣", name: "agent" }, { glyph: "󰚩", name: "assistant" },
    { glyph: "󰘦", name: "robot" }, { glyph: "", fallbackGlyph: "󰘦", name: "bot", fontFamily: "Font Awesome 7 Free Solid" },
    { glyph: "󰧑", name: "brain" }, { glyph: "", fallbackGlyph: "󰧑", name: "neural", fontFamily: "Font Awesome 7 Free Solid" },
    { glyph: "󱕅", name: "spark" }, { glyph: "", name: "magic" },
    { glyph: "", name: "lightbulb" }, { glyph: "", name: "star" },
    { glyph: "󰀄", name: "account" }, { glyph: "", name: "balanced" },
    { glyph: "", name: "power" }, { glyph: "󰒋", name: "memory" },
    { glyph: "", name: "code" }, { glyph: "", name: "terminal" },
    { glyph: "󰭻", name: "chat" }, { glyph: "󰏗", name: "tools" },
    { glyph: "󰒍", name: "network" }, { glyph: "", name: "shield" },
    { glyph: "", name: "heart" }, { glyph: "󰈹", name: "explore" },
    { glyph: "󰕮", name: "orb" }, { glyph: "", name: "mystery" },
    { glyph: "", name: "verified" }
  ]

  property string selectedProfile: "default"
  property var report: null
  property var reportsByProfile: ({})
  property var profileCatalog: [{ value: "default", label: "default" }]
  property string requestProfile: "default"
  property string lastError: ""
  property bool cursorActive: false
  property int cursorIndex: 0
  property bool refreshModels: false
  property bool refreshAfterSnapshot: false
  property string pendingProvider: ""
  property string pendingModel: ""
  property string pendingModelValue: ""
  property string pendingProfileIcon: ""
  property string pendingProfileIconProfile: ""
  property bool modelChangePending: false
  property bool iconPickerOpen: false
  property bool profileInitialized: false
  readonly property bool refreshing: snapshotProcess.running
  readonly property bool changingModel: modelChangePending || modelSetProcess.running
  readonly property int refreshIntervalSeconds: boundedNumber("refreshIntervalSeconds", 15, 5, 300)
  readonly property bool refreshModelsOnOpen: setting("refreshModelsOnOpen", false) === true
  readonly property string configuredDefaultProfile: validProfileName(String(setting("defaultProfile", "default"))) ? String(setting("defaultProfile", "default")) : "default"
  readonly property string dashboardHost: validDashboardHost(String(setting("dashboardHost", "127.0.0.1"))) ? String(setting("dashboardHost", "127.0.0.1")) : "127.0.0.1"
  readonly property int dashboardPort: boundedNumber("dashboardPort", 9119, 1, 65535)
  readonly property int panelWidth: boundedNumber("panelWidth", 440, 320, 720)
  readonly property int panelMaxHeight: boundedNumber("panelMaxHeight", 530, 360, 900)
  readonly property bool showChatAction: setting("showChatAction", true) !== false
  readonly property bool showDashboardAction: setting("showDashboardAction", true) !== false
  readonly property bool profileAvailable: report && report.available === true && report.profiles && report.profiles.length > 0
  readonly property var cards: report ? report.cards : blankCards()
  readonly property var profileOptions: report ? report.profiles.map(function(profile) { return { value: profile.name, label: profile.name } }) : profileCatalog
  readonly property var modelOptions: report ? report.models.options : []
  readonly property string modelValue: pendingModelValue !== "" ? pendingModelValue : (report ? report.models.selected : "")
  readonly property string currentProfileIcon: profileIconFor(selectedProfile)
  readonly property string displayedProfileIcon: !root.fontAwesomeAvailable && currentProfileIcon === "" ? "󰘦" : (!root.fontAwesomeAvailable && currentProfileIcon === "" ? "󰧑" : currentProfileIcon)
  readonly property var selectedModelOption: modelOptions.find(function(item) { return item.value === modelValue })
  readonly property string errorText: lastError || (report ? report.errors.join("\n") : "")
  readonly property var visibleCardData: {
    var configured = setting("visibleStatusCards", cardSchema.map(function(item) { return item.id }))
    if (!(configured instanceof Array)) configured = cardSchema.map(function(item) { return item.id })
    var allowed = {}
    configured.forEach(function(id) { allowed[String(id)] = true })
    return cards.filter(function(item) { return allowed[item.id] })
  }

  function boundedNumber(name, fallback, minimum, maximum) {
    var value = Number(setting(name, fallback))
    if (isNaN(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(value)))
  }

  function validProfileName(value) {
    return /^[a-z0-9][a-z0-9_-]{0,63}$/.test(value)
  }

  function validDashboardHost(value) {
    return /^[A-Za-z0-9.:-]+$/.test(value)
  }

  function blankCards() {
    return cardSchema.map(function(schema) {
      return { id: schema.id, label: schema.label, value: "Unknown", state: "unknown", detail: null }
    })
  }

  function switchPanel(direction) {
    return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.barIdentity, direction) : false
  }

  function refresh(models) {
    if (snapshotProcess.running) return
    requestProfile = selectedProfile
    refreshModels = models === true
    lastError = ""
    snapshotProcess.running = true
  }

  function applySnapshot(text) {
    try {
      var data = JSON.parse(text)
      if (!data || data.schemaVersion !== 4 || data.profile !== requestProfile || typeof data.available !== "boolean" || !Array.isArray(data.cards)
          || data.cards.length !== cardSchema.length || !Array.isArray(data.profiles) || !data.models
          || !Array.isArray(data.models.options) || !Array.isArray(data.errors)
          || typeof data.collectedAt !== "string" || isNaN(Date.parse(data.collectedAt))) throw new Error("Invalid snapshot")
      data.cards.forEach(function(card, index) {
        if (!card || card.id !== cardSchema[index].id || typeof card.label !== "string" || typeof card.value !== "string"
            || ["ok", "inactive", "neutral", "unknown"].indexOf(card.state) < 0
            || !(card.detail === null || typeof card.detail === "string")) throw new Error("Invalid card")
      })
      data.profiles.forEach(function(profile) {
        if (!profile || typeof profile.name !== "string" || !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(profile.name)
            || !(profile.icon === undefined || typeof profile.icon === "string")) throw new Error("Invalid profile")
      })
      data.models.options.forEach(function(option) {
        if (!option || typeof option.value !== "string" || typeof option.label !== "string"
            || typeof option.provider !== "string" || typeof option.model !== "string") throw new Error("Invalid model")
      })
      var nextReports = {}
      for (var profileName in reportsByProfile) nextReports[profileName] = reportsByProfile[profileName]
      nextReports[data.profile] = data
      reportsByProfile = nextReports
      profileCatalog = data.profiles.map(function(profile) { return { value: profile.name, label: profile.name } })
      if (data.profile === selectedProfile) report = data
      if (data.profile === selectedProfile) pendingModelValue = ""
      lastError = ""
      cursorIndex = Math.min(cursorIndex, 4)
    } catch (error) {
      failSnapshot("Could not read Hermes status. Refresh to retry.")
    }
  }

  function failSnapshot(message) {
    lastError = message
  }

  function chooseProfile(name) {
    if (name === selectedProfile || profileIconProcess.running || !validProfileName(name)) return
    selectedProfile = name
    report = reportsByProfile[name] || null
    if (snapshotProcess.running) refreshAfterSnapshot = true
    else refresh(false)
  }

  function launchChat() {
    if (root.changingModel || !root.profileAvailable || !root.selectedModelOption || !root.showChatAction) return
    var option = selectedModelOption
    Quickshell.execDetached(["python3", helperPath, "chat", selectedProfile,
      option ? option.provider : "", option ? option.model : ""])
    root.close()
  }

  function setModel(value) {
    if (!value || root.changingModel) return
    var option = modelOptions.find(function(item) { return item.value === value })
    if (!option) return
    pendingProvider = option.provider
    pendingModel = option.model
    pendingModelValue = value
    modelChangePending = true
    lastError = ""
    modelSetProcess.running = true
  }

  function launchDashboard() {
    if (root.changingModel || !root.profileAvailable || !root.selectedModelOption || !root.showDashboardAction) return
    var option = selectedModelOption
    Quickshell.execDetached(["bash", dashboardPath, selectedProfile,
      option ? option.provider : "", option ? option.model : "", root.dashboardHost, String(root.dashboardPort)])
    root.close()
  }

  function cardIcon(cardId) {
    if (cardId === "gateway") return "󰒍"
    if (cardId === "dashboard") return "󰕮"
    if (cardId === "sessions") return "󰒋"
    if (cardId === "jobs") return "󰃰"
    if (cardId === "version") return "󰋼"
    if (cardId === "skills") return "󰘧"
    return "󰋼"
  }

  function cardStateIcon(card) {
    if (!card || card.state === "unknown" || card.state === "inactive") return "󰅙"
    if (card.state === "ok") return "󰄬"
    return "󰋼"
  }

  function activateCursor() {
    if (cursorIndex === 0) root.openIconPicker()
    else if (cursorIndex === 1 && profileDropdown.enabled) profileDropdown.toggle()
    else if (cursorIndex === 2) modelDropdown.toggle()
    else if (cursorIndex === 3) launchChat()
    else if (cursorIndex === 4) launchDashboard()
  }

  function profileIconFor(profileName) {
    if (!report || !report.profiles) return fallbackProfileIcon
    var profile = report.profiles.find(function(item) { return item.name === profileName })
    return profile && typeof profile.icon === "string" && profile.icon.length > 0 ? profile.icon : fallbackProfileIcon
  }

  function openIconPicker() {
    root.iconPickerOpen = true
  }

  function saveProfileIcon(glyph) {
    iconPickerOpen = false
    pendingProfileIcon = glyph
    pendingProfileIconProfile = selectedProfile
    var nextReport = report
    if (nextReport && nextReport.profiles) {
      var updatedReport = {}
      for (var key in nextReport) updatedReport[key] = nextReport[key]
      updatedReport.profiles = nextReport.profiles.map(function(item) {
        return item.name === selectedProfile ? { name: item.name, icon: glyph } : item
      })
      nextReport = updatedReport
      report = nextReport
      var nextReports = {}
      for (var profileName in reportsByProfile) nextReports[profileName] = reportsByProfile[profileName]
      nextReports[selectedProfile] = nextReport
      reportsByProfile = nextReports
    }
    profileIconProcess.running = true
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = 0
    } else {
      cursorIndex = Math.max(0, Math.min(4, cursorIndex + (dy || dx)))
    }
    Qt.callLater(function() {
      var item = cursorIndex === 0 ? profileIconButton : cursorIndex === 1 ? profileDropdown : cursorIndex === 2 ? modelDropdown : cursorIndex === 3 ? chatButton : dashboardButton
      if (!item) return
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      if (top < panelFlick.contentY) panelFlick.contentY = top
      else if (bottom > panelFlick.contentY + panelFlick.height) panelFlick.contentY = bottom - panelFlick.height
    })
  }

  onOpenedChanged: {
    if (opened) {
      if (!profileInitialized) {
        selectedProfile = configuredDefaultProfile
        requestProfile = selectedProfile
        profileInitialized = true
      }
      cursorActive = false
      cursorIndex = 0
      panelFlick.contentY = 0
      refresh(refreshModelsOnOpen)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.iconPickerOpen = false
    }
  }

  Process {
    id: snapshotProcess
    command: root.refreshModels
      ? ["python3", root.helperPath, "snapshot", root.requestProfile, "--refresh-models", "--dashboard-host", root.dashboardHost, "--dashboard-port", String(root.dashboardPort)]
      : ["python3", root.helperPath, "snapshot", root.requestProfile, "--dashboard-host", root.dashboardHost, "--dashboard-port", String(root.dashboardPort)]
    stdout: StdioCollector { id: snapshotOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applySnapshot(snapshotOutput.text)
      else if (root.requestProfile === root.selectedProfile)
        root.failSnapshot("Hermes status helper failed. Refresh to retry.")
      root.refreshModels = false
      if (root.refreshAfterSnapshot) {
        root.refreshAfterSnapshot = false
        Qt.callLater(function() { root.refresh(false) })
      }
    }
  }

  Process {
    id: modelSetProcess
    command: ["python3", root.helperPath, "set-model", root.selectedProfile, root.pendingProvider, root.pendingModel]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.modelChangePending = false
      if (exitCode === 0) root.refresh(true)
      else {
        root.pendingModelValue = ""
        root.lastError = "Could not change the Hermes model."
      }
    }
  }

  Process {
    id: profileIconProcess
    command: ["python3", root.helperPath, "set-profile-icon", root.pendingProfileIconProfile, root.pendingProfileIcon]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.lastError = "Could not save the profile icon."
      root.pendingProfileIcon = ""
      root.pendingProfileIconProfile = ""
    }
  }

  Timer {
    interval: root.refreshIntervalSeconds * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh(false)
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight, Style.space(root.panelMaxHeight))

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: profileDropdown.popupOpen || modelDropdown.popupOpen || iconPicker.opened
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text.toLowerCase() === "r") root.refresh(false) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(profileIconButton.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)
            Ui.BorderSurface {
              id: profileIconButton
              width: Style.space(48)
              height: Style.space(48)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: "transparent"
              borderSpec: Border.none()
              Text {
                anchors.centerIn: parent
                text: root.displayedProfileIcon
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
              MouseArea {
                id: profileIconMouse
                anchors.fill: parent
                enabled: root.profileAvailable && !profileIconProcess.running
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { root.cursorActive = true; root.cursorIndex = 0 }
                onClicked: root.openIconPicker()
              }
              Ui.PanelToolTip {
                visible: profileIconMouse.containsMouse
                text: "Choose profile icon"
                fontFamily: root.fontFamily
              }
            }
            Column {
              id: heroLabels
              anchors.left: profileIconButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: heroActions.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0
              TextSelector {
                id: profileDropdown
                width: parent.width
                enabled: root.profileAvailable && !profileIconProcess.running
                label: "Profile"
                showLabel: false
                textStyle: true
                heroStyle: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                options: root.profileOptions
                value: root.selectedProfile
                hasCursor: root.cursorActive && root.cursorIndex === 1
                onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.cursorIndex = 1 } }
                onChanged: function(value) { root.chooseProfile(value) }
              }
              ModelSearchableDropdown {
                id: modelDropdown
                width: parent.width
                label: "Model"
                showLabel: false
                textStyle: true
                heroStyle: true
                placeholderText: "Choose a model…"
                emptyText: "No matching models"
                foreground: root.foreground
                fontFamily: root.fontFamily
                options: root.modelOptions
                value: root.modelValue
                hasCursor: root.cursorActive && root.cursorIndex === 2
                enabled: root.profileAvailable && root.modelOptions.length > 0
                onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.cursorIndex = 2 } }
                onChanged: function(value) { root.setModel(value) }
              }
            }
            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Ui.Button {
                id: chatButton
                text: ""
                iconText: "󰆍"
                visible: root.showChatAction
                enabled: root.profileAvailable && !!root.selectedModelOption && !root.changingModel
                opacity: root.profileAvailable && !!root.selectedModelOption && !root.changingModel ? 1 : 0.42
                width: Style.space(34)
                height: Style.space(34)
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: !root.changingModel && root.cursorActive && root.cursorIndex === 3
                tooltipText: "Open Hermes chat"
                onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.cursorIndex = 3 } }
                onClicked: root.launchChat()
              }
              Ui.Button {
                id: dashboardButton
                text: ""
                iconText: "󰕮"
                visible: root.showDashboardAction
                enabled: root.profileAvailable && !!root.selectedModelOption && !root.changingModel
                opacity: root.profileAvailable && !!root.selectedModelOption && !root.changingModel ? 1 : 0.42
                width: Style.space(34)
                height: Style.space(34)
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: !root.changingModel && root.cursorActive && root.cursorIndex === 4
                tooltipText: "Open Hermes dashboard"
                onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.cursorIndex = 4 } }
                onClicked: root.launchDashboard()
              }
            }
          }
          Ui.PanelSeparator { foreground: root.foreground }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(20)
            rowSpacing: Style.space(2)
            Repeater {
              model: root.visibleCardData
              delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(1)
                StatusLabel { text: modelData.label }
                StatusValue { cardData: modelData }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.errorText !== ""
            textFormat: Text.PlainText
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      MouseArea {
        id: iconPickerDismissArea
        anchors.fill: parent
        visible: iconPicker.opened
        enabled: visible
        z: 999
        onClicked: root.iconPickerOpen = false
      }

      ProfileIconPicker {
        id: iconPicker
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(50)
        opened: root.iconPickerOpen
        icons: root.iconCatalog
        selectedIcon: root.currentProfileIcon
        foreground: root.foreground
        fontFamily: root.fontFamily
        onSelected: function(glyph) { root.saveProfileIcon(glyph) }
      }

  component StatusLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component StatusValue: Text {
    property var cardData: null

    textFormat: Text.PlainText
    text: cardData ? cardData.value : "--"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    Layout.fillWidth: true
    Behavior on color { ColorAnimation { duration: 160 } }
  }

    }
  }

}

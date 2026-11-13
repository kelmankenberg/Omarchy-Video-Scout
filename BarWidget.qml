import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "scroll-read.js" as ScrollRead

BarWidget {
  id: root
  moduleName: "kel.omarchy-video-scout"

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property string dateRange: "week"
  property string status: ""
  property string downloadingId: ""
  property var videos: []
  property var rangeResults: ({})
  property var rangeResultLimits: ({})
  property int resultLimit: 50
  property int searchResultLimit: 50
  readonly property var resultLimits: [50, 100, 150]
  property bool automaticRefresh: false
  property var readVideoIds: ({})
  property bool readStateLoaded: false
  property string readStateError: ""
  property string pluginVersion: ""
  property string supportError: ""
  property var pendingScrollReads: ({})
  property real previousReadScrollY: 0
  property bool setupPage: false
  property int refreshMinutes: 0
  property bool refreshSettingsLoaded: false
  property string refreshSettingsError: ""
  readonly property var refreshIntervals: [0, 10, 15, 30, 45, 60, 90, 120]

  readonly property string home: Quickshell.env("HOME")
  readonly property string downloadPath: home + "/Videos/Omarchy Video Scout"
  readonly property var visibleVideos: videos

  onPopupOpenChanged: resetScrollRead()
  onSetupPageChanged: resetScrollRead()
  onDateRangeChanged: resetScrollRead()

  function resetScrollRead() {
    pendingScrollReads = {}
    previousReadScrollY = videoScroll.contentItem ? videoScroll.contentItem.contentY : 0
  }

  function observeReadScroll() {
    if (!popupOpen || setupPage || searchProc.running || !readStateLoaded) {
      resetScrollRead()
      return
    }
    var currentY = videoScroll.contentItem.contentY
    var rows = []
    for (var i = 0; i < videoRows.count; i++) {
      var row = videoRows.itemAt(i)
      if (row && !isRead(row.modelData.id)) {
        rows.push({id: row.modelData.id, bottom: row.y + row.height})
      }
    }
    pendingScrollReads = ScrollRead.advance(pendingScrollReads, rows,
      previousReadScrollY, currentY, Date.now())
    previousReadScrollY = currentY
  }

  Connections {
    target: videoScroll.contentItem
    function onContentYChanged() { root.observeReadScroll() }
  }

  Timer {
    interval: 100
    repeat: true
    running: root.popupOpen && !root.setupPage && Object.keys(root.pendingScrollReads).length > 0
    onTriggered: {
      root.observeReadScroll()
      if (!readStateProc.running) {
        var ids = ScrollRead.ready(root.pendingScrollReads, Date.now())
        if (ids.length > 0) root.markVideos(ids, true)
      }
    }
  }

  function helperPath(filename) {
    var path = Qt.resolvedUrl("bin/" + (filename || "search-videos.py")).toString()
    if (path.indexOf("file://") === 0) path = path.substring(7)
    try { path = decodeURIComponent(path) } catch (e) {}
    return path
  }

  function issueUrl(kind) {
    if (!pluginVersion || ["bug-report", "feature-request"].indexOf(kind) < 0) return ""
    return "https://github.com/kelmankenberg/Omarchy-Video-Scout/issues/new?template="
      + encodeURIComponent(kind + ".yml") + "&version=" + encodeURIComponent(pluginVersion)
  }

  function openIssue(kind) {
    var url = issueUrl(kind)
    if (!url || !Qt.openUrlExternally(url)) {
      supportError = strings.t("support.openFailed")
      console.warn("Video Scout: could not open support form")
    } else supportError = ""
  }

  FileView {
    path: root.helperPath("../manifest.json")
    onLoaded: {
      try {
        var version = JSON.parse(text()).version
        if (typeof version !== "string" || version.length > 64
            || !/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$/.test(version))
          throw new Error("Invalid manifest version")
        root.pluginVersion = version
        root.supportError = ""
      } catch (error) {
        root.supportError = strings.t("support.versionFailed")
        console.warn("Video Scout manifest:", error)
      }
    }
    onLoadFailed: {
      root.supportError = strings.t("support.versionFailed")
      console.warn("Video Scout: could not load manifest version")
    }
  }

  function fetchVideos(automatic) {
    if (searchProc.running) return
    resetScrollRead()
    automaticRefresh = automatic === true
    searchResultLimit = resultLimit
    status = ""
    searchProc.command = ["python3", root.helperPath(), root.dateRange, String(root.searchResultLimit)]
    searchProc.running = true
  }

  function selectRange(value) {
    if (["day", "week", "month", "all"].indexOf(value) < 0) {
      console.warn("Video Scout: invalid date range")
      return
    }
    if (searchProc.running) return
    dateRange = value
    videos = root.rangeResults[value] || []
    downloadStatus = ""
    fetchVideos()
  }

  function open() {
    popupOpen = true
  }

  function close() {
    popupOpen = false
  }

  function toggle() {
    if (popupOpen) close()
    else open()
  }

  function finishSearch(exitCode, output) {
    if (exitCode !== 0) {
      videos = []
      try {
        var failure = JSON.parse(output)
        status = failure && failure.error
          ? String(failure.error).replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 240)
          : strings.t("panel.searchFailed")
      } catch (error) {
        status = strings.t("panel.searchFailed")
      }
      return
    }

    try {
      var payload = JSON.parse(output)
      var rows = payload && Array.isArray(payload.videos) ? payload.videos : []
      var cleanRows = []
      for (var i = 0; i < rows.length && i < root.searchResultLimit; i++) {
        var row = rows[i]
        if (!row || !/^[A-Za-z0-9_-]{11}$/.test(String(row.id || ""))) continue
        if (row.uploadDate !== "" && !/^\d{8}$/.test(String(row.uploadDate || ""))) continue
        var title = String(row.title || "").slice(0, 240)
        if (!title) continue
        cleanRows.push({
          id: String(row.id),
          title: title,
          channel: String(row.channel || "").slice(0, 120),
          uploadDate: String(row.uploadDate),
          timestamp: typeof row.timestamp === "number" && isFinite(row.timestamp) ? row.timestamp : 0
        })
      }
      cleanRows.sort(function(a, b) {
        return b.timestamp - a.timestamp
      })
      videos = cleanRows
      status = payload && payload.error ? String(payload.error).slice(0, 200) : ""
      if (payload && Array.isArray(payload.videos) && !payload.error) {
        var cached = Object.assign({}, root.rangeResults)
        cached[root.dateRange] = cleanRows
        root.rangeResults = cached
        var limits = Object.assign({}, root.rangeResultLimits)
        limits[root.dateRange] = root.searchResultLimit
        root.rangeResultLimits = limits
      }
    } catch (error) {
      videos = []
      status = strings.t("panel.searchFailed")
    }
  }

  function dateTimestamp(uploadDate) {
    var year = Number(uploadDate.slice(0, 4))
    var month = Number(uploadDate.slice(4, 6)) - 1
    var day = Number(uploadDate.slice(6, 8))
    return new Date(year, month, day).getTime()
  }

  function formattedDate(uploadDate) {
    if (!uploadDate) return strings.t("video.dateUnknown")
    var value = new Date(dateTimestamp(uploadDate))
    return value.toLocaleString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy")
  }

  function videoUrl(id) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(String(id || ""))) return ""
    return "https://www.youtube.com/watch?v=" + id
  }

  function thumbnailUrl(id) {
    if (!/^[A-Za-z0-9_-]{11}$/.test(String(id || ""))) return ""
    return "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg"
  }

  function watchVideo(id) {
    var url = videoUrl(id)
    if (url) Qt.openUrlExternally(url)
  }

  function downloadVideo(id) {
    if (downloadingId || !/^[A-Za-z0-9_-]{11}$/.test(String(id || ""))) return
    downloadingId = id
    downloadProc.running = true
  }

  function finishDownload(exitCode, errorText) {
    downloadingId = ""
    if (exitCode === 0) {
      downloadStatus = strings.t("video.downloaded")
      return
    }
    var detail = String(errorText || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim()
    if (detail.length > 220) detail = detail.slice(0, 220) + "…"
    if (!detail) detail = strings.t("video.unknownError")
    downloadStatus = strings.t("video.downloadFailed").arg(detail)
  }

  property string downloadStatus: ""

  function isRead(id) {
    return root.readVideoIds[id] === true
  }

  function unreadCount(range) {
    var rows = root.rangeResults[range]
    if (!rows || !root.readStateLoaded || root.readStateError !== "") return -1
    var ids = {}
    for (var i = 0; i < rows.length; i++) {
      if (!root.isRead(rows[i].id)) ids[rows[i].id] = true
    }
    return Object.keys(ids).length
  }

  function markVideos(ids, read) {
    if (!readStateLoaded || readStateProc.running || ids.length === 0) return
    var pending = Object.assign({}, pendingScrollReads)
    for (var i = 0; i < ids.length; i++) delete pending[ids[i]]
    pendingScrollReads = pending
    readStateError = ""
    readStateProc.command = ["python3", helperPath("read-state.py"), read ? "read" : "unread"].concat(ids)
    readStateProc.running = true
  }

  Process {
    id: readStateProc
    command: ["python3", root.helperPath("read-state.py")]
    running: true
    stdout: StdioCollector { id: readStateOut; waitForEnd: true }
    stderr: StdioCollector { id: readStateErr; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.readStateLoaded = true
        if (exitCode !== 0) {
          root.readStateError = strings.t("read.saveFailed")
          console.warn("Video Scout read state:", readStateErr.text)
          return
        }
        try {
          var ids = JSON.parse(readStateOut.text).readIds
          if (!Array.isArray(ids) || ids.length > 100000) throw new Error("Invalid read state")
          var map = {}
          for (var i = 0; i < ids.length; i++) {
            if (!/^[A-Za-z0-9_-]{11}$/.test(ids[i])) throw new Error("Invalid video ID")
            map[ids[i]] = true
          }
          root.readVideoIds = map
          root.readStateError = ""
        } catch (error) {
          root.readStateError = strings.t("read.saveFailed")
          console.warn("Video Scout read state:", error)
        }
      })
    }
  }

  function saveRefreshInterval(minutes) {
    if (!refreshSettingsLoaded || refreshSettingsProc.running
        || refreshIntervals.indexOf(minutes) < 0) return
    refreshSettingsError = ""
    refreshSettingsProc.command = ["python3", helperPath("refresh-settings.py"), String(minutes)]
    refreshSettingsProc.running = true
  }

  function saveResultLimit(limit) {
    if (!refreshSettingsLoaded || refreshSettingsProc.running
        || resultLimits.indexOf(limit) < 0) return
    refreshSettingsError = ""
    refreshSettingsProc.command = ["python3", helperPath("refresh-settings.py"), "--limit", String(limit)]
    refreshSettingsProc.running = true
  }

  Process {
    id: refreshSettingsProc
    command: ["python3", root.helperPath("refresh-settings.py")]
    running: true
    stdout: StdioCollector { id: refreshSettingsOut; waitForEnd: true }
    stderr: StdioCollector { id: refreshSettingsErr; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.refreshSettingsLoaded = true
        if (exitCode !== 0) {
          root.refreshSettingsError = strings.t("setup.saveFailed")
          console.warn("Video Scout settings:", refreshSettingsErr.text)
          return
        }
        try {
          var settings = JSON.parse(refreshSettingsOut.text)
          var minutes = settings.refreshMinutes
          var limit = settings.resultLimit
          if (root.refreshIntervals.indexOf(minutes) < 0) throw new Error("Invalid interval")
          if (root.resultLimits.indexOf(limit) < 0) throw new Error("Invalid video limit")
          var restartTimer = !refreshTimer.running || root.refreshMinutes !== minutes
          root.refreshMinutes = minutes
          root.resultLimit = limit
          root.refreshSettingsError = ""
          if (minutes === 0) refreshTimer.stop()
          else if (restartTimer) refreshTimer.restart()
        } catch (error) {
          root.refreshSettingsError = strings.t("setup.saveFailed")
          console.warn("Video Scout settings:", error)
        }
      })
    }
  }

  Timer {
    id: refreshTimer
    interval: Math.max(1, root.refreshMinutes) * 60000
    repeat: true
    onTriggered: root.fetchVideos(true)
  }

  ShellIpc {
    target: "kel.omarchy-video-scout"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.fetchVideos() }
    function selectRange(value: string) { root.selectRange(value) }
    function status(): string {
      return JSON.stringify({
        searching: searchProc.running,
        automaticRefresh: searchProc.running && root.automaticRefresh,
        readStateError: root.readStateError,
        readResults: root.visibleVideos.filter(function(video) { return root.isRead(video.id) }).length,
        rangeUnreadCounts: {
          day: root.unreadCount("day"),
          week: root.unreadCount("week"),
          month: root.unreadCount("month"),
          all: root.unreadCount("all")
        },
        refreshMinutes: root.refreshMinutes,
        resultLimit: root.resultLimit,
        version: root.pluginVersion,
        refreshTimerRunning: refreshTimer.running,
        refreshSettingsError: root.refreshSettingsError,
        opened: root.opened,
        panelGeometry: {
          x: popup.cardOrigin.x,
          y: popup.cardOrigin.y,
          width: popup.contentWidth,
          height: popup.contentHeight
        },
        error: root.status,
        range: root.dateRange,
        results: root.videos.length,
        titles: root.videos.map(function(video) { return video.title }),
        matching: root.visibleVideos.length,
        viewportWidth: videoScroll.availableWidth,
        listWidth: videoList.width,
        listHeight: videoList.implicitHeight,
        rows: videoRows.count,
        firstRowHeight: videoRows.count > 0 ? videoRows.itemAt(0).height : 0,
        firstThumbnailStatus: videoRows.count > 0 ? videoRows.itemAt(0).thumbnailStatus : -1,
        firstDate: root.visibleVideos.length > 0
          ? root.formattedDate(root.visibleVideos[0].uploadDate) : ""
      })
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.finishSearch(exitCode, String(searchOut.text || ""))
        root.resetScrollRead()
      })
    }
  }

  Process {
    id: downloadProc
    command: [
      "yt-dlp",
      "--ignore-config",
      "--no-playlist",
      "--no-warnings",
      "--no-progress",
      "--socket-timeout", "20",
      "--paths", root.downloadPath,
      "--output", "%(title).160s [%(id)s].%(ext)s",
      "--",
      root.videoUrl(root.downloadingId)
    ]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: downloadErr; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() { root.finishDownload(exitCode, String(downloadErr.text || "")) })
    }
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: searchProc.running && root.automaticRefresh
    activeColor: Commons.Color.accent
    fontSize: Style.font.body
    tooltipText: strings.t("widget.tooltip")
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: contentColumn
    contentWidth: popup.fittedContentWidth(Style.space(520), 640)
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, 660)

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(10)
      focus: true
      Keys.onEscapePressed: root.close()

      RowLayout {
        width: parent.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: button.text
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: strings.t("panel.title")
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Button {
          text: root.setupPage ? strings.t("setup.back") : strings.t("setup.title")
          onClicked: root.setupPage = !root.setupPage
        }
        Button {
          text: searchProc.running ? strings.t("panel.loading") : strings.t("panel.refresh")
          enabled: !searchProc.running
          onClicked: root.fetchVideos()
        }
      }

      ScrollView {
        id: setupScroll
        visible: root.setupPage
        width: parent.width
        contentWidth: availableWidth
        height: Math.min(Style.space(500), setupContent.implicitHeight)
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        Column {
          id: setupContent
          width: setupScroll.availableWidth
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: strings.t("setup.refreshing")
            color: Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("setup.description")
            color: Color.popups.text
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          ComboBox {
            width: parent.width
            model: root.refreshIntervals.map(function(minutes) {
              return minutes === 0 ? strings.t("setup.off")
                : strings.tn("setup.minutes", minutes).arg(Commons.I18n.formatNumber(minutes))
            })
            currentIndex: root.refreshIntervals.indexOf(root.refreshMinutes)
            enabled: root.refreshSettingsLoaded && !refreshSettingsProc.running
            onActivated: function(index) {
              root.saveRefreshInterval(root.refreshIntervals[index])
            }
          }
          Text {
            textFormat: Text.PlainText
            text: strings.t("setup.resultLimit")
            color: Color.popups.text
            font.pixelSize: Style.font.body
          }
          ComboBox {
            width: parent.width
            model: root.resultLimits.map(function(limit) {
              return strings.t("setup.videos").arg(Commons.I18n.formatNumber(limit))
            })
            currentIndex: root.resultLimits.indexOf(root.resultLimit)
            enabled: root.refreshSettingsLoaded && !refreshSettingsProc.running
            onActivated: function(index) {
              root.saveResultLimit(root.resultLimits[index])
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("setup.limitDescription")
            color: Color.popups.text
            opacity: 0.72
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
          Text {
            visible: root.refreshSettingsError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.refreshSettingsError
            color: "#ff8a80"
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          Rectangle {
            width: parent.width
            height: 1
            color: Color.popups.border
          }
          Text {
            textFormat: Text.PlainText
            text: strings.t("support.title")
            color: Color.popups.text
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("support.description")
            color: Color.popups.text
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
          Text {
            visible: root.pluginVersion !== ""
            textFormat: Text.PlainText
            text: strings.t("support.version").arg(root.pluginVersion)
            color: Color.popups.text
            font.pixelSize: Style.font.bodySmall
          }
          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            Button {
              Layout.fillWidth: true
              text: strings.t("support.help")
              onClicked: {
                if (!Qt.openUrlExternally("https://github.com/kelmankenberg/Omarchy-Video-Scout#use"))
                  root.supportError = strings.t("support.openFailed")
              }
            }
            Button {
              Layout.fillWidth: true
              text: strings.t("support.feature")
              enabled: root.pluginVersion !== ""
              onClicked: root.openIssue("feature-request")
            }
            Button {
              Layout.fillWidth: true
              text: strings.t("support.bug")
              enabled: root.pluginVersion !== ""
              onClicked: root.openIssue("bug-report")
            }
          }
          Text {
            visible: root.supportError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.supportError
            color: "#ff8a80"
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
        }
      }

      Column {
        visible: !root.setupPage
        width: parent.width
        spacing: Style.space(10)
        RowLayout {
          width: parent.width
          spacing: Style.space(6)
          Button {
            Layout.fillWidth: true
            text: strings.t("read.allRead")
            enabled: root.readStateLoaded && !readStateProc.running && root.visibleVideos.length > 0
            onClicked: root.markVideos(root.visibleVideos.map(function(video) { return video.id }), true)
          }
          Button {
            Layout.fillWidth: true
            text: strings.t("read.allUnread")
            enabled: root.readStateLoaded && !readStateProc.running && root.visibleVideos.length > 0
            onClicked: root.markVideos(root.visibleVideos.map(function(video) { return video.id }), false)
          }
        }
        Text {
          visible: root.readStateError !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.readStateError
          color: "#ff8a80"
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
        RowLayout {
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: [
              { id: "day", label: strings.t("range.day") },
              { id: "week", label: strings.t("range.week") },
              { id: "month", label: strings.t("range.month") },
              { id: "all", label: strings.t("range.all") }
            ]
            delegate: Button {
              id: rangeButton
              required property var modelData
              readonly property int unread: root.unreadCount(modelData.id)
              Layout.fillWidth: true
              text: modelData.label
              tooltipText: unread < 0 ? strings.t("range.notSearched")
                : strings.tn("range.cachedUnread", unread)
                  .arg(Commons.I18n.formatNumber(unread))
                  .arg(Commons.I18n.formatNumber(root.rangeResultLimits[modelData.id]))
              selected: root.dateRange === modelData.id
              enabled: !searchProc.running
              onClicked: root.selectRange(modelData.id)
              Rectangle {
                visible: rangeButton.unread >= 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                width: Math.max(Style.space(18), badgeLabel.implicitWidth + Style.space(8))
                height: Style.space(18)
                radius: height / 2
                color: Commons.Color.accent
                Text {
                  id: badgeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: Commons.I18n.formatNumber(Math.max(0, rangeButton.unread))
                  color: Color.popups.background
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("panel.searchingNote").arg(Commons.I18n.formatNumber(root.resultLimit))
          color: Color.popups.text
          opacity: 0.72
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          visible: root.status !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.status
          color: "#ff8a80"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          visible: searchProc.running && root.videos.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("panel.loading")
          color: Color.popups.text
          opacity: 0.72
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !searchProc.running && root.status === "" && root.visibleVideos.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("panel.empty")
          color: Color.popups.text
          opacity: 0.72
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        ScrollView {
          id: videoScroll
          width: parent.width
          contentWidth: availableWidth
          height: Math.min(Style.space(420), Math.max(Style.space(100), videoList.implicitHeight))
          clip: true
          ScrollBar.vertical.policy: ScrollBar.AsNeeded

          Column {
            id: videoList
            width: videoScroll.availableWidth
            spacing: Style.space(6)

            Repeater {
              id: videoRows
              model: root.visibleVideos
              delegate: Rectangle {
                required property var modelData
                readonly property int thumbnailStatus: thumbnail.status
                width: videoList.width
                height: rowContent.implicitHeight + Style.space(12)
                radius: Math.min(4, Style.cornerRadius)
                color: Color.popups.background
                border.color: root.isRead(modelData.id) ? "#666666" : Commons.Color.accent
                border.width: 1

                RowLayout {
                  id: rowContent
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(10)

                  Rectangle {
                    Layout.preferredWidth: Style.space(128)
                    Layout.preferredHeight: Style.space(72)
                    Layout.alignment: Qt.AlignTop
                    color: Color.popups.border
                    radius: Math.min(4, Style.cornerRadius)
                    clip: true

                    Image {
                      id: thumbnail
                      anchors.fill: parent
                      source: root.popupOpen ? root.thumbnailUrl(modelData.id) : ""
                      sourceSize.width: 320
                      sourceSize.height: 180
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: true
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: thumbnail.status !== Image.Ready
                      textFormat: Text.PlainText
                      text: "▶"
                      color: Color.popups.text
                      font.pixelSize: Style.font.subtitle
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)

                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      text: modelData.title
                      color: Color.popups.text
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      text: (modelData.channel ? modelData.channel + " · " : "") + root.formattedDate(modelData.uploadDate)
                      color: Color.popups.text
                      opacity: 0.72
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(6)
                      Item { Layout.fillWidth: true }
                      Button {
                        iconText: ""
                        tooltipText: strings.t("video.open")
                        onClicked: root.watchVideo(modelData.id)
                      }
                      Button {
                        iconText: ""
                        tooltipText: root.downloadingId === modelData.id
                          ? strings.t("video.downloading") : strings.t("video.download")
                        enabled: !root.downloadingId
                        onClicked: root.downloadVideo(modelData.id)
                      }
                      Button {
                        iconText: root.isRead(modelData.id) ? "" : ""
                        tooltipText: root.isRead(modelData.id) ? strings.t("read.unread") : strings.t("read.mark")
                        enabled: root.readStateLoaded && !readStateProc.running
                        onClicked: root.markVideos([modelData.id], !root.isRead(modelData.id))
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          visible: root.downloadStatus !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.downloadStatus
          color: root.downloadStatus === strings.t("video.downloaded")
            ? Commons.Color.accent : "#ff8a80"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }
    }
  }
}

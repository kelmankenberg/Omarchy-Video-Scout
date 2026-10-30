import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kel.omarchy-video-scout"

  property bool popupOpen: false
  property string dateRange: "week"
  property string status: ""
  property string downloadingId: ""
  property var videos: []

  readonly property string home: Quickshell.env("HOME")
  readonly property string downloadPath: home + "/Videos/Omarchy Video Scout"
  readonly property var visibleVideos: videos

  function helperPath() {
    var path = Qt.resolvedUrl("bin/search-videos.py").toString()
    if (path.indexOf("file://") === 0) path = path.substring(7)
    try { path = decodeURIComponent(path) } catch (e) {}
    return path
  }

  function fetchVideos() {
    if (searchProc.running) return
    status = ""
    videos = []
    searchProc.command = ["python3", root.helperPath(), root.dateRange]
    searchProc.running = true
  }

  function selectRange(value) {
    if (["day", "week", "month", "all"].indexOf(value) < 0) {
      console.warn("Video Scout: invalid date range")
      return
    }
    if (searchProc.running) return
    dateRange = value
    downloadStatus = ""
    fetchVideos()
  }

  function open() {
    popupOpen = true
    fetchVideos()
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
      for (var i = 0; i < rows.length && i < 50; i++) {
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
      Qt.callLater(function() { root.finishSearch(exitCode, String(searchOut.text || "")) })
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
    text: "▶"
    fontSize: Style.font.body
    tooltipText: strings.t("widget.tooltip")
    onPressed: root.toggle()
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(520), 640)
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, 660)

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(10)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)
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
          text: searchProc.running ? strings.t("panel.loading") : strings.t("panel.refresh")
          enabled: !searchProc.running
          onClicked: root.fetchVideos()
        }
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
            required property var modelData
            Layout.fillWidth: true
            text: modelData.label
            selected: root.dateRange === modelData.id
            enabled: !searchProc.running
            onClicked: root.selectRange(modelData.id)
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: strings.t("panel.searchingNote")
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
              border.color: Color.popups.border
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
                      text: strings.t("video.open")
                      onClicked: root.watchVideo(modelData.id)
                    }
                    Button {
                      text: root.downloadingId === modelData.id
                        ? strings.t("video.downloading") : strings.t("video.download")
                      enabled: !root.downloadingId
                      onClicked: root.downloadVideo(modelData.id)
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

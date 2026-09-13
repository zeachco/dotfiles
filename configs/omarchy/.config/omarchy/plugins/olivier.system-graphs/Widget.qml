import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "olivier.system-graphs"
    implicitWidth: vertical ? 76 : 387
    implicitHeight: vertical ? 139 : barSize
    property var sample: ({})
    property var histories: [[], [], [], [], []]
    readonly property color ink: Color.bar.text

    function metricDetails(index) {
        var s = sample
        if (s.cpu === undefined) return "Collecting system metrics…"
        var details = [
            "CPU usage: " + s.cpu.toFixed(1) + "%",
            "Memory: " + s.usedGiB.toFixed(1) + " / " + s.totalGiB.toFixed(1) + " GiB (" + s.memory.toFixed(1) + "%)",
            "Disk read: " + s.read.toFixed(2) + " MiB/s\nDisk write: " + s.write.toFixed(2) + " MiB/s\nGraph auto-scales",
            "CPU temperature: " + (s.temperature === null ? "unavailable" : s.temperature.toFixed(1) + " °C") + "\nHottest CPU sensor • graph 0–100 °C",
            "GPU load: " + (s.gpu === null ? "unavailable" : s.gpu + "% (busiest GPU)")
        ]
        return details[index] + "\n60 seconds of history\nClick to open btop"
    }

    function ingest(data) {
        sample = JSON.parse(data)
        var values = [sample.cpu, sample.memory, sample.read + sample.write, sample.temperature, sample.gpu]
        var next = []
        for (var i = 0; i < values.length; i++)
            next.push(histories[i].concat([values[i]]).slice(-30))
        histories = next
    }

    Process {
        id: collector
        command: ["python3", Qt.resolvedUrl("collect.py").toString().replace(/^file:\/\//, "")]
        running: true
        stdout: SplitParser { onRead: data => root.ingest(data) }
    }

    Grid {
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 5
        spacing: 6
        Repeater {
            model: ["CPU", "MEM", "I/O", "TEMP", "GPU"]
            delegate: Item {
                id: metric
                required property int index
                required property string modelData
                width: 71
                height: 23
                readonly property var history: root.histories[index]
                readonly property real scale: index === 2 ? Math.max(1, ...history) : 100
                readonly property var value: history.length ? history[history.length - 1] : null
                onHistoryChanged: graph.requestPaint()
                readonly property bool tooltipHovered: visible && metricMouse.containsMouse
                readonly property string tooltipText: root.metricDetails(index)
                onTooltipTextChanged: {
                    if (root.bar && root.bar.tooltipTarget === metric)
                        root.bar.tooltipText = tooltipText
                }
                Component.onDestruction: {
                    if (root.bar) root.bar.hideTooltip(metric)
                }

                MouseArea {
                    id: metricMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.bar) root.bar.showTooltip(metric, metric.tooltipText)
                    onExited: if (root.bar) root.bar.hideTooltip(metric)
                    onClicked: Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
                }

                Text {
                    anchors.top: parent.top
                    text: metric.modelData
                    color: root.ink
                    font.family: Style.font.family
                    font.pixelSize: 8
                }
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    text: metric.value === null ? "—" : metric.index === 2
                        ? metric.value.toFixed(1) + "M/s"
                        : Math.round(metric.value) + (metric.index === 3 ? "°" : "%")
                    color: root.ink
                    font.family: Style.font.family
                    font.pixelSize: 8
                }
                Canvas {
                    id: graph
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 12
                    property color ink: root.ink
                    onInkChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = ink
                        ctx.lineWidth = 1
                        ctx.globalAlpha = 0.2
                        ctx.beginPath(); ctx.moveTo(0, height - 1); ctx.lineTo(width, height - 1); ctx.stroke()
                        ctx.globalAlpha = 1
                        ctx.beginPath()
                        var started = false
                        for (var i = 0; i < metric.history.length; i++) {
                            if (metric.history[i] === null) { started = false; continue }
                            var x = (30 - metric.history.length + i) * (width - 1) / 29
                            var y = height - 1 - Math.max(0, Math.min(1, metric.history[i] / metric.scale)) * (height - 2)
                            if (!started) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                            started = true
                        }
                        ctx.stroke()
                    }
                }
            }
        }
    }
}

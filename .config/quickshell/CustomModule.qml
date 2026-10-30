import QtQuick
import Quickshell.Io

// A user-defined bar module, described by one entry of layout.json:
//   { "type": "custom", "kind": "text" | "script" | "clock",
//     "icon": "", "text": "...", "command": "sh command whose stdout is shown", "interval": 5,
//     "format": "HH:mm", "color": "accent" | "#rrggbb", "accent": true, "click": "sh command" }
GlassPill {
    id: pill
    property var cfg: ({})
    property var host: null
    property string output: ""
    property string now: ""

    readonly property color tone: {
        var c = cfg.color
        if (!c || c === "accent") return Theme.neonStrong
        if (c === "text") return Theme.textPrimary
        return c
    }

    accent: cfg.accent === true
    content: Row {
        spacing: 7
        Text {
            visible: (cfg.icon || "") !== ""
            text: cfg.icon || ""
            color: pill.tone
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: 700
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            text: cfg.kind === "script" ? pill.output : (cfg.kind === "clock" ? pill.now : (cfg.text || ""))
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: 700
            verticalAlignment: Text.AlignVCenter
        }
    }

    Process {
        id: runner
        command: ["sh", "-c", cfg.command || "true"]
        running: false
        stdout: StdioCollector { onStreamFinished: pill.output = this.text.trim() }
    }

    Process { id: clicker; running: false }

    Timer {
        interval: Math.max(1, cfg.interval || 5) * 1000
        repeat: true
        triggeredOnStart: true
        running: cfg.kind === "script" || cfg.kind === "clock"
        onTriggered: {
            if (cfg.kind === "script") { runner.running = false; runner.running = true }
            else pill.now = Qt.formatDateTime(new Date(), cfg.format || "HH:mm")
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: (cfg.click || "") !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { clicker.command = ["sh", "-c", cfg.click]; clicker.running = false; clicker.running = true }
    }
}

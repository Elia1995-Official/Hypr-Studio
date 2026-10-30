import QtQuick

// Standalone copy of shell.qml's GlassModule, for modules defined outside shell.qml (custom bar widgets).
Rectangle {
    id: module
    property bool accent: false
    property alias content: moduleContent.data

    implicitWidth: moduleContent.implicitWidth + 28
    implicitHeight: 28
    radius: Theme.radiusMedium
    color: accent ? Theme.alpha(Theme.neon, 0.16) : Theme.alpha(Theme.panel, 0.94)
    border.width: 1
    border.color: accent ? Theme.alpha(Theme.neonStrong, 0.72) : Theme.alpha(Theme.neonDark, 0.58)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.textPrimary, 0.035)
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Math.min(parent.width * 0.36, 44)
        height: 1
        color: Theme.alpha(accent ? Theme.neonStrong : Theme.neonSoft, accent ? 0.72 : 0.30)
    }

    Row {
        id: moduleContent
        anchors.centerIn: parent
        spacing: 7
    }
}

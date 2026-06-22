import QtQuick
import qs.Common

Item {
    property real pct: 0
    property bool available: true
    height: 8
    implicitHeight: 8

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceContainerHighest
    }

    Rectangle {
        height: parent.height
        width: available ? parent.width * Math.min(1.0, Math.max(0.0, pct / 100.0)) : 0
        radius: height / 2
        color: !available ? Theme.surfaceContainerHighest
            : pct >= 90 ? Theme.error
            : pct >= 70 ? Theme.warning
            : Theme.success
        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }
}

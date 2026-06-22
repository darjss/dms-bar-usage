import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

StyledRect {
    id: card

    property string iconName: ""
    property string labelText: ""
    property string valueText: "--"
    property color valueColor: Theme.surfaceText
    property real pct: 0
    property bool barAvailable: true
    property bool showBar: true
    property string footerText: ""
    property bool showFooter: false

    width: parent ? parent.width : 200
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh

    implicitHeight: contentCol.implicitHeight + Theme.spacingM * 2

    Column {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        Row {
            spacing: Theme.spacingXS
            width: parent.width

            DankIcon {
                name: card.iconName
                size: Theme.iconSize - 4
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: card.labelText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            text: card.valueText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: card.valueColor
            width: parent.width
        }

        UsageBar {
            width: parent.width
            pct: card.pct
            available: card.barAvailable
            visible: card.showBar
        }

        StyledText {
            text: card.footerText
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.surfaceVariantText
            visible: card.showFooter
        }
    }
}

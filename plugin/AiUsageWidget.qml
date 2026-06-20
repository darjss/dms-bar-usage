import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // --- settings (auto-persisted via pluginData) ---
    property int refreshSeconds: pluginData.refreshSeconds || 5
    property bool showCredits: pluginData.showCredits === false ? false : true

    // --- runtime state ---
    property bool codexAvailable: false
    property bool stale: false
    property string planType: ""
    property real primaryPct: 0
    property real secondaryPct: 0
    property int primaryResetAt: 0
    property int secondaryResetAt: 0
    property var creditsData: null

    property int refreshMs: refreshSeconds * 1000

    // --- helpers ---

    function formatDuration(seconds) {
        if (seconds <= 0) return "now"
        var days = Math.floor(seconds / 86400)
        var hours = Math.floor((seconds % 86400) / 3600)
        var mins = Math.floor((seconds % 3600) / 60)
        if (days > 0) return days + "d " + hours + "h"
        if (hours > 0) return hours + "h " + mins + "m"
        return mins + "m"
    }

    function resetInSec(resetAt) {
        var now = Math.floor(Date.now() / 1000)
        return Math.max(0, resetAt - now)
    }

    // --- data fetching ---

    function parseResponse(text) {
        if (!text || text.trim() === "") {
            codexAvailable = false
            return
        }
        try {
            var data = JSON.parse(text.trim())
            if (data.codex) applyData(data.codex)
            else codexAvailable = false
        } catch (e) {
            codexAvailable = false
        }
    }

    function applyData(c) {
        codexAvailable = c.available || false
        stale = c.stale || false
        planType = c.plan_type || ""
        primaryPct = c.primary ? c.primary.pct : 0
        secondaryPct = c.secondary ? c.secondary.pct : 0
        primaryResetAt = c.primary ? c.primary.reset_at : 0
        secondaryResetAt = c.secondary ? c.secondary.reset_at : 0
        creditsData = c.credits || null
    }

    function refresh() {
        if (!fetchProcess.running) fetchProcess.running = true
    }

    Process {
        id: fetchProcess
        command: ["dms-ai-usage"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseResponse(text)
        }
    }

    Timer {
        id: refreshTimer
        interval: root.refreshMs
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    // --- bar pills (icon only) ---

    horizontalBarPill: Component {
        Item {
            anchors.verticalCenter: parent.verticalCenter

            DankIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined,
                        root.barConfig ? root.barConfig.maximizeWidgetIcons : false,
                        root.barConfig ? root.barConfig.iconScale : 1)
                color: Theme.widgetIconColor
                anchors.centerIn: parent
            }
        }
    }

    verticalBarPill: Component {
        Item {
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined,
                        root.barConfig ? root.barConfig.maximizeWidgetIcons : false,
                        root.barConfig ? root.barConfig.iconScale : 1)
                color: Theme.widgetIconColor
                anchors.centerIn: parent
            }
        }
    }

    // --- click popout ---

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: root.codexAvailable ? "Codex Usage" : "Codex Usage"
            detailsText: {
                if (!root.codexAvailable) return "Unavailable"
                if (root.stale) return "Cached data \u2014 live fetch unavailable"
                if (root.planType) return root.planType
                return ""
            }
            showCloseButton: true

            Column {
                id: popoutColumn
                width: parent.width
                spacing: Theme.spacingM

                // --- Primary window card ---

                StyledRect {
                    width: parent.width
                    height: primaryColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: primaryColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "schedule"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "5h Window"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.codexAvailable ? Math.round(root.primaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            width: parent.width
                        }

                        StyledText {
                            text: root.codexAvailable ? "Resets in " + root.formatDuration(root.resetInSec(root.primaryResetAt)) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            visible: root.codexAvailable
                        }
                    }
                }

                // --- Weekly window card ---

                StyledRect {
                    width: parent.width
                    height: weeklyColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: weeklyColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "date_range"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Weekly Window"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.codexAvailable ? Math.round(root.secondaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            width: parent.width
                        }

                        StyledText {
                            text: root.codexAvailable ? "Resets in " + root.formatDuration(root.resetInSec(root.secondaryResetAt)) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            visible: root.codexAvailable
                        }
                    }
                }

                // --- Credits card ---

                StyledRect {
                    width: parent.width
                    height: creditsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showCredits && root.creditsData !== null

                    Column {
                        id: creditsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "payments"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Credits"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.creditsData ? "$" + root.creditsData.balance.toFixed(2) : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            width: parent.width
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 320
    popoutHeight: 420
}

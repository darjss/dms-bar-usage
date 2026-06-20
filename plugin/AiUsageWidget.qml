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
    property int warnPct: pluginData.warnPct || 80
    property int criticalPct: pluginData.criticalPct || 95
    property bool showWeekly: pluginData.showWeekly === false ? false : true
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

    function colorForPct(pct) {
        if (!codexAvailable) return Theme.widgetTextColor
        if (pct >= criticalPct) return Theme.tempDanger
        if (pct >= warnPct) return Theme.tempWarning
        return Theme.widgetTextColor
    }

    function iconColor() {
        if (!codexAvailable) return Theme.widgetIconColor
        var maxPct = Math.max(primaryPct, secondaryPct)
        if (maxPct >= criticalPct) return Theme.tempDanger
        if (maxPct >= warnPct) return Theme.tempWarning
        return Theme.widgetIconColor
    }

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

    function barText() {
        if (!codexAvailable) return "--"
        var p = Math.round(primaryPct) + "%"
        if (showWeekly) p += " \u00b7 " + Math.round(secondaryPct) + "%"
        return p
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

    // --- bar pills ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter

            DankIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined,
                        root.barConfig ? root.barConfig.maximizeWidgetIcons : false,
                        root.barConfig ? root.barConfig.iconScale : 1)
                color: root.iconColor()
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: root.minimumWidth ? Math.max(baselineMetrics.width, currentMetrics.width) : currentMetrics.width
                implicitHeight: barLabel.implicitHeight
                width: implicitWidth
                height: implicitHeight

                StyledTextMetrics {
                    id: baselineMetrics
                    text: root.showWeekly ? "100% \u00b7 100%" : "100%"
                    font.pixelSize: Theme.barTextSize(root.barThickness,
                        root.barConfig ? root.barConfig.fontScale : 1,
                        root.barConfig ? root.barConfig.maximizeWidgetText : false)
                }

                StyledTextMetrics {
                    id: currentMetrics
                    text: barLabel.text
                    font.pixelSize: baselineMetrics.font.pixelSize
                }

                StyledText {
                    id: barLabel
                    text: root.barText()
                    font.pixelSize: baselineMetrics.font.pixelSize
                    color: root.colorForPct(root.primaryPct)
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined,
                        root.barConfig ? root.barConfig.maximizeWidgetIcons : false,
                        root.barConfig ? root.barConfig.iconScale : 1)
                color: root.iconColor()
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.codexAvailable ? Math.round(root.primaryPct) + "%" : "--"
                font.pixelSize: Theme.fontSizeSmall
                color: root.colorForPct(root.primaryPct)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- click popout ---

    popoutContent: Component {
        Column {
            spacing: Theme.spacingS
            width: parent ? parent.width : 300

            StyledText {
                text: root.codexAvailable ? "Codex Usage (" + root.planType + ")" : "Codex Usage"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                visible: root.stale
                text: "\u26a0 Cached data \u2014 live fetch unavailable"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.tempWarning
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineVariant
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS
                StyledText {
                    text: "5h:"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    width: 60
                }
                StyledText {
                    text: root.codexAvailable ? Math.round(root.primaryPct) + "% used" : "--"
                    font.pixelSize: Theme.fontSizeMedium
                    color: root.colorForPct(root.primaryPct)
                }
            }

            StyledText {
                text: root.codexAvailable ? "resets in " + root.formatDuration(root.resetInSec(root.primaryResetAt)) : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                leftPadding: 60
                visible: root.codexAvailable
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS
                StyledText {
                    text: "Weekly:"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    width: 60
                }
                StyledText {
                    text: root.codexAvailable ? Math.round(root.secondaryPct) + "% used" : "--"
                    font.pixelSize: Theme.fontSizeMedium
                    color: root.colorForPct(root.secondaryPct)
                }
            }

            StyledText {
                text: root.codexAvailable ? "resets in " + root.formatDuration(root.resetInSec(root.secondaryResetAt)) : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                leftPadding: 60
                visible: root.codexAvailable
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.showCredits && root.creditsData !== null
                StyledText {
                    text: "Credits:"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    width: 60
                }
                StyledText {
                    text: root.creditsData ? "$" + root.creditsData.balance.toFixed(2) : "--"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
            }
        }
    }

    popoutWidth: 300
    popoutHeight: 240
}

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // --- settings (auto-persisted via pluginData) ---
    property int refreshSeconds: pluginData.refreshSeconds || 5
    property bool showCredits: pluginData.showCredits === false ? false : true
    property bool showCodex: pluginData.showCodex === false ? false : true
    property bool showClaude: pluginData.showClaude === false ? false : true

    // --- runtime state (codex) ---
    property bool codexAvailable: false
    property bool codexStale: false
    property string codexPlanType: ""
    property real codexPrimaryPct: 0
    property real codexSecondaryPct: 0
    property int codexPrimaryResetAt: 0
    property int codexSecondaryResetAt: 0
    property var codexCreditsData: null

    // --- runtime state (claude) ---
    property bool claudeAvailable: false
    property bool claudeStale: false
    property string claudePlanType: ""
    property string claudeRateLimitTier: ""
    property real claudePrimaryPct: 0
    property real claudeSecondaryPct: 0
    property int claudePrimaryResetAt: 0
    property int claudeSecondaryResetAt: 0
    property var claudeModelSpecific: null
    property var claudeExtraUsage: null

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

    function statusColor(pct) {
        if (pct >= 90) return Theme.error
        if (pct >= 70) return Theme.warning
        return Theme.success
    }

    function resetText(available, resetAt) {
        if (!available) return ""
        return "Resets in " + formatDuration(resetInSec(resetAt))
    }

    // --- data fetching ---

    function parseResponse(text) {
        if (!text || text.trim() === "") {
            codexAvailable = false
            claudeAvailable = false
            return
        }
        try {
            var data = JSON.parse(text.trim())
            if (data.codex) applyCodexData(data.codex)
            else codexAvailable = false
            if (data.claude) applyClaudeData(data.claude)
            else claudeAvailable = false
        } catch (e) {
            codexAvailable = false
            claudeAvailable = false
        }
    }

    function applyCodexData(c) {
        codexAvailable = c.available || false
        codexStale = c.stale || false
        codexPlanType = c.plan_type || ""
        codexPrimaryPct = c.primary ? c.primary.pct : 0
        codexSecondaryPct = c.secondary ? c.secondary.pct : 0
        codexPrimaryResetAt = c.primary ? c.primary.reset_at : 0
        codexSecondaryResetAt = c.secondary ? c.secondary.reset_at : 0
        codexCreditsData = c.credits || null
    }

    function applyClaudeData(c) {
        claudeAvailable = c.available || false
        claudeStale = c.stale || false
        claudePlanType = c.plan_type || ""
        claudeRateLimitTier = c.rate_limit_tier || ""
        claudePrimaryPct = c.primary ? c.primary.pct : 0
        claudeSecondaryPct = c.secondary ? c.secondary.pct : 0
        claudePrimaryResetAt = c.primary ? c.primary.reset_at : 0
        claudeSecondaryResetAt = c.secondary ? c.secondary.reset_at : 0
        claudeModelSpecific = c.model_specific || null
        claudeExtraUsage = c.extra_usage || null
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

    // --- reusable usage bar: track + status-colored fill ---

    component UsageBar : Item {
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

            headerText: "AI Usage"
            detailsText: {
                if (!root.codexAvailable && !root.claudeAvailable) return "Unavailable"
                if (root.codexStale || root.claudeStale) return "Cached data \u2014 live fetch unavailable"
                var bits = []
                if (root.codexAvailable && root.codexPlanType) bits.push("Codex " + root.codexPlanType)
                if (root.claudeAvailable && root.claudePlanType) bits.push("Claude " + root.claudePlanType)
                return bits.join(" \u2022 ")
            }
            showCloseButton: true

            Column {
                id: popoutColumn
                width: parent.width
                spacing: Theme.spacingM

                // ===== Codex section =====

                StyledText {
                    width: parent.width
                    text: "CODEX"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                    font.letterSpacing: 1.5
                    visible: root.showCodex
                }

                // Codex 5h window
                StyledRect {
                    width: parent.width
                    height: codexPrimaryCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showCodex

                    Column {
                        id: codexPrimaryCol
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
                            text: root.codexAvailable ? Math.round(root.codexPrimaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.codexAvailable ? root.statusColor(root.codexPrimaryPct) : Theme.surfaceVariantText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.codexPrimaryPct
                            available: root.codexAvailable
                        }

                        StyledText {
                            text: root.resetText(root.codexAvailable, root.codexPrimaryResetAt)
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            visible: root.codexAvailable
                        }
                    }
                }

                // Codex weekly window
                StyledRect {
                    width: parent.width
                    height: codexWeeklyCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showCodex

                    Column {
                        id: codexWeeklyCol
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
                            text: root.codexAvailable ? Math.round(root.codexSecondaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.codexAvailable ? root.statusColor(root.codexSecondaryPct) : Theme.surfaceVariantText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.codexSecondaryPct
                            available: root.codexAvailable
                        }

                        StyledText {
                            text: root.resetText(root.codexAvailable, root.codexSecondaryResetAt)
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            visible: root.codexAvailable
                        }
                    }
                }

                // Codex credits
                StyledRect {
                    width: parent.width
                    height: codexCreditsCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showCodex && root.showCredits && root.codexCreditsData !== null

                    Column {
                        id: codexCreditsCol
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
                            text: root.codexCreditsData ? "$" + root.codexCreditsData.balance.toFixed(2) : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            width: parent.width
                        }
                    }
                }

                // ===== Claude Code section =====

                StyledText {
                    width: parent.width
                    text: "CLAUDE CODE"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                    font.letterSpacing: 1.5
                    visible: root.showClaude
                }

                // Claude 5h session
                StyledRect {
                    width: parent.width
                    height: claudePrimaryCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showClaude

                    Column {
                        id: claudePrimaryCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "bolt"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "5h Session"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.claudeAvailable ? Math.round(root.claudePrimaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.claudeAvailable ? root.statusColor(root.claudePrimaryPct) : Theme.surfaceVariantText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.claudePrimaryPct
                            available: root.claudeAvailable
                        }

                        StyledText {
                            text: root.resetText(root.claudeAvailable, root.claudePrimaryResetAt)
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            visible: root.claudeAvailable
                        }
                    }
                }

                // Claude weekly (all models)
                StyledRect {
                    width: parent.width
                    height: claudeWeeklyCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showClaude

                    Column {
                        id: claudeWeeklyCol
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
                                text: "Weekly (all models)"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.claudeAvailable ? Math.round(root.claudeSecondaryPct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.claudeAvailable ? root.statusColor(root.claudeSecondaryPct) : Theme.surfaceVariantText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.claudeSecondaryPct
                            available: root.claudeAvailable
                        }

                        StyledText {
                            text: root.resetText(root.claudeAvailable, root.claudeSecondaryResetAt)
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            visible: root.claudeAvailable
                        }
                    }
                }

                // Claude model-specific weekly (Sonnet/Opus)
                StyledRect {
                    width: parent.width
                    height: claudeModelCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showClaude && root.claudeModelSpecific !== null

                    Column {
                        id: claudeModelCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "memory"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.claudeModelSpecific ? "Weekly (" + root.claudeModelSpecific.label + ")" : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.claudeModelSpecific ? Math.round(root.claudeModelSpecific.pct) + "% used" : "--"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.claudeModelSpecific ? root.statusColor(root.claudeModelSpecific.pct) : Theme.surfaceVariantText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.claudeModelSpecific ? root.claudeModelSpecific.pct : 0
                            available: root.claudeModelSpecific !== null
                        }

                        StyledText {
                            text: root.claudeModelSpecific ? root.resetText(true, root.claudeModelSpecific.reset_at) : ""
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            visible: root.claudeModelSpecific
                        }
                    }
                }

                // Claude extra usage / credits
                StyledRect {
                    width: parent.width
                    height: claudeExtraCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.showClaude && root.claudeExtraUsage !== null

                    Column {
                        id: claudeExtraCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS
                            width: parent.width

                            DankIcon {
                                name: "add_circle"
                                size: Theme.iconSize - 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Extra Usage"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: {
                                if (!root.claudeExtraUsage) return "--"
                                if (root.claudeExtraUsage.is_enabled) {
                                    return "$" + root.claudeExtraUsage.used_credits.toFixed(2) + " / $" + root.claudeExtraUsage.monthly_limit.toFixed(2)
                                }
                                return root.claudeExtraUsage.disabled_reason ? root.claudeExtraUsage.disabled_reason : "disabled"
                            }
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            width: parent.width
                        }

                        UsageBar {
                            width: parent.width
                            pct: root.claudeExtraUsage ? root.claudeExtraUsage.utilization : 0
                            available: root.claudeExtraUsage ? root.claudeExtraUsage.is_enabled : false
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 340
    popoutHeight: 640
}

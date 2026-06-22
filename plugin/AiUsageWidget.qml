import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property int refreshSeconds: pluginData.refreshSeconds || 5
    property bool showCredits: pluginData.showCredits === false ? false : true
    property bool showCodex: pluginData.showCodex === false ? false : true
    property bool showClaude: pluginData.showClaude === false ? false : true

    property bool codexAvailable: false
    property bool codexStale: false
    property string codexPlanType: ""
    property real codexPrimaryPct: 0
    property real codexSecondaryPct: 0
    property int codexPrimaryResetAt: 0
    property int codexSecondaryResetAt: 0
    property var codexCreditsData: null

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
        return Math.max(0, resetAt - Math.floor(Date.now() / 1000))
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

    component SectionHeader : StyledText {
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
        font.letterSpacing: 1.5
        width: parent.width
    }

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

            Row {
                id: columns
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    id: codexCol
                    width: (parent.width - parent.spacing) / 2
                    spacing: Theme.spacingS
                    visible: root.showCodex

                    SectionHeader { text: "CODEX" }

                    UsageCard {
                        width: parent.width
                        iconName: "schedule"
                        labelText: "5h Window"
                        valueText: root.codexAvailable ? Math.round(root.codexPrimaryPct) + "% used" : "--"
                        valueColor: root.codexAvailable ? root.statusColor(root.codexPrimaryPct) : Theme.surfaceVariantText
                        pct: root.codexPrimaryPct
                        barAvailable: root.codexAvailable
                        footerText: root.resetText(root.codexAvailable, root.codexPrimaryResetAt)
                        showFooter: root.codexAvailable
                    }

                    UsageCard {
                        width: parent.width
                        iconName: "date_range"
                        labelText: "Weekly"
                        valueText: root.codexAvailable ? Math.round(root.codexSecondaryPct) + "% used" : "--"
                        valueColor: root.codexAvailable ? root.statusColor(root.codexSecondaryPct) : Theme.surfaceVariantText
                        pct: root.codexSecondaryPct
                        barAvailable: root.codexAvailable
                        footerText: root.resetText(root.codexAvailable, root.codexSecondaryResetAt)
                        showFooter: root.codexAvailable
                    }

                    UsageCard {
                        width: parent.width
                        visible: root.showCredits && root.codexCreditsData !== null
                        iconName: "payments"
                        labelText: "Credits"
                        valueText: root.codexCreditsData ? "$" + root.codexCreditsData.balance.toFixed(2) : "--"
                        showBar: false
                    }
                }

                Column {
                    id: claudeCol
                    width: (parent.width - parent.spacing) / 2
                    spacing: Theme.spacingS
                    visible: root.showClaude

                    SectionHeader { text: "CLAUDE" }

                    UsageCard {
                        width: parent.width
                        iconName: "bolt"
                        labelText: "5h Session"
                        valueText: root.claudeAvailable ? Math.round(root.claudePrimaryPct) + "% used" : "--"
                        valueColor: root.claudeAvailable ? root.statusColor(root.claudePrimaryPct) : Theme.surfaceVariantText
                        pct: root.claudePrimaryPct
                        barAvailable: root.claudeAvailable
                        footerText: root.resetText(root.claudeAvailable, root.claudePrimaryResetAt)
                        showFooter: root.claudeAvailable
                    }

                    UsageCard {
                        width: parent.width
                        iconName: "date_range"
                        labelText: "Weekly"
                        valueText: root.claudeAvailable ? Math.round(root.claudeSecondaryPct) + "% used" : "--"
                        valueColor: root.claudeAvailable ? root.statusColor(root.claudeSecondaryPct) : Theme.surfaceVariantText
                        pct: root.claudeSecondaryPct
                        barAvailable: root.claudeAvailable
                        footerText: root.resetText(root.claudeAvailable, root.claudeSecondaryResetAt)
                        showFooter: root.claudeAvailable
                    }

                    UsageCard {
                        width: parent.width
                        visible: root.claudeModelSpecific !== null
                        iconName: "memory"
                        labelText: root.claudeModelSpecific ? "Weekly (" + root.claudeModelSpecific.label + ")" : ""
                        valueText: root.claudeModelSpecific ? Math.round(root.claudeModelSpecific.pct) + "% used" : "--"
                        valueColor: root.claudeModelSpecific ? root.statusColor(root.claudeModelSpecific.pct) : Theme.surfaceVariantText
                        pct: root.claudeModelSpecific ? root.claudeModelSpecific.pct : 0
                        barAvailable: root.claudeModelSpecific !== null
                        footerText: root.claudeModelSpecific ? root.resetText(true, root.claudeModelSpecific.reset_at) : ""
                        showFooter: root.claudeModelSpecific !== null
                    }

                    UsageCard {
                        width: parent.width
                        visible: root.claudeExtraUsage !== null
                        iconName: "add_circle"
                        labelText: "Extra Usage"
                        valueText: {
                            if (!root.claudeExtraUsage) return "--"
                            if (root.claudeExtraUsage.is_enabled) {
                                return "$" + root.claudeExtraUsage.used_credits.toFixed(2) + " / $" + root.claudeExtraUsage.monthly_limit.toFixed(2)
                            }
                            return root.claudeExtraUsage.disabled_reason ? root.claudeExtraUsage.disabled_reason : "disabled"
                        }
                        pct: root.claudeExtraUsage ? root.claudeExtraUsage.utilization : 0
                        barAvailable: root.claudeExtraUsage ? root.claudeExtraUsage.is_enabled : false
                    }
                }
            }
        }
    }

    popoutWidth: 520
    popoutHeight: 400
}

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiUsage"

    StyledText {
        width: parent.width
        text: "AI Usage Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitors Codex usage limits in the DankBar"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshSeconds"
        label: "Refresh interval"
        description: "How often to poll for usage data"
        minimum: 2
        maximum: 60
        defaultValue: 5
        unit: "s"
    }

    SliderSetting {
        settingKey: "warnPct"
        label: "Warn at"
        description: "Percentage that triggers amber color"
        minimum: 50
        maximum: 100
        defaultValue: 80
        unit: "%"
    }

    SliderSetting {
        settingKey: "criticalPct"
        label: "Critical at"
        description: "Percentage that triggers red color"
        minimum: 50
        maximum: 100
        defaultValue: 95
        unit: "%"
    }

    ToggleSetting {
        settingKey: "showWeekly"
        label: "Show weekly %"
        description: "Display the 7-day window percentage alongside the 5h percentage"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showCredits"
        label: "Show credits in popout"
        description: "Display credit balance in the click popout"
        defaultValue: true
    }
}

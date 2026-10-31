import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// First editing milestone: functional trim/export. Crop and rotation
// will be added in the second PR, not shown as working actions here.
Rectangle {
    id: root
    width: 288
    color: tokens.panelGlass || "#20202B"
    border.color: tokens.panelBorder || "#444"
    border.width: 1

    property var tokens: themeController.tokens
    onVisibleChanged: {
        if (!visible)
            exportModePopup.close();
    }
    property string sourceTitle: ""
    property string sourcePath: ""
    readonly property bool canReplace: sourcePath.toLowerCase().endsWith(".mp4")
    property real startTime: 0
    property real endTime: 0
    property real duration: 0
    property real editSpeed: 1.0
    property int audioVolumePercent: 100
    readonly property var presetIds: ["ultrafast", "veryfast", "fast", "medium", "slow"]
    function presetLabel(id) {
        const names = ["Ultrafast", "Very Fast", "Fast", "Medium", "Slow"];
        return names[Math.max(0, presetIds.indexOf(id))];
    }
    function gifLabel(id) {
        return id === "high" ? "High Quality (640px · 12fps)" :
               id === "compact" ? "Compact (360px · 8fps)" :
                                  "Balanced (480px · 10fps)";
    }

    signal closeRequested()
    signal exportRequested()
    signal exportGifRequested()
     signal previewRequested()
    signal resetRequested()
    signal queueRequested()

    function mp4ModeLabel() {
        switch (settingsStore.mp4ExportMode) {
        case "saveAs": return "Save As dialog";
        case "replace": return "Replace original";
        default: return "Quick copy";
        }
    }
    function gifModeLabel() {
        return settingsStore.gifExportMode === "saveAs" ? "Save As dialog" : "Quick GIF";
    }

    component ModeChoice: Button {
        id: choice
        property string detail: ""
        property bool selected: false
        Layout.fillWidth: true
        Layout.preferredHeight: 43
        padding: 7
        font.pixelSize: 11
        background: Rectangle {
            radius: 7
            color: choice.selected ? (root.tokens.accentTint || "#183424")
                                   : (choice.hovered ? (root.tokens.panelGlass || "#181D19") : "transparent")
            border.width: choice.selected ? 1 : 0
            border.color: root.tokens.accentSolid || "#2BFA83"
        }
        contentItem: RowLayout {
            spacing: 9
            Rectangle {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                radius: 6
                color: choice.selected ? (root.tokens.accentSolid || "#2BFA83") : "transparent"
                border.width: 1
                border.color: choice.selected
                    ? (root.tokens.accentSolid || "#2BFA83")
                    : (root.tokens.textMuted || "#777")
                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: root.tokens.videoCardBackground || "#08130B"
                    visible: choice.selected
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: choice.text
                    color: root.tokens.textPrimary || "white"
                    font.pixelSize: 11
                    font.bold: choice.selected
                }
                Text {
                    Layout.fillWidth: true
                    text: choice.detail
                    color: root.tokens.textSecondary || "#AAA"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }

    function showExportModePopup() {
        const overlay = exportModePopup.parent;
        const pt = settingsButton.mapToItem(overlay, 0, 0);
        exportModePopup.x = Math.max(8, Math.min(pt.x + settingsButton.width - exportModePopup.width,
                                               prismWindow.width - exportModePopup.width - 8));
        exportModePopup.y = Math.max(8, Math.min(pt.y + settingsButton.height + 6,
                                               prismWindow.height - exportModePopup.height - 8));
        exportModePopup.open();
    }

    function timeText(seconds) {
        let s = Math.max(0, Math.floor(seconds || 0));
        let h = Math.floor(s / 3600);
        let m = Math.floor((s % 3600) / 60);
        let sec = s % 60;
        const pad = n => String(n).padStart(2, "0");
        const base = h ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
        return seconds >= 0 && seconds < 10
            ? base + "." + pad(Math.floor((seconds - Math.floor(seconds)) * 100 + 0.001))
            : base;
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: parent.width
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 20
                Text {
                    Layout.fillWidth: true
                    text: "EDIT VIDEO"
                    color: root.tokens.textPrimary || "white"
                    font.pixelSize: 13
                    font.bold: true
                }
                Button {
                    text: "✕"
                    enabled: exportQueue.canQueue
                    flat: true
                    onClicked: root.closeRequested()
                    ToolTip.visible: hovered
                    ToolTip.text: "Return to player"
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: root.sourceTitle
                elide: Text.ElideMiddle
                color: root.tokens.textSecondary || "#aaa"
                font.pixelSize: 11
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 102
                radius: 10
                color: root.tokens.accentTint || "#223344"
                border.color: root.tokens.accentSolid || "#A89BFF"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 7
                    Text {
                        text: "✂   Trim"
                        color: root.tokens.textPrimary || "white"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Choose your IN and OUT points on the timeline below."
                        color: root.tokens.textSecondary || "#ddd"
                        font.pixelSize: 11
                    }
                    Text {
                        text: root.timeText(root.endTime - root.startTime) + " selected"
                        color: root.tokens.accentSolid || "#A89BFF"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 43
                radius: 9
                color: root.tokens.panelGlassStrong || "#242331"
                border.color: root.tokens.panelBorder || "#444"
                Text {
                    anchors.centerIn: parent
                    text: "Crop  ·  Available in next PR"
                    color: root.tokens.textMuted || "#777"
                    font.pixelSize: 11
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 43
                radius: 9
                color: root.tokens.panelGlassStrong || "#242331"
                border.color: root.tokens.panelBorder || "#444"
                Text {
                    anchors.centerIn: parent
                    text: "Rotate  ·  Available in next PR"
                    color: root.tokens.textMuted || "#777"
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 1
                color: root.tokens.panelBorder || "#444"
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "EXPORT SUMMARY"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                color: root.tokens.textSecondary || "#aaa"
                font.pixelSize: 11
                text: "Output: MP4 (H.264 + AAC)\n"
                    + "Edited duration: " + root.timeText((root.endTime - root.startTime)
                        / Math.max(0.25, root.editSpeed)) + "\n"
                    + "MP4 audio: " + (root.audioVolumePercent === 0 ? "Removed" :
                       root.audioVolumePercent === 100 ? "Original level" :
                       root.audioVolumePercent + "% of original") + "\n"
                    + "GIF: " + root.gifLabel(settingsStore.gifQualityPreset)
                    + "\nSubtitles not included"
                lineHeight: 1.45
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "ENCODING PRESET"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }
            Button {
                id: presetButton
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: exportQueue.canQueue
                text: root.presetLabel(settingsStore.encodingPreset) + " ▾"
                onClicked: presetMenu.open()
                background: Rectangle {
                    color: root.tokens.panelGlassStrong || "#242331"
                    radius: 8
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Menu {
                    id: presetMenu
                    parent: presetButton
                    y: presetButton.height
                    Repeater {
                        model: root.presetIds
                        MenuItem {
                            text: root.presetLabel(modelData)
                            checkable: true
                            checked: settingsStore.encodingPreset === modelData
                            onTriggered: settingsStore.encodingPreset = modelData
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Very Fast is recommended. Slower presets may produce smaller files."
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "GIF QUALITY"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }
            Button {
                id: gifPresetButton
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: exportQueue.canQueue
                text: root.gifLabel(settingsStore.gifQualityPreset) + " ▾"
                onClicked: gifPresetMenu.open()
                background: Rectangle {
                    radius: 8
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Menu {
                    id: gifPresetMenu
                    parent: gifPresetButton
                    y: gifPresetButton.height
                    Repeater {
                        model: ["high", "balanced", "compact"]
                        MenuItem {
                            text: root.gifLabel(modelData)
                            checkable: true
                            checked: settingsStore.gifQualityPreset === modelData
                            onTriggered: settingsStore.gifQualityPreset = modelData
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "Balanced is recommended. GIFs have no sound and can be much larger than MP4."
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: "QUICK EXPORT"
                font.pixelSize: 10
                font.bold: true
                color: root.tokens.textMuted || "#999"
            }

            Rectangle {
                id: minimalDock
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 48
                color: root.tokens.panelGlassStrong || "#111A13"
                border.color: root.tokens.panelBorder || "#375443"
                border.width: 1
                radius: 10

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 5
                    spacing: 5

                    Button {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: root.endTime - root.startTime >= 0.1 &&
                            (settingsStore.mp4ExportMode === "replace"
                                ? (root.canReplace && !exportQueue.hasOutstanding &&
                                   !videoExportController.busy) : exportQueue.canQueue)
                        text: "MP4"
                        onClicked: root.exportRequested()
                        font.bold: true
                        font.pixelSize: 12
                        background: Rectangle {
                            radius: 7
                            color: parent.enabled ? (root.tokens.accentSolid || "#2BFA83")
                                                   : (root.tokens.panelBorder || "#444")
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.tokens.videoCardBackground || "#092111"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "MP4: " + root.mp4ModeLabel()
                    }

                    Button {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: exportQueue.canQueue && root.endTime - root.startTime >= 0.1
                        text: "GIF"
                        onClicked: root.exportGifRequested()
                        font.bold: true
                        font.pixelSize: 12
                        background: Rectangle {
                            radius: 7
                            color: root.tokens.accentTint || "#132319"
                            border.color: root.tokens.accentSolid || "#2BFA83"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.tokens.textPrimary || "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "GIF: " + root.gifModeLabel()
                    }

                    Button {
                        id: settingsButton
                        Layout.preferredWidth: 36
                        Layout.fillHeight: true
                        text: "⚙"
                        onClicked: root.showExportModePopup()
                        font.pixelSize: 17
                        background: Rectangle {
                            radius: 7
                            color: root.tokens.accentTint || "#14231A"
                            border.color: root.tokens.panelBorder || "#375443"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: root.tokens.textPrimary || "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Configure MP4 and GIF export actions"
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: 55
                radius: 8
                color: root.tokens.panelGlassStrong || "#0B150E"
                border.color: root.tokens.panelBorder || "#25412F"

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Text {
                        text: "●  MP4   " + root.mp4ModeLabel()
                        color: root.tokens.textSecondary || "#9DBBAC"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: "●  GIF      " + root.gifModeLabel()
                        color: root.tokens.textSecondary || "#9DBBAC"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                visible: settingsStore.mp4ExportMode === "replace"
                text: !root.canReplace
                    ? "Replace original is available only for MP4 source files."
                    : exportQueue.hasOutstanding
                        ? "Replacement is available after the export queue finishes."
                        : (settingsStore.keepBackupOnReplace
                            ? "Backup ON. Original is preserved on replacement."
                            : "Backup OFF. Replacing the original cannot be undone.")
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            ExportQueuePanel {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: Math.min(310, Math.max(130,
                    65 + Math.min(exportQueue.jobs.length, 3) * 80))
                visible: exportQueue.jobs.length > 0
                compact: true
            }
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                text: "View export queue"
                onClicked: root.queueRequested()
                font.pixelSize: 11
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.accentSolid || "#A89BFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 7
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.color: root.tokens.panelBorder || "#444"
                }
            }

            Item { Layout.preferredHeight: 15 }
        }
    }
    Popup {
        id: exportModePopup
        parent: Overlay.overlay
        width: 318
        height: 370
        padding: 12
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 11
            color: root.tokens.panelGlassStrong || "#111A13"
            border.color: root.tokens.accentSolid || "#2BFA83"
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "⚙  Export behavior"
                    color: root.tokens.textPrimary || "white"
                    font.pixelSize: 12
                    font.bold: true
                }
                Button {
                    text: "✕"
                    flat: true
                    onClicked: exportModePopup.close()
                    contentItem: Text {
                        text: parent.text
                        color: root.tokens.textSecondary || "#AAA"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            Text {
                text: "WHEN YOU CLICK MP4"
                font.pixelSize: 9
                font.bold: true
                color: root.tokens.textMuted || "#888"
            }
            ModeChoice {
                text: "Export a copy automatically"
                detail: "Queue a uniquely named MP4 beside the source"
                selected: settingsStore.mp4ExportMode === "auto"
                onClicked: settingsStore.mp4ExportMode = "auto"
            }
            ModeChoice {
                text: "Choose name and folder"
                detail: "Open Windows Save As, then add to queue"
                selected: settingsStore.mp4ExportMode === "saveAs"
                onClicked: settingsStore.mp4ExportMode = "saveAs"
            }
            ModeChoice {
                text: "Replace original MP4"
                detail: "Confirm before replacing; queue must be empty"
                selected: settingsStore.mp4ExportMode === "replace"
                enabled: root.canReplace
                onClicked: settingsStore.mp4ExportMode = "replace"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.tokens.panelBorder || "#444"
            }
            Text {
                text: "WHEN YOU CLICK GIF"
                font.pixelSize: 9
                font.bold: true
                color: root.tokens.textMuted || "#888"
            }
            ModeChoice {
                text: "Export GIF automatically"
                detail: "Queue a uniquely named GIF beside the source"
                selected: settingsStore.gifExportMode === "auto"
                onClicked: settingsStore.gifExportMode = "auto"
            }
            ModeChoice {
                text: "Choose name and folder"
                detail: "Open Windows Save As, then add to queue"
                selected: settingsStore.gifExportMode === "saveAs"
                onClicked: settingsStore.gifExportMode = "saveAs"
            }
            Text {
                Layout.fillWidth: true
                text: "Backup preference remains in Tools → Settings."
                wrapMode: Text.WordWrap
                font.pixelSize: 9
                color: root.tokens.textMuted || "#888"
            }
        }
    }

}

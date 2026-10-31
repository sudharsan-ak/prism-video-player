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
    property string sourceTitle: ""
    property string sourcePath: ""
    readonly property bool canReplace: sourcePath.toLowerCase().endsWith(".mp4")
    property real startTime: 0
    property real endTime: 0
    property real duration: 0
    property real editSpeed: 1.0
    property bool muteAudio: false
    readonly property var presetIds: ["ultrafast", "veryfast", "fast", "medium", "slow"]
    function presetLabel(id) {
        const names = ["Ultrafast", "Very Fast", "Fast", "Medium", "Slow"];
        return names[Math.max(0, presetIds.indexOf(id))];
    }

    signal closeRequested()
    signal exportRequested()
    signal exportGifRequested()
    signal replaceRequested()
    signal previewRequested()
    signal resetRequested()

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
                    enabled: !videoExportController.busy
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
                    + "MP4 audio: " + (root.muteAudio ? "Removed" : "First audio track") + "\n"
                    + "GIF: Silent, 12 fps, up to 640px wide\nSubtitles not included"
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
                enabled: !videoExportController.busy
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

            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: !videoExportController.busy && root.endTime - root.startTime >= 0.1
                text: "Export edited copy..."
                onClicked: root.exportRequested()
                font.pixelSize: 12
                font.bold: true
                contentItem: Text {
                    text: parent.text
                    color: root.tokens.videoCardBackground || "#121212"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: parent.font
                }
                background: Rectangle {
                    radius: 9
                    color: parent.enabled ? (root.tokens.accentSolid || "#A89BFF")
                                          : (root.tokens.panelBorder || "#444")
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: !videoExportController.busy && root.endTime - root.startTime >= 0.1
                text: "Export animated GIF..."
                onClicked: root.exportGifRequested()
                font.pixelSize: 12
                background: Rectangle {
                    radius: 9
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.width: 1
                    border.color: root.tokens.accentSolid || "#A89BFF"
                }
                contentItem: Text {
                    text: parent.text
                    color: root.tokens.textPrimary || "#fff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: parent.font
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                enabled: root.canReplace && !videoExportController.busy &&
                         root.endTime - root.startTime >= 0.1
                text: "Replace original MP4..."
                onClicked: root.replaceRequested()
                font.pixelSize: 12
                background: Rectangle {
                    radius: 9
                    color: "transparent"
                    border.width: 1
                    border.color: root.tokens.accentSolid || "#A89BFF"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "#fff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: root.canReplace
                    ? (settingsStore.keepBackupOnReplace
                        ? "Backup enabled. A timestamped original will be kept."
                        : "Backup OFF. Change this in Tools → Settings.")
                    : "Replacing the original is supported only for MP4 sources."
                color: root.tokens.textMuted || "#888"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                visible: videoExportController.busy
                    || videoExportController.error.length > 0
                    || videoExportController.lastOutput.toString().length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 9

                Text {
                    Layout.fillWidth: true
                    text: videoExportController.error.length
                        ? videoExportController.error : videoExportController.status
                    color: videoExportController.error.length ? "#E36B6B" : (root.tokens.textPrimary || "white")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
                ProgressBar {
                    id: exportProgress
                    visible: videoExportController.busy
                    Layout.fillWidth: true
                    value: videoExportController.progress
                    from: 0
                    to: 1
                    background: Rectangle {
                        implicitHeight: 6
                        radius: 3
                        color: root.tokens.seekTrack || "#4A4A60"
                    }
                    contentItem: Item {
                        implicitHeight: 6
                        Rectangle {
                            width: parent.width * exportProgress.position
                            height: 6
                            radius: 3
                            color: root.tokens.accentSolid || "#A89BFF"
                        }
                    }
                }
                Text {
                    visible: videoExportController.busy
                    text: Math.round(videoExportController.progress * 100) + "%"
                    color: root.tokens.textSecondary || "#aaa"
                    font.pixelSize: 11
                }
                Button {
                    visible: videoExportController.busy
                    text: "Cancel export"
                    onClicked: videoExportController.cancel()
                }
                Text {
                    visible: videoExportController.lastOutput.toString().length > 0
                    Layout.fillWidth: true
                    text: videoExportController.lastOutput.toString()
                    wrapMode: Text.WrapAnywhere
                    color: root.tokens.textSecondary || "#aaa"
                    font.pixelSize: 10
                }
            }

            Item { Layout.preferredHeight: 15 }
        }
    }
}

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
    property real startTime: 0
    property real endTime: 0
    property real duration: 0

    signal closeRequested()
    signal exportRequested()
    signal previewRequested()
    signal resetRequested()

    function timeText(seconds) {
        let s = Math.max(0, Math.floor(seconds || 0));
        let h = Math.floor(s / 3600);
        let m = Math.floor((s % 3600) / 60);
        let sec = s % 60;
        const pad = n => String(n).padStart(2, "0");
        return h ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
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
                text: "Output: MP4 (H.264 + AAC)\nOriginal untouched\nFirst audio track only\nSubtitles not included"
                lineHeight: 1.45
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

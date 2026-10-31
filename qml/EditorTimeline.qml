import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Trim selection is independent of the playback seek bar: only the
// range handles change the exported IN/OUT values. The red playhead
// shows current mpv position; export cuts at the exact chosen times.
Rectangle {
    id: root
    height: 175
    color: tokens.panelGlass || "#20202B"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property real duration: 0
    property real position: 0
    property real startTime: 0
    property real endTime: 0
    property real editSpeed: 1.0
    property bool previewPlaying: false
    property bool muteAudio: false

    signal startTimeEdited(real seconds)
    signal endTimeEdited(real seconds)
    signal seekRequested(real seconds)
    signal previewRequested()
    signal togglePlaybackRequested()
    signal speedEdited(real speed)
    signal audioMutedEdited(bool muted)
    signal resetRequested()
    signal exportRequested()

    function timeText(seconds) {
        let whole = Math.max(0, Math.floor(seconds || 0));
        const h = Math.floor(whole / 3600), m = Math.floor((whole % 3600) / 60);
        const s = whole % 60;
        const pad = n => String(n).padStart(2, "0");
        const base = h ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
        return root.duration < 10
            ? base + "." + pad(Math.floor((seconds - Math.floor(seconds)) * 100 + 0.001))
            : base;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "TRIM TIMELINE"
                color: root.tokens.textPrimary || "#fff"
                font.pixelSize: 11
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "IN  " + root.timeText(root.startTime)
                color: root.tokens.accentSolid || "#A89BFF"
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                text: "OUT  " + root.timeText(root.endTime)
                color: root.tokens.textPrimary || "#fff"
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                text: "SELECTED  " + root.timeText(root.endTime - root.startTime)
                color: root.tokens.textSecondary || "#aaa"
                font.pixelSize: 11
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54

            // Real thumbnail images are generated asynchronously by FFmpeg.
            Rectangle {
                id: frameTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                radius: 7
                color: root.tokens.videoCardBackground || "#111"
                border.color: root.tokens.panelBorder || "#555"
                clip: true

                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: videoThumbnailController.frames.length > 0
                            ? videoThumbnailController.frames : Array(16).fill("")
                        Item {
                            width: frameTrack.width / 16
                            height: frameTrack.height
                            clip: true
                            Rectangle {
                                anchors.fill: parent
                                color: index % 2 === 0 ? "#24242E" : "#343441"
                            }
                            Image {
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Rectangle {
                                anchors.right: parent.right
                                width: 1
                                height: parent.height
                                color: "#55000000"
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: videoThumbnailController.error.length > 0
                    width: parent.width - 18
                    text: videoThumbnailController.error
                    font.pixelSize: 10
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    style: Text.Outline
                    styleColor: "#111111"
                }

                Rectangle {
                    x: trimRange.first.visualPosition * parent.width
                    width: Math.max(0, (trimRange.second.visualPosition - trimRange.first.visualPosition) * parent.width)
                    height: parent.height
                    color: root.tokens.accentTint || "#334466"
                    border.color: root.tokens.accentSolid || "#A89BFF"
                    border.width: 2
                }
                Rectangle {
                    x: Math.max(0, Math.min(parent.width - 2,
                        parent.width * root.position / Math.max(root.duration, 1)))
                    height: parent.height
                    width: 2
                    color: "#F06B6B"
                    z: 3
                }
            }

            RangeSlider {
                id: trimRange
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                anchors.fill: parent
                from: 0
                to: Math.max(root.duration, 1)
                first.value: root.startTime
                second.value: root.endTime
                focusPolicy: Qt.NoFocus
                live: true
                first.onMoved: root.startTimeEdited(first.value)
                second.onMoved: root.endTimeEdited(second.value)
                first.onPressedChanged: {
                    if (!first.pressed)
                        root.seekRequested(root.startTime)
                }
                second.onPressedChanged: {
                    if (!second.pressed)
                        root.seekRequested(root.endTime)
                }
                background: Item {}
                first.handle: Rectangle {
                    HoverHandler { cursorShape: Qt.SizeHorCursor }
                    width: 14; height: 46; radius: 4
                    x: trimRange.leftPadding + trimRange.first.visualPosition * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    color: root.tokens.accentSolid || "#A89BFF"
                    border.width: 2
                    border.color: root.tokens.seekThumbEdge || "#fff"
                    Text {
                        anchors.centerIn: parent
                        text: "Ⅰ"
                        font.pixelSize: 12
                        color: root.tokens.videoCardBackground || "#111"
                    }
                }
                second.handle: Rectangle {
                    HoverHandler { cursorShape: Qt.SizeHorCursor }
                    width: 14; height: 46; radius: 4
                    x: trimRange.leftPadding + trimRange.second.visualPosition * (trimRange.availableWidth - width)
                    y: (trimRange.height - height) / 2
                    color: root.tokens.accentSolid || "#A89BFF"
                    border.width: 2
                    border.color: root.tokens.seekThumbEdge || "#fff"
                    Text {
                        anchors.centerIn: parent
                        text: "Ⅱ"
                        font.pixelSize: 12
                        color: root.tokens.videoCardBackground || "#111"
                    }
                }
            }
        }

        ThemedSeekBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            mediaPosition: root.position
            mediaDuration: root.duration
            onSeekRequested: function(seconds) { root.seekRequested(seconds); }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "0:00"
                font.pixelSize: 10
                color: root.tokens.textMuted || "#888"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Playhead: " + root.timeText(root.position)
                font.pixelSize: 10
                color: root.tokens.textSecondary || "#aaa"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.timeText(root.duration)
                font.pixelSize: 10
                color: root.tokens.textMuted || "#888"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            component TrimButton: Button {
                font.pixelSize: 11
                background: Rectangle {
                    radius: 7
                    color: parent.down
                        ? (root.tokens.accentTint || "#334")
                        : (root.tokens.panelGlassStrong || "#272735")
                    border.width: 1
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "#fff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            TrimButton {
                id: rangePlaybackButton
                text: root.previewPlaying ? "Pause" : "Play range"
                onClicked: root.togglePlaybackRequested()
                // The previous ❚❚ characters had font-dependent spacing.
                // Draw two aligned bars ourselves for a compact pause icon.
                contentItem: Item {
                    implicitWidth: playbackContents.implicitWidth
                    implicitHeight: playbackContents.implicitHeight
                    Row {
                        id: playbackContents
                        anchors.centerIn: parent
                        spacing: 6

                        Item {
                            width: 12
                            height: 14
                            y: (playbackContents.height - height) / 2

                            Text {
                                anchors.centerIn: parent
                                text: "▶"
                                font.pixelSize: 12
                                color: root.tokens.textPrimary || "#fff"
                                visible: !root.previewPlaying
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                visible: root.previewPlaying
                                Rectangle {
                                    width: 3
                                    height: 11
                                    radius: 1
                                    color: root.tokens.textPrimary || "#fff"
                                }
                                Rectangle {
                                    width: 3
                                    height: 11
                                    radius: 1
                                    color: root.tokens.textPrimary || "#fff"
                                }
                            }
                        }
                        Text {
                            text: rangePlaybackButton.text
                            font: rangePlaybackButton.font
                            color: root.tokens.textPrimary || "#fff"
                            y: (playbackContents.height - height) / 2
                        }
                    }
                }
            }
            TrimButton {
                id: speedButton
                text: root.editSpeed + "x ▾"
                onClicked: speedMenu.open()
                Menu {
                    id: speedMenu
                    parent: speedButton
                    y: speedButton.height
                    Repeater {
                        model: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                        MenuItem {
                            text: modelData + "x"
                            checkable: true
                            checked: root.editSpeed === modelData
                            onTriggered: root.speedEdited(modelData)
                        }
                    }
                }
            }
            TrimButton {
                text: root.muteAudio ? "🔇 Muted" : "🔊 Sound on"
                onClicked: root.audioMutedEdited(!root.muteAudio)
                ToolTip.visible: hovered
                ToolTip.text: root.muteAudio
                    ? "Enable preview sound and include audio in MP4 exports"
                    : "Mute preview and remove audio from exported MP4"
                ToolTip.delay: 400
            }
            TrimButton {
                text: "Set IN"
                onClicked: root.startTimeEdited(Math.max(0, Math.min(root.position, root.endTime - 0.1)))
            }
            TrimButton {
                text: "Set OUT"
                onClicked: root.endTimeEdited(Math.min(root.duration, Math.max(root.position, root.startTime + 0.1)))
            }
            TrimButton {
                text: "Reset range"
                onClicked: root.resetRequested()
            }
            Item { Layout.fillWidth: true }
            TrimButton {
                text: "Export..."
                enabled: exportQueue.canQueue
                onClicked: root.exportRequested()
            }
        }
    }
}

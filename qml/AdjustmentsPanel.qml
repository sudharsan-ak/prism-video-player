import QtQuick
import QtQuick.Controls

// Collapsible right-side panel, mirrors LibraryPanel's pattern exactly
// (PHASE1_PLAN_QT.md section 6.6). Opened via the dedicated top-bar
// Adjustments button.
Rectangle {
    id: root
    width: 270
    color: tokens.panelGlass || "#fff"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property var mpv: null
    signal closeRequested()

    property int activeTab: 0 // 0 picture, 1 audio, 2 subs


    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Row {
            width: parent.width
            Text {
                text: "ADJUSTMENTS"
                font.pixelSize: 9
                font.weight: Font.Black
                color: root.tokens.textMuted || "#888"
                width: parent.width - 20
            }
            Text {
                text: "✕"
                font.pixelSize: 11
                color: root.tokens.textMuted || "#888"
                MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
            }
        }

        Row {
            width: parent.width
            height: 28
            spacing: 4
            Repeater {
                model: ["Picture", "Audio", "Subs"]
                Rectangle {
                    width: (root.width - 28 - 8) / 3
                    height: parent.height
                    radius: 7
                    color: root.activeTab === index ? (root.tokens.panelGlassStrong || "#fff") : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        color: root.tokens.textPrimary || "#000"
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.activeTab = index }
                }
            }
        }

        // Picture tab
        Column {
            visible: root.activeTab === 0
            width: parent.width
            spacing: 14

            Row {
                width: parent.width
                Text {
                    text: "COLOR & LIGHT"
                    font.pixelSize: 9
                    font.weight: Font.Black
                    color: root.tokens.accentSolid || "#888"
                    width: parent.width - 50
                }
                Text {
                    text: "Reset"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    color: root.tokens.textSecondary || "#888"
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: {
                            playerController.setBrightness(0);
                            playerController.setContrast(0);
                            playerController.setSaturation(0);
                            playerController.setGamma(0);
                        }
                    }
                }
            }

            // Unrolled rather than a Repeater over a {label, prop} model:
            // each slider's value now binds directly to a real MpvObject
            // Q_PROPERTY (mpv.brightness etc, added alongside this fix)
            // so it stays in sync when changed from elsewhere - e.g. the
            // panel's own Reset button, or re-opening the panel on a
            // file whose values differ. The old version read through a
            // one-shot getProperty() call that never updated again after
            // the slider was first created.
            Column {
                width: root.width - 28
                spacing: 6
                Text { text: "Brightness"; font.pixelSize: 11; color: root.tokens.textPrimary || "#000" }
                Slider {
                    focusPolicy: Qt.NoFocus
                    width: parent.width
                    from: -100; to: 100
                    value: mpv ? mpv.brightness : 0
                    onMoved: playerController.setBrightness(value)
                }
            }
            Column {
                width: root.width - 28
                spacing: 6
                Text { text: "Contrast"; font.pixelSize: 11; color: root.tokens.textPrimary || "#000" }
                Slider {
                    focusPolicy: Qt.NoFocus
                    width: parent.width
                    from: -100; to: 100
                    value: mpv ? mpv.contrast : 0
                    onMoved: playerController.setContrast(value)
                }
            }
            Column {
                width: root.width - 28
                spacing: 6
                Text { text: "Saturation"; font.pixelSize: 11; color: root.tokens.textPrimary || "#000" }
                Slider {
                    focusPolicy: Qt.NoFocus
                    width: parent.width
                    from: -100; to: 100
                    value: mpv ? mpv.saturation : 0
                    onMoved: playerController.setSaturation(value)
                }
            }
            Column {
                width: root.width - 28
                spacing: 6
                Text { text: "Gamma"; font.pixelSize: 11; color: root.tokens.textPrimary || "#000" }
                Slider {
                    focusPolicy: Qt.NoFocus
                    width: parent.width
                    from: -100; to: 100
                    value: mpv ? mpv.gamma : 0
                    onMoved: playerController.setGamma(value)
                }
            }

            Text { text: "DISPLAY"; font.pixelSize: 9; font.weight: Font.Black; color: root.tokens.accentSolid || "#888" }

            Text { text: "Aspect ratio"; font.pixelSize: 11; color: root.tokens.textSecondary || "#888" }
            ThemedComboBox {
                width: parent.width
                tokens: root.tokens
                model: ["Original / Auto", "16:9", "4:3", "21:9", "1:1"]
                onActivated: {
                    const values = ["no", "16:9", "4:3", "21:9", "1:1"];
                    playerController.setAspectRatio(values[currentIndex]);
                }
            }

            Text { text: "Rotation"; font.pixelSize: 11; color: root.tokens.textSecondary || "#888" }
            Row {
                width: parent.width
                spacing: 4
                Repeater {
                    model: ["0°", "90°", "180°", "270°"]
                    Rectangle {
                        width: (root.width - 28 - 12) / 4
                        height: 30
                        radius: 7
                        border.width: 1
                        border.color: root.tokens.panelBorder || "#ccc"
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 10
                            color: root.tokens.textPrimary || "#000"
                        }
                        MouseArea { anchors.fill: parent; onClicked: playerController.setRotation(index) }
                    }
                }
            }
        }

        // Audio tab
        Column {
            visible: root.activeTab === 1
            width: parent.width
            spacing: 10

            Text { text: "AUDIO TRACK"; font.pixelSize: 9; font.weight: Font.Black; color: root.tokens.accentSolid || "#888" }
            ThemedComboBox {
                id: audioTrackBox
                width: parent.width
                tokens: root.tokens
                property var audioTracks: mpv ? mpv.trackList.filter(function(t) { return t.type === "audio"; }) : []
                model: audioTracks.map(function(t) { return t.title || t.lang || ("Track " + t.id); })
                onActivated: {
                    if (audioTracks[currentIndex]) playerController.setAudioTrack(audioTracks[currentIndex].id);
                }
            }

            Text { text: "SYNCHRONIZATION"; font.pixelSize: 9; font.weight: Font.Black; color: root.tokens.accentSolid || "#888" }
            Row {
                spacing: 8
                Button { text: "-0.5s"; onClicked: playerController.setAudioDelay(-0.5) }
                Button { text: "Reset"; onClicked: playerController.setAudioDelay(0) }
                Button { text: "+0.5s"; onClicked: playerController.setAudioDelay(0.5) }
            }
        }

        // Subs tab
        Column {
            visible: root.activeTab === 2
            width: parent.width
            spacing: 10

            Text { text: "SUBTITLE TRACK"; font.pixelSize: 9; font.weight: Font.Black; color: root.tokens.accentSolid || "#888" }
            ThemedComboBox {
                id: subtitleTrackBox
                width: parent.width
                tokens: root.tokens
                property var subTracks: mpv ? mpv.trackList.filter(function(t) { return t.type === "sub"; }) : []
                model: ["Off"].concat(subTracks.map(function(t) { return t.title || t.lang || ("Track " + t.id); }))
                onActivated: {
                    if (currentIndex === 0) playerController.setSubtitleTrack("no");
                    else if (subTracks[currentIndex - 1]) playerController.setSubtitleTrack(subTracks[currentIndex - 1].id);
                }
            }

            Text { text: "SYNCHRONIZATION"; font.pixelSize: 9; font.weight: Font.Black; color: root.tokens.accentSolid || "#888" }
            Row {
                spacing: 8
                Button { text: "-0.5s"; onClicked: playerController.setSubtitleDelay(-0.5) }
                Button { text: "Reset"; onClicked: playerController.setSubtitleDelay(0) }
                Button { text: "+0.5s"; onClicked: playerController.setSubtitleDelay(0.5) }
            }
        }
    }
}

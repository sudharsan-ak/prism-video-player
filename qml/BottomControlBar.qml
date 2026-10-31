import QtQuick
import QtQuick.Controls

// Docked control bar below the video (PHASE1_PLAN_QT.md section 6.7).
// Three-zone layout: left empty/reserved (locked decision), center
// transport group always visually centered, right utility icons.
Rectangle {
    id: root
    height: 92
    color: tokens.panelGlass || "#fff"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property var mpv: null

    property real scrubPosition: -1 // -1 = not scrubbing
    property int abLoopStage: 0 // 0 = no points set, 1 = A set, 2 = A+B set (looping)
    readonly property bool abLoopActive: abLoopStage > 0

    function formatTime(seconds) {
        seconds = Math.max(0, Math.floor(seconds || 0));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        const pad = n => String(n).padStart(2, "0");
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (m + ":" + pad(s));
    }

    // Every transport/utility icon shares this size and baseline so
    // nothing looks oversized or vertically off relative to its
    // neighbors - the previous version mixed bare Text items at three
    // different font sizes with no common box, which is what made the
    // row look uneven. Also carries the tooltip every icon was missing.
    component IconButton: Item {
        id: iconButton
        property alias text: glyph.text
        property string tip: ""
        property real glyphSize: 15
        property color iconColor: root.tokens.textPrimary || "#000"
        // Emoji glyphs (the camera icon) carry their own internal
        // vertical metrics that sit a couple px lower than plain text
        // glyphs ("CC", "AB") even when both are centered identically -
        // this per-instance nudge is how that gets corrected without
        // hacking the shared centering logic for every icon.
        property real glyphYOffset: 0
        signal clicked()

        width: 28
        height: 28

        Text {
            id: glyph
            anchors.centerIn: parent
            anchors.verticalCenterOffset: iconButton.glyphYOffset
            font.pixelSize: iconButton.glyphSize
            color: iconButton.iconColor
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: iconButton.clicked()
        }
        ToolTip.visible: iconButton.tip.length > 0 && mouseArea.containsMouse
        ToolTip.text: iconButton.tip
        ToolTip.delay: 450
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Row {
            width: parent.width
            height: 20
            spacing: 10

            Text {
                text: root.formatTime(root.scrubPosition >= 0 ? root.scrubPosition : (mpv ? mpv.position : 0))
                font.pixelSize: 10
                color: root.tokens.textSecondary || "#888"
                width: 36
            }

            Slider {
                id: seekSlider
                focusPolicy: Qt.NoFocus
                width: parent.width - 100
                from: 0
                to: Math.max(mpv ? mpv.duration : 0, 1)
                value: root.scrubPosition >= 0 ? root.scrubPosition : (mpv ? mpv.position : 0)
                onPressedChanged: {
                    if (pressed) {
                        root.scrubPosition = value;
                    } else {
                        playerController.seek(value);
                        root.scrubPosition = -1;
                    }
                }
                onMoved: root.scrubPosition = value
            }

            Text {
                text: root.formatTime(mpv ? mpv.duration : 0)
                font.pixelSize: 10
                color: root.tokens.textSecondary || "#888"
                width: 36
            }
        }

        Item {
            width: parent.width
            height: 36

            Row {
                anchors.centerIn: parent
                spacing: 8

                IconButton { text: "◀◀"; glyphSize: 13; tip: "Previous file"; onClicked: playerController.previous() }
                IconButton { text: "⏮"; glyphSize: 13; tip: "Back 10 seconds"; onClicked: playerController.skip(-10) }

                Rectangle {
                    width: 28; height: 28; radius: 14
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: root.tokens.accentGradient ? root.tokens.accentGradient[0] : "#D97757" }
                        GradientStop { position: 1; color: root.tokens.accentGradient ? root.tokens.accentGradient[root.tokens.accentGradient.length - 1] : "#D97757" }
                    }
                    // Drawn, not an emoji/font glyph: the pause "II" and
                    // play triangle render inconsistently across fonts
                    // (too-wide bars, odd vertical box) - two plain
                    // Rectangles and a rotated triangle give exact,
                    // predictable proportions instead.
                    Text {
                        visible: mpv && mpv.paused
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        text: "▶"
                        font.pixelSize: 13
                        color: "white"
                    }
                    Row {
                        visible: !(mpv && mpv.paused)
                        anchors.centerIn: parent
                        spacing: 3
                        Rectangle { width: 3; height: 11; radius: 1; color: "white" }
                        Rectangle { width: 3; height: 11; radius: 1; color: "white" }
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: playerController.togglePause()
                    }
                    ToolTip.visible: playArea.containsMouse
                    ToolTip.text: mpv && mpv.paused ? "Play" : "Pause"
                    ToolTip.delay: 450
                }

                IconButton { text: "⏭"; glyphSize: 13; tip: "Forward 10 seconds"; onClicked: playerController.skip(10) }
                IconButton { text: "▶▶"; glyphSize: 13; tip: "Next file"; onClicked: playerController.next() }

                Rectangle { width: 1; height: 16; color: root.tokens.panelBorder || "#ccc"; anchors.verticalCenter: parent.verticalCenter }

                IconButton {
                    text: mpv && mpv.volume > 0 ? "🔊" : "🔇"
                    tip: "Mute"
                    onClicked: playerController.setVolume(mpv && mpv.volume > 0 ? 0 : 80)
                }
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    focusPolicy: Qt.NoFocus
                    width: 58
                    from: 0
                    to: 100
                    value: mpv ? mpv.volume : 0
                    onMoved: playerController.setVolume(value)
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    width: speedLabel.implicitWidth + 14
                    height: 22
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.tokens.accentTint || "transparent"
                    border.color: root.tokens.panelBorder || "transparent"
                    border.width: 1
                    Text {
                        id: speedLabel
                        anchors.centerIn: parent
                        text: mpv ? (mpv.speed.toFixed(1) + "x") : "1.0x"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: root.tokens.textPrimary || "#000"
                    }
                    MouseArea {
                        id: speedArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // Cycles through the common presets - this
                            // chip looked clickable (hover cursor,
                            // tooltip) but previously had no handler at
                            // all.
                            const presets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
                            const current = mpv ? mpv.speed : 1.0;
                            let next = presets[0];
                            for (let i = 0; i < presets.length; i++) {
                                if (presets[i] > current + 0.001) { next = presets[i]; break; }
                                if (i === presets.length - 1) next = presets[0];
                            }
                            playerController.setSpeed(next);
                        }
                    }
                    ToolTip.visible: speedArea.containsMouse
                    ToolTip.text: "Playback speed"
                    ToolTip.delay: 450
                }

                IconButton {
                    text: "CC"
                    glyphSize: 11
                    // No subtitle track loaded/selected -> grey "off"
                    // state; a track selected -> accent-highlighted "on".
                    // Click toggles between off and the first available
                    // track, same pair of states the Subtitle menu's
                    // "Off" / track list already exposes.
                    iconColor: (mpv && mpv.sidActive) ? (root.tokens.accentSolid || "#888") : (root.tokens.textSecondary || "#888")
                    tip: (mpv && mpv.sidActive) ? "Subtitles: on (click to turn off)" : "Subtitles: off (click to turn on)"
                    onClicked: {
                        if (!mpv) return;
                        if (mpv.sidActive) {
                            playerController.setSubtitleTrack("no");
                        } else {
                            const subs = mpv.trackList.filter(function(t) { return t.type === "sub"; });
                            if (subs.length > 0) playerController.setSubtitleTrack(subs[0].id);
                        }
                    }
                }
                IconButton { text: "📷"; glyphSize: 13; glyphYOffset: -2; iconColor: root.tokens.textSecondary || "#888"; tip: "Screenshot - saves the current frame to Pictures/Prism Captures"; onClicked: playerController.takeScreenshot() }
                IconButton {
                    text: "AB"
                    glyphSize: 11
                    // Three-click cycle: set point A, set point B (loop
                    // becomes active), clear both - same model as the
                    // Play menu's "Set A-B loop points", exposed here as
                    // one quick button instead of two menu actions.
                    iconColor: root.abLoopActive ? (root.tokens.accentSolid || "#888") : (root.tokens.textSecondary || "#888")
                    tip: root.abLoopStage === 0 ? "Set loop point A" : (root.abLoopStage === 1 ? "Set loop point B" : "Clear A-B loop")
                    onClicked: {
                        if (root.abLoopStage === 0) {
                            playerController.setLoopA();
                            root.abLoopStage = 1;
                        } else if (root.abLoopStage === 1) {
                            playerController.setLoopB();
                            root.abLoopStage = 2;
                        } else {
                            playerController.clearLoop();
                            root.abLoopStage = 0;
                        }
                    }
                }
                IconButton { text: "⚙"; glyphSize: 13; iconColor: root.tokens.textSecondary || "#888"; tip: "Adjustments"; onClicked: prismWindow.toggleAdjustments() }
                IconButton { text: "⤢"; glyphSize: 13; iconColor: root.tokens.textSecondary || "#888"; tip: "Fullscreen"; onClicked: prismWindow.toggleFullscreen() }
            }
        }
    }
}

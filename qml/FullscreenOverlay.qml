import QtQuick
import QtQuick.Controls

// Floating glass control bar shown only in fullscreen (PHASE1_PLAN_QT.md
// section 6.8). Appears on mouse movement, auto-hides after ~3s idle,
// compact width per the user's explicit "it needn't be this long"
// feedback on the first design draft.
Item {
    id: root
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 110
    // Explicit z: videoSurface is reparented into fullscreenVideoSlot at
    // runtime (see Main.qml onFullscreenModeChanged), and a dynamically
    // reparented item's implicit stacking order is not guaranteed to
    // respect QML declaration order - without this the video's own
    // full-area MouseArea could sit above the overlay and swallow every
    // click meant for these buttons, which is exactly what made none of
    // them respond.
    z: 10

    property var tokens: themeController.tokens
    property var mpv: null
    property bool active: false

    function formatTime(seconds) {
        const exact = Math.max(0, seconds || 0);
        const whole = Math.floor(exact);
        const m = Math.floor(whole / 60);
        const sec = whole % 60;
        const base = m + ":" + String(sec).padStart(2, "0");
        return mpv && mpv.duration > 0 && mpv.duration < 10
            ? base + "." + String(Math.floor((exact - whole) * 100 + 0.001)).padStart(2, "0")
            : base;
    }

    function notifyActivity() {
        visibleBar.opacity = 1;
        idleTimer.restart();
    }

    function toggleVisibility() {
        if (visibleBar.opacity > 0) {
            idleTimer.stop();
            visibleBar.opacity = 0;
        } else {
            notifyActivity();
        }
    }

    Timer {
        id: idleTimer
        interval: 3000
        onTriggered: visibleBar.opacity = 0
    }

    component OverlayIconButton: Item {
        id: iconButton
        property alias text: glyph.text
        property string tip: ""
        property real glyphSize: 13
        width: 26
        height: 26

        Text {
            id: glyph
            anchors.centerIn: parent
            font.pixelSize: iconButton.glyphSize
            color: "white"
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: iconButton.clicked()
        }
        signal clicked()
        ToolTip.visible: iconButton.tip.length > 0 && mouseArea.containsMouse
        ToolTip.text: iconButton.tip
        ToolTip.delay: 450
    }

    Item {
        id: visibleBar
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 250 }
        }

        Rectangle {
            width: 560
            height: 86
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            radius: 14
            color: Qt.rgba(0.12, 0.11, 0.09, 0.6)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    height: 18
                    spacing: 9

                    Text {
                        text: root.formatTime(fullscreenSeek.displayPosition)
                        font.pixelSize: 9
                        color: "#D8D2C4"
                        width: 32
                    }
                    ThemedSeekBar {
                        id: fullscreenSeek
                        width: parent.width - 80
                        height: parent.height
                        mediaPosition: mpv ? mpv.position : 0
                        mediaDuration: mpv ? mpv.duration : 0
                        onSeekRequested: function(seconds) { playerController.seek(seconds); }
                    }

                    Text {
                        text: root.formatTime(mpv ? mpv.duration : 0)
                        font.pixelSize: 9
                        color: "#D8D2C4"
                        width: 32
                    }
                }

                Item {
                    width: parent.width
                    height: 44

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            text: mpv && mpv.volume > 0 ? "🔊" : "🔇"
                            font.pixelSize: 12
                            color: "#D8D2C4"
                            MouseArea {
                                anchors.fill: parent
                                onClicked: playerController.setVolume(mpv && mpv.volume > 0 ? 0 : 80)
                            }
                        }
                        // Was a plain drawn Rectangle with no MouseArea -
                        // looked like a slider but could never actually
                        // be dragged, unlike the equivalent control in
                        // the windowed bottom bar.
                        Slider {
                            anchors.verticalCenter: parent.verticalCenter
                            focusPolicy: Qt.NoFocus
                            width: 60
                            from: 0
                            to: 100
                            value: mpv ? mpv.volume : 0
                            onMoved: playerController.setVolume(value)
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        OverlayIconButton { text: "⏮"; glyphSize: 12; tip: "Back 10 seconds"; onClicked: playerController.skip(-10) }
                        OverlayIconButton { text: "◀◀"; glyphSize: 12; tip: "Previous file"; onClicked: playerController.previous() }

                        Rectangle {
                            width: 30; height: 30; radius: 15
                            anchors.verticalCenter: parent.verticalCenter
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0; color: root.tokens.accentGradient ? root.tokens.accentGradient[0] : "#D97757" }
                                GradientStop { position: 1; color: root.tokens.accentGradient ? root.tokens.accentGradient[root.tokens.accentGradient.length - 1] : "#D97757" }
                            }
                            Text {
                                visible: mpv && mpv.paused
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 1
                                text: "▶"
                                font.pixelSize: 14
                                color: "#1A1510"
                            }
                            Row {
                                visible: !(mpv && mpv.paused)
                                anchors.centerIn: parent
                                spacing: 3
                                Rectangle { width: 3; height: 11; radius: 1; color: "#1A1510" }
                                Rectangle { width: 3; height: 11; radius: 1; color: "#1A1510" }
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

                        OverlayIconButton { text: "▶▶"; glyphSize: 12; tip: "Next file"; onClicked: playerController.next() }
                        OverlayIconButton { text: "⏭"; glyphSize: 12; tip: "Forward 10 seconds"; onClicked: playerController.skip(10) }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        OverlayIconButton { text: "CC"; glyphSize: 11; tip: "Subtitles" }
                        OverlayIconButton { text: "📷"; glyphSize: 12; tip: "Screenshot"; onClicked: playerController.takeScreenshot() }
                        OverlayIconButton { text: "⤢"; glyphSize: 12; tip: "Exit fullscreen"; onClicked: prismWindow.toggleFullscreen() }
                    }
                }
            }
        }
    }
}

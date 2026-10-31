import QtQuick

// Brief, auto-fading indicator for volume/brightness changes, matching
// PotPlayer/VLC behavior (PHASE1_PLAN_QT.md section 5.1). Call show()
// whenever a value changes via keyboard, scroll, or menu, not just
// when the persistent Adjustments-panel sliders move.
Item {
    id: root
    width: 220
    height: 64
    opacity: 0

    property string label: "Volume"
    property real value: 0
    property real maxValue: 100
    property var tokens: themeController.tokens

    function show(newLabel, newValue, newMax) {
        label = newLabel;
        value = newValue;
        maxValue = newMax > 0 ? newMax : 100;
        hideTimer.restart();
        opacity = 1;
    }

    Behavior on opacity {
        NumberAnimation { duration: 220 }
    }

    Timer {
        id: hideTimer
        interval: 900
        onTriggered: root.opacity = 0
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: tokens.panelGlassStrong || "#1C1D26"
        border.color: tokens.panelBorder || "transparent"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            Text {
                text: root.label
                color: tokens.textPrimary || "#fff"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(0, 0, 0, 0.12)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.value / root.maxValue))
                    height: parent.height
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: tokens.accentGradient ? tokens.accentGradient[0] : "#D97757" }
                        GradientStop { position: 1.0; color: tokens.accentGradient ? tokens.accentGradient[tokens.accentGradient.length - 1] : "#D97757" }
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls

// Shared seek bar for the windowed and fullscreen controls. The played
// portion is always visible and uses the active Prism theme's accent;
// the muted remainder is NOT a streaming/buffer indicator.
// Clicking or dragging previews locally, then seeks once on release.
Slider {
    id: root

    property var tokens: themeController.tokens
    property real mediaPosition: 0
    property real mediaDuration: 0
    property bool endOfFileReached: false
    property real scrubPosition: -1

    // mpv's time-pos stops at the PTS of the last decoded frame,
    // which can be one frame (~40ms at 24fps) short of duration.
    // Show a fully completed seek bar only after mpv confirms EOF.
    // A user scrub takes precedence so the handle remains draggable.
    readonly property real displayPosition: scrubPosition >= 0 ? scrubPosition
        : (endOfFileReached && mediaDuration > 0 ? mediaDuration : mediaPosition)
    readonly property int trackThickness: settingsStore.seekBarThickness === "thick" ? 8
        : (settingsStore.seekBarThickness === "medium" ? 6 : 4)
    readonly property bool flatStyle: themeController.activeThemeName === "terminalFlat"
    readonly property real hoverX: Math.max(0, Math.min(width, seekHover.point.position.x))
    readonly property real previewSeconds: mediaDuration * Math.max(0, Math.min(1,
        (hoverX - leftPadding) / Math.max(1, availableWidth)))

    signal seekRequested(real seconds)

    function formatTime(seconds) {
        const whole = Math.max(0, Math.floor(seconds || 0));
        const h = Math.floor(whole / 3600);
        const m = Math.floor((whole % 3600) / 60);
        const s = whole % 60;
        const pad = n => String(n).padStart(2, "0");
        return h ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
    }

    implicitHeight: 24
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    from: 0
    to: Math.max(mediaDuration, 1)
    value: Math.max(0, Math.min(to, displayPosition))
    enabled: mediaDuration > 0

    // Keep the original windowed seek behavior: do not spam mpv with
    // exact-seek commands while scrubbing; commit only on release.
    onPressedChanged: {
        if (pressed) {
            scrubPosition = value;
        } else if (scrubPosition >= 0) {
            const destination = Math.max(0, Math.min(mediaDuration, value));
            scrubPosition = -1;
            seekRequested(destination);
        }
    }
    onMoved: scrubPosition = value

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: root.trackThickness + ((root.hovered || root.pressed) ? 2 : 0)

        Rectangle {
            anchors.fill: parent
            radius: root.flatStyle ? 1 : height / 2
            color: root.tokens.seekTrack || "#4A4A60"
        }
        Rectangle {
            width: Math.max(0, Math.min(parent.width, parent.width * root.visualPosition))
            height: parent.height
            radius: root.flatStyle ? 1 : height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: root.tokens.accentGradient ? root.tokens.accentGradient[0] : "#E2A86F"
                }
                GradientStop {
                    position: 1
                    color: root.tokens.accentGradient
                        ? root.tokens.accentGradient[root.tokens.accentGradient.length - 1] : "#D97757"
                }
            }
        }
    }

    handle: Rectangle {
        width: (root.hovered || root.pressed) ? 18 : 14
        height: width
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        radius: root.flatStyle ? 3 : width / 2
        color: root.tokens.accentSolid || "#D97757"
        border.width: 2
        border.color: root.tokens.seekThumbEdge || "#FFFFFF"

        Behavior on width { NumberAnimation { duration: 110 } }
    }

    // Hover-only preview does not grab clicks, so it cannot block Slider
    // dragging or interfere with the native libmpv rendering surface.
    HoverHandler {
        id: seekHover
        cursorShape: Qt.PointingHandCursor
    }

    Rectangle {
        visible: seekHover.hovered && root.mediaDuration > 0 && !root.pressed
        z: 5
        width: previewLabel.implicitWidth + 16
        height: 25
        radius: 6
        x: Math.max(0, Math.min(root.width - width, root.hoverX - width / 2))
        y: -29
        color: "#1C1D26"
        border.color: "#444654"
        border.width: 1

        Text {
            id: previewLabel
            anchors.centerIn: parent
            text: root.formatTime(root.previewSeconds)
            font.pixelSize: 11
            color: "#FFFFFF"
        }
    }
}

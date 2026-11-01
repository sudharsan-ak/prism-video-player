import QtQuick

// Cropping takes place on the ROTATED picture, before GIF scaling.
// Bounds are relative to the full displayed video (0..1), never to
// the entire player window / letterbox bars.
Item {
    id: root
    property var tokens: themeController.tokens
    property int sourceWidth: 0
    property int sourceHeight: 0
    property int quarterTurns: 0
    property real cropX: 0
    property real cropY: 0
    property real cropWidth: 1
    property real cropHeight: 1
    signal cropEdited(real x, real y, real w, real h)

    readonly property bool sideways: quarterTurns % 2 === 1
    readonly property real rotatedWidth: sideways ? sourceHeight : sourceWidth
    readonly property real rotatedHeight: sideways ? sourceWidth : sourceHeight
    readonly property real scaleFactor: sourceWidth > 0 && sourceHeight > 0
        ? Math.min(width / Math.max(1, rotatedWidth),
                   height / Math.max(1, rotatedHeight)) : 0

    // Record drag origin to prevent pointer movement from accumulating
    // rounding errors as the crop rectangle rerenders.
    property real startPointerX: 0
    property real startPointerY: 0
    property real originalX: 0
    property real originalY: 0
    property real originalW: 1
    property real originalH: 1
    property int dragCorner: -2  // -1 = move; 0 TL, 1 TR, 2 BL, 3 BR
    readonly property real minFraction: 0.05

    function limit(value, lo, hi) {
        return Math.max(lo, Math.min(value, hi));
    }

    function beginDrag(corner, item, mx, my) {
        const local = item.mapToItem(frame, mx, my);
        startPointerX = local.x;
        startPointerY = local.y;
        originalX = cropX;
        originalY = cropY;
        originalW = cropWidth;
        originalH = cropHeight;
        dragCorner = corner;
    }

    function updateDrag(item, mx, my) {
        if (frame.width <= 0 || frame.height <= 0 || dragCorner === -2)
            return;
        const pointer = item.mapToItem(frame, mx, my);
        const dx = (pointer.x - startPointerX) / frame.width;
        const dy = (pointer.y - startPointerY) / frame.height;
        let x = originalX, y = originalY;
        let w = originalW, h = originalH;
        if (dragCorner === -1) {
            x = limit(originalX + dx, 0, 1 - originalW);
            y = limit(originalY + dy, 0, 1 - originalH);
        } else {
            if (dragCorner === 0 || dragCorner === 2) {
                x = limit(originalX + dx, 0, originalX + originalW - minFraction);
                w = originalX + originalW - x;
            } else {
                w = limit(originalW + dx, minFraction, 1 - originalX);
            }
            if (dragCorner === 0 || dragCorner === 1) {
                y = limit(originalY + dy, 0, originalY + originalH - minFraction);
                h = originalY + originalH - y;
            } else {
                h = limit(originalH + dy, minFraction, 1 - originalY);
            }
        }
        root.cropEdited(x, y, w, h);
    }

    Item {
        id: frame
        width: root.rotatedWidth * root.scaleFactor
        height: root.rotatedHeight * root.scaleFactor
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        visible: root.scaleFactor > 0

        // Four outside regions darken everything except the export crop.
        Rectangle {
            x: 0; y: 0; width: parent.width
            height: root.cropY * parent.height
            color: "#88000000"
        }
        Rectangle {
            x: 0
            y: (root.cropY + root.cropHeight) * parent.height
            width: parent.width
            height: Math.max(0, parent.height - y)
            color: "#88000000"
        }
        Rectangle {
            x: 0
            y: root.cropY * parent.height
            width: root.cropX * parent.width
            height: root.cropHeight * parent.height
            color: "#88000000"
        }
        Rectangle {
            x: (root.cropX + root.cropWidth) * parent.width
            y: root.cropY * parent.height
            width: Math.max(0, parent.width - x)
            height: root.cropHeight * parent.height
            color: "#88000000"
        }

        Rectangle {
            id: selection
            x: root.cropX * frame.width
            y: root.cropY * frame.height
            width: root.cropWidth * frame.width
            height: root.cropHeight * frame.height
            color: "transparent"
            border.width: 2
            border.color: root.tokens.accentSolid || "#25EA78"

            // Rule-of-thirds guides; these are noninteractive.
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    x: selection.width * (index + 1) / 3
                    y: 0
                    width: 1
                    height: selection.height
                    color: "#AFFFFFFF"
                    opacity: 0.7
                }
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    y: selection.height * (index + 1) / 3
                    x: 0
                    height: 1
                    width: selection.width
                    color: "#AFFFFFFF"
                    opacity: 0.7
                }
            }
            MouseArea {
                id: moveArea
                anchors.fill: parent
                anchors.margins: 9
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function(mouse) { root.beginDrag(-1, moveArea, mouse.x, mouse.y); }
                onPositionChanged: function(mouse) {
                    if (pressed) root.updateDrag(moveArea, mouse.x, mouse.y);
                }
                onReleased: root.dragCorner = -2
                onCanceled: root.dragCorner = -2
            }
        }

        Repeater {
            model: 4
            Rectangle {
                id: handle
                required property int index
                width: 15
                height: 15
                radius: 3
                color: root.tokens.accentSolid || "#25EA78"
                border.width: 2
                border.color: root.tokens.textPrimary || "#FFFFFF"
                x: selection.x + (index % 2 ? selection.width : 0) - width / 2
                y: selection.y + (index >= 2 ? selection.height : 0) - height / 2
                MouseArea {
                    id: grabArea
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: index === 0 || index === 3
                        ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                    onPressed: function(mouse) {
                        root.beginDrag(index, grabArea, mouse.x, mouse.y);
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed) root.updateDrag(grabArea, mouse.x, mouse.y);
                    }
                    onReleased: root.dragCorner = -2
                    onCanceled: root.dragCorner = -2
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: selection.horizontalCenter
            y: selection.y > 24 ? selection.y - 26 : selection.y + 8
            width: cropHint.implicitWidth + 16
            height: 20
            radius: 5
            color: root.tokens.panelGlassStrong || "#1B2420"
            border.color: root.tokens.panelBorder || "#456"
            Text {
                id: cropHint
                anchors.centerIn: parent
                text: Math.round(root.cropWidth * 100) + "% × " +
                      Math.round(root.cropHeight * 100) + "%"
                font.pixelSize: 10
                color: root.tokens.textPrimary || "#FFFFFF"
            }
        }
    }
}

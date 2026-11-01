import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Trim selection is independent of the playback seek bar: only the
// range handles change the exported IN/OUT values. The draggable playhead
// scrubs mpv position; export cuts at the exact chosen times.
Rectangle {
    id: root
    height: 365
    color: tokens.panelGlass || "#20202B"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property real duration: 0
    property real sourceDuration: 0
    property var displaySegments: []
    property int selectedSegmentId: -1
    property real keptDuration: 0
    property real keptPosition: 0
    property bool canUndo: false
    property bool canRedo: false
    property bool hasNextKept: false
    property bool segmentEditing: false
    property string segmentWarning: ""
    property real position: 0
    property real startTime: 0
    property real endTime: 0
    property real editSpeed: 1.0
    property bool previewPlaying: false
    property bool rangePlaying: false
    property int audioVolumePercent: 100
    property int lastAudibleVolume: 100
    property bool sourceIsMp4: false
    property bool selectedRemoved: false
    property bool selectedCollapsed: false
    property bool canSoftDelete: false
    signal beginningRequested()
    signal resetAllRequested()
    signal exampleRequested()

    signal startTimeEdited(real seconds)
    signal endTimeEdited(real seconds)
    signal rangeMoveStarted()
    signal rangeMoved(real newStart, real newEnd)
    signal rangeMoveFinished(real newStart)
    signal seekRequested(real seconds)
    signal previewRequested()
    signal togglePlaybackRequested()
    signal speedEdited(real speed)
    signal audioVolumeEdited(int percent)
    signal resetRequested()
    signal exportRequested()
    signal splitRequested()
    signal softDeleteRequested()
    signal restoreSegmentRequested()
    signal removeGapRequested(int segmentId)
    signal undoRequested()
    signal redoRequested()
    signal jumpNextRequested()
    signal normalPlaybackRequested()
    signal segmentSelected(int segmentId)
    signal segmentSelectedAt(real visualSeconds)
    signal playbackSeekRequested(real editedSeconds)

    function seekTimeAtPixel(pixelX) {
        if (root.duration <= 0 || frameTrack.width <= 0)
            return 0;
        return Math.max(0, Math.min(root.duration,
            pixelX * root.duration / frameTrack.width));
    }

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

        // Floating player, relocated below the video as approved.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 43
            Rectangle {
                id: previewPill
                anchors.centerIn: parent
                height: 37
                width: previewContent.implicitWidth + 28
                radius: 19
                color: "#E509131B"
                border.width: 1
                border.color: root.tokens.panelBorder || "#23515A"
                Row {
                    id: previewContent
                    anchors.centerIn: parent
                    spacing: 12
                    Button {
                        text: "↤"; width: 28; height: 30
                        onClicked: root.beginningRequested()
                        ToolTip.visible: hovered
                        ToolTip.text: "Beginning of edited timeline"
                        background: Item {}
                        contentItem: Text {
                            text: parent.text
                            color: "#FFFFFF"
                            font.pixelSize: 15
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        id: previewPlay
                        width: 33; height: 33
                        text: root.previewPlaying ? "❚❚" : "▶"
                        onClicked: root.normalPlaybackRequested()
                        background: Rectangle {
                            radius: 18
                            color: root.tokens.accentSolid || "#29C7AC"
                        }
                        contentItem: Text {
                            text: previewPlay.text
                            color: "#071D1D"
                            font.pixelSize: 15
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.timeText(root.keptPosition) + " / " + root.timeText(root.keptDuration)
                        font.pixelSize: 11
                        font.bold: true
                        color: "#FFFFFF"
                    }
                    Button {
                        width: 30; height: 30
                        text: root.audioVolumePercent === 0 ? "🔇" : "🔊"
                        onClicked: root.audioVolumeEdited(root.audioVolumePercent===0
                            ? Math.max(1,root.lastAudibleVolume) : 0)
                        background: Item {}
                        contentItem: Text {
                            text: parent.text; font.pixelSize: 13
                            color: "#FFFFFF"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 9
            Text {
                text: "SEGMENT TIMELINE"
                color: root.tokens.textPrimary || "#E6F6F6"
                font.pixelSize: 11
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: countText.implicitWidth+16
                radius: 12
                color: root.tokens.panelGlassStrong || "#0C3038"
                border.color: root.tokens.panelBorder || "#23515A"
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: root.displaySegments.length + " segment(s)"
                    color: root.tokens.textSecondary || "#85AAB1"
                    font.pixelSize: 10
                }
            }
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: editedTimeText.implicitWidth+18
                radius: 12
                color: root.tokens.panelGlassStrong || "#0C3038"
                border.color: root.tokens.panelBorder || "#23515A"
                Text {
                    id: editedTimeText
                    anchors.centerIn: parent
                    text: root.timeText(root.keptDuration/Math.max(.25,root.editSpeed)) + " export"
                    color: root.tokens.accentSolid || "#29C7AC"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            font.pixelSize: 10
            color: root.tokens.textMuted || "#638C96"
            wrapMode: Text.WordWrap
            text: "Move IN and OUT on the thumbnails, then Split selection. Soft Delete shortens the edited playback clock; Remove Gap closes the visible space. The playhead stays independent."
        }

        // One interaction toolbar above the time ruler, matching HTML.
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 5
            component Action: Button {
                id: action
                font.pixelSize: 10
                padding: 7
                background: Rectangle {
                    radius: 7
                    color: action.hovered ? (root.tokens.accentTint || "#124B4C") :
                         (root.tokens.panelGlassStrong || "#113840")
                    border.color: root.tokens.panelBorder || "#23515A"
                    border.width: 1
                }
                contentItem: Text {
                    text: action.text
                    font: action.font
                    color: root.tokens.textPrimary || "#E6F6F6"
                    opacity: action.enabled ? 1 : .35
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Action {
                text: root.rangePlaying ? "❚❚ Pause range    R" : "▶ Play range    R"
                onClicked: root.togglePlaybackRequested()
            }
            Action {
                text: "⇥ Jump next    J"
                enabled: root.hasNextKept
                onClicked: root.jumpNextRequested()
            }
            Button {
                id: splitButton
                text: "✂ Split selection    S"
                font.pixelSize: 10
                padding: 7
                enabled: root.endTime-root.startTime >= .05
                onClicked: root.splitRequested()
                background: Rectangle {
                    radius: 7
                    color: splitButton.enabled ?
                          (root.tokens.accentSolid || "#29C7AC") :
                          (root.tokens.panelGlassStrong || "#113840")
                }
                contentItem: Text {
                    text: splitButton.text
                    font: splitButton.font
                    color: splitButton.enabled ? (root.tokens.videoCardBackground || "#06171D") :
                                                (root.tokens.textMuted || "#638C96")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Action {
                text: "▧ Soft Delete    Del"
                enabled: root.canSoftDelete
                onClicked: root.softDeleteRequested()
            }
            Action {
                text: "↩ Restore"
                enabled: root.selectedRemoved
                onClicked: root.restoreSegmentRequested()
            }
            Action {
                text: "⌦ Remove Gap"
                enabled: root.selectedRemoved && !root.selectedCollapsed
                onClicked: root.removeGapRequested(root.selectedSegmentId)
            }
            Action { text: "↶"; enabled: root.canUndo; onClicked: root.undoRequested() }
            Action { text: "↷"; enabled: root.canRedo; onClicked: root.redoRequested() }
            Action {
                text: "Set IN"
                onClicked: root.startTimeEdited(Math.min(root.position,root.endTime-.12))
            }
            Action {
                text: "Set OUT"
                onClicked: root.endTimeEdited(Math.max(root.position,root.startTime+.12))
            }
            Action { text: "Reset range"; onClicked: root.resetRequested() }
            Action {
                text: "✧ Try example"
                enabled: root.sourceDuration > 1.0
                onClicked: root.exampleRequested()
            }
            Action { text: "Reset all"; onClicked: root.resetAllRequested() }
        }

        Item {
            id: timelineRuler
            Layout.fillWidth: true
            Layout.preferredHeight: 15
            Repeater {
                model: 13
                Item {
                    property real p: index/12
                    x: p*timelineRuler.width
                    width: 1
                    height: timelineRuler.height
                    Rectangle {
                        anchors.top: parent.top
                        width: 1
                        height: index % 3 === 0 ? 8 : 4
                        color: root.tokens.textMuted || "#888"
                        opacity: 0.65
                    }
                    Text {
                        visible: index % 3 === 0
                        x: index === 12 ? -36 : 2
                        y: 1
                        text: root.timeText(root.duration*p)
                        color: root.tokens.textSecondary || "#aaa"
                        font.pixelSize: 9
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onDoubleClicked: function(mouse) {
                    root.seekRequested(Math.max(0,Math.min(root.duration,
                        mouse.x/Math.max(1,timelineRuler.width)*root.duration)));
                }
                ToolTip.visible: containsMouse
                ToolTip.text: "Double-click to preview this position"
                hoverEnabled: true
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 90

            // Real thumbnail images are generated asynchronously by FFmpeg.
            Rectangle {
                id: frameTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 72
                radius: 7
                color: root.tokens.videoCardBackground || "#111"
                border.color: root.tokens.panelBorder || "#555"
                clip: true

                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: root.displaySegments
                        Item {
                            id: segmentTile
                            required property var modelData
                            property var seg: modelData
                            width: Math.max(0, seg.visualEnd-seg.visualStart) /
                                Math.max(root.duration,0.001) * frameTrack.width
                            height: frameTrack.height
                            clip: true
                            visible: width > 0.5
                            Rectangle {
                                anchors.fill: parent
                                color: root.tokens.videoCardBackground || "#12171A"
                            }
                            Row {
                                anchors.fill: parent
                                spacing: 0
                                Repeater {
                                    model: Math.max(1,Math.ceil(segmentTile.width/50))
                                    Item {
                                        property real sourceSecond: segmentTile.seg.start +
                                            (index+0.5)/Math.max(1,Math.ceil(segmentTile.width/50))
                                            * (segmentTile.seg.end-segmentTile.seg.start)
                                        width: segmentTile.width /
                                            Math.max(1,Math.ceil(segmentTile.width/50))
                                        height: segmentTile.height
                                        Image {
                                            anchors.fill: parent
                                            property var frames: videoThumbnailController.frames
                                            source: frames.length ?
                                                frames[Math.min(frames.length-1,Math.max(0,
                                                  Math.floor(sourceSecond /
                                                    Math.max(root.sourceDuration,0.001)*frames.length)))] : ""
                                            fillMode: Image.PreserveAspectCrop
                                            cache: false
                                            asynchronous: true
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: "#AA0A1117"
                                visible: segmentTile.seg.removed
                            }
                            Repeater {
                                model: segmentTile.seg.removed ? Math.ceil(segmentTile.width/12)+5 : 0
                                Rectangle {
                                    x: index*12-32; y: -15
                                    width: 2; height: segmentTile.height+50
                                    rotation: 40
                                    color: "#6685A5A4"
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: root.selectedSegmentId === segmentTile.seg.id ? 2 : 1
                                border.color: root.selectedSegmentId === segmentTile.seg.id
                                    ? (root.tokens.accentSolid || "#28DCA7") : "#55777777"
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: root.segmentSelected(segmentTile.seg.id)
                                onDoubleClicked: function(mouse) {
                                    const pt=mapToItem(frameTrack,mouse.x,mouse.y);
                                    root.seekRequested(root.seekTimeAtPixel(pt.x));
                                }
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                text: root.timeText(segmentTile.seg.end-segmentTile.seg.start)
                                visible: segmentTile.width > 68
                                font.pixelSize: 9
                                color: "#FFF"
                                style: Text.Outline
                                styleColor: "#111"
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
                    x: (root.startTime/Math.max(root.duration,0.001)) * parent.width
                    width: Math.max(0, ((root.endTime/Math.max(root.duration,0.001)) - (root.startTime/Math.max(root.duration,0.001))) * parent.width)
                    height: parent.height
                    color: root.tokens.accentTint || "#334466"
                    border.color: root.tokens.accentSolid || "#A89BFF"
                    border.width: 2
                }
            }

            // Trim handles are separate from the click targets on segments.
            Rectangle {
                id: inHandle
                width: 14; height: frameTrack.height
                x: frameTrack.x + Math.max(0, Math.min(frameTrack.width-width,
                    root.startTime/Math.max(root.duration,0.001)*frameTrack.width-width/2 -
                    (Math.abs(root.endTime-root.startTime)<0.001 ? width/2 : 0)))
                y: frameTrack.y; radius: 4; z: 12
                color: root.tokens.accentSolid || "#29C7AC"
                border.color: root.tokens.textPrimary || "#fff"
                border.width: 1
                Text { anchors.centerIn: parent; text: "Ⅰ"; font.pixelSize: 11; color: "#071D1D" }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if (pressed) root.startTimeEdited(root.seekTimeAtPixel(
                            mapToItem(frameTrack,mouse.x,mouse.y).x));
                    }
                }
            }
            Rectangle {
                id: outHandle
                width: 14; height: frameTrack.height
                x: frameTrack.x + Math.max(0, Math.min(frameTrack.width-width,
                    root.endTime/Math.max(root.duration,0.001)*frameTrack.width-width/2 +
                    (Math.abs(root.endTime-root.startTime)<0.001 ? width/2 : 0)))
                y: frameTrack.y; radius: 4; z: 13
                color: root.tokens.accentSolid || "#29C7AC"
                border.color: root.tokens.textPrimary || "#fff"
                border.width: 1
                Text { anchors.centerIn: parent; text: "Ⅱ"; font.pixelSize: 11; color: "#071D1D" }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if (pressed) root.endTimeEdited(root.seekTimeAtPixel(
                            mapToItem(frameTrack,mouse.x,mouse.y).x));
                    }
                }
            }

            // Only the narrow TOP BORDER of the selection is draggable.
            // All other pixels remain clickable for segment selection.
            MouseArea {
                id: moveSelectionArea
                property real pressX: 0
                property real originalStart: 0
                property real originalEnd: 0
                property bool dragActivated: false
                property real clickThreshold: 5
                x: frameTrack.x + (root.startTime/Math.max(root.duration,0.001)) * frameTrack.width + 14
                y: frameTrack.y
                width: Math.max(0, ((root.endTime/Math.max(root.duration,0.001)) -
                    (root.startTime/Math.max(root.duration,0.001))) * frameTrack.width - 28)
                height: 8
                visible: width > 10 && root.duration > 0
                z: 5
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function(mouse) {
                    pressX = moveSelectionArea.mapToItem(frameTrack, mouse.x, mouse.y).x;
                    originalStart = root.startTime;
                    originalEnd = root.endTime;
                    dragActivated = false;
                }
                onPositionChanged: function(mouse) {
                    if (!pressed || root.duration <= 0 || frameTrack.width <= 0)
                        return;
                    const pointerX = moveSelectionArea.mapToItem(
                        frameTrack, mouse.x, mouse.y).x;
                    const pixelDelta = pointerX - pressX;
                    // A click moves only the playhead. A deliberate drag
                    // moves the entire IN/OUT selection together.
                    if (!dragActivated) {
                        if (Math.abs(pixelDelta) < clickThreshold)
                            return;
                        dragActivated = true;
                        root.rangeMoveStarted();
                    }
                    const delta = pixelDelta * root.duration / frameTrack.width;
                    const span = originalEnd - originalStart;
                    const start = Math.max(0, Math.min(root.duration - span,
                                                     originalStart + delta));
                    root.rangeMoved(start, start + span);
                }
                onReleased: function(mouse) {
                    if (dragActivated) {
                        root.rangeMoveFinished(root.startTime);
                    } else {
                        const pointerX = moveSelectionArea.mapToItem(
                            frameTrack, mouse.x, mouse.y).x;
                        // The click was inside the selected region, so do
                        // not change either trim boundary.
                        root.segmentSelectedAt(root.seekTimeAtPixel(pointerX));
                    }
                    dragActivated = false;
                }
                onDoubleClicked: function(mouse) {
                    const pt=moveSelectionArea.mapToItem(frameTrack,mouse.x,mouse.y);
                    root.seekRequested(root.seekTimeAtPixel(pt.x));
                }
                onCanceled: dragActivated = false
            }

            // Above RangeSlider and selection drag layer so this button
            // remains clickable even when the excluded gap is selected.
            Repeater {
                model: root.displaySegments
                Button {
                    id: gapAction
                    required property var modelData
                    property var seg: modelData
                    width: Math.min(116,Math.max(0,
                        (seg.visualEnd-seg.visualStart) /
                        Math.max(root.duration,0.001)*frameTrack.width - 12))
                    height: 24
                    x: frameTrack.x + (seg.visualStart+seg.visualEnd) /
                        2/Math.max(root.duration,0.001)*frameTrack.width - width/2
                    y: frameTrack.y + (frameTrack.height-height)/2
                    z: 6
                    visible: seg.removed && !seg.collapsed && width > 92
                    text: "▣ Remove Gap"
                    font.pixelSize: 10
                    onClicked: root.removeGapRequested(seg.id)
                    background: Rectangle {
                        radius: 6
                        color: gapAction.hovered ? (root.tokens.accentTint || "#29463A")
                                                 : (root.tokens.panelGlassStrong || "#131B1E")
                        border.color: root.tokens.accentSolid || "#28DCA7"
                    }
                    contentItem: Text {
                        text: gapAction.text
                        font: gapAction.font
                        color: root.tokens.textPrimary || "#fff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Clipchamp-style playhead: a wide grab target and a narrow
            // theme-aware needle. It floats above the thumbnail strip,
            // without making the marker itself visually bulky.
            Item {
                id: playheadMarker
                property real displayTime: playheadGrab.pressed
                    ? playheadGrab.scrubSeconds : root.position
                width: 22
                height: frameTrack.height + 36
                x: frameTrack.x +
                    Math.max(0, Math.min(1, displayTime / Math.max(root.duration, 0.001)))
                    * frameTrack.width - width / 2
                y: frameTrack.y - 36
                z: 7
                visible: root.duration > 0

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    width: 4
                    height: parent.height - 12
                    color: root.tokens.textPrimary || "#FFFFFF"
                    border.width: 1
                    border.color: root.tokens.videoCardBackground || "#101010"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: 20
                    height: 16
                    radius: 5
                    color: root.tokens.textPrimary || "#FFFFFF"
                    border.color: root.tokens.videoCardBackground || "#101010"
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "▼"
                        font.pixelSize: 9
                        color: root.tokens.videoCardBackground || "#101010"
                    }
                }
                MouseArea {
                    id: playheadGrab
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeHorCursor
                    ToolTip.visible: containsMouse && !pressed
                    ToolTip.text: "Drag playhead to scrub the video"
                    ToolTip.delay: 600
                    property real scrubSeconds: 0
                    property real gripOffset: 0
                    onPressed: function(mouse) {
                        scrubSeconds = root.position;
                        // Preserve where inside the 22px handle the user
                        // grabbed it so the needle doesn't jump on drag.
                        gripOffset = mouse.x - width / 2;
                    }
                    onPositionChanged: function(mouse) {
                        if (!pressed)
                            return;
                        const trackX = playheadGrab.mapToItem(
                            frameTrack, mouse.x, mouse.y).x - gripOffset;
                        scrubSeconds = root.seekTimeAtPixel(trackX);
                        root.seekRequested(scrubSeconds);
                    }
                    onReleased: root.seekRequested(scrubSeconds)
                }
            }
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
                text: "Playhead: " + root.timeText(root.keptPosition)
                font.pixelSize: 10
                color: root.tokens.textSecondary || "#aaa"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.timeText(root.keptDuration)
                font.pixelSize: 10
                color: root.tokens.textMuted || "#888"
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.segmentWarning.length > 0
            text: root.segmentWarning
            color: root.tokens.accentSolid || "#28DCA7"
            font.pixelSize: 10
        }
    }
}

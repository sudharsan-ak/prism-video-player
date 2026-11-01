import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Trim selection is independent of the playback seek bar: only the
// range handles change the exported IN/OUT values. The draggable playhead
// scrubs mpv position; export cuts at the exact chosen times.
Rectangle {
    id: root
    height: 280
    color: tokens.panelGlass || "#20202B"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property real duration: 0
    property real timelineZoom: 1.0
    signal quickTrimRequested()
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

    function setZoom(value) {
        timelineZoom = Math.max(1,Math.min(8,value));
        Qt.callLater(function() {
            // Keep the playhead visible without seeking or changing cuts.
            const x=root.position/Math.max(.001,root.duration)*timelineViewport.contentWidth-
                    timelineViewport.width/2;
            timelineViewport.contentX=Math.max(0,Math.min(timelineViewport.contentWidth-timelineViewport.width,x));
        });
    }
    function stepZoom(direction) {
        const stops=[1,1.25,1.5,2,3,4,6,8];
        let i=stops.findIndex(z=>z>=root.timelineZoom-.001);
        if(i<0)i=0;
        setZoom(stops[Math.max(0,Math.min(stops.length-1,i+direction))]);
    }
    component RibbonButton: Button {
        id: action
        font.pixelSize: 10
        padding: 7
        background: Rectangle {
            radius: 6
            color: action.hovered ? (root.tokens.accentTint || "#124B4C")
                                  : (root.tokens.panelGlassStrong || "#113840")
            border.color: root.tokens.panelBorder || "#23515A"
            border.width: 1
        }
        contentItem: Text {
            text: action.text
            font.family: action.font.family
            font.pixelSize: action.font.pixelSize
            color: root.tokens.textPrimary || "#E6F6F6"
            opacity: action.enabled ? 1 : .35
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    function speedText(v) { return Number(v).toFixed(1)+"x"; }

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

        // Row 1: label/back left, transport true-centered, zoom right.
        // An Item with anchored groups (not a RowLayout with equal spacers) so
        // the transport sits at the row's real midpoint regardless of how wide
        // the left and right content blocks are.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 30

            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Text {
                    text: "ADVANCED EDITOR"
                    color: root.tokens.textPrimary || "#E6F6F6"
                    font.pixelSize: 11
                    font.bold: true
                }
                RibbonButton { text: "← Quick Trim"; onClicked: root.quickTrimRequested() }
            }

            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                RibbonButton {
                    text: "↤"
                    onClicked: root.beginningRequested()
                    ToolTip.visible: hovered
                    ToolTip.text: "Beginning of edited timeline"
                }
                Button {
                    id: previewPlay
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    padding: 0
                    onClicked: root.normalPlaybackRequested()
                    background: Rectangle {
                        radius: width/2
                        color: previewPlay.hovered ? Qt.lighter(root.tokens.accentSolid || "#29C7AC",1.1)
                                                    : (root.tokens.accentSolid || "#29C7AC")
                    }
                    contentItem: Item {
                        Text {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            visible: !root.previewPlaying
                            text: "▶"
                            font.pixelSize: 15
                            color: "#071D1D"
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            visible: root.previewPlaying
                            Rectangle { width: 4; height: 12; radius: 1; color: "#071D1D" }
                            Rectangle { width: 4; height: 12; radius: 1; color: "#071D1D" }
                        }
                    }
                }
                Text {
                    text: root.timeText(root.keptPosition) + " / " + root.timeText(root.keptDuration)
                    font.pixelSize: 11
                    color: root.tokens.textPrimary || "#E6F6F6"
                }
            }

            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                RibbonButton {
                    text: "−"
                    enabled: root.timelineZoom > 1.001
                    onClicked: root.stepZoom(-1)
                }
                Text {
                    text: Math.round(root.timelineZoom*100) + "%"
                    color: root.tokens.textSecondary || "#85AAB1"
                    font.pixelSize: 10
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                }
                RibbonButton { text: "+"; enabled: root.timelineZoom < 7.999; onClicked: root.stepZoom(1) }
                RibbonButton { text: "Fit"; onClicked: root.setZoom(1) }
            }
        }

        // Row 1b: segment/export stats, speed and volume, right-aligned.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 5
            Item { Layout.fillWidth: true }

            Rectangle {
                height: 24
                visible: root.width >= 820
                Layout.preferredWidth: visible ? countText.implicitWidth+16 : 0
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
                height: 24
                visible: root.width >= 950
                Layout.preferredWidth: visible ? editedTimeText.implicitWidth+18 : 0
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

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: root.tokens.panelBorder || "#23515A" }

            RibbonButton {
                id: speedButton
                text: "▸  " + root.speedText(root.editSpeed)
                onClicked: {
                    const pos = speedButton.mapToItem(speedPopup.parent, 0, 0);
                    speedPopup.x = Math.max(8, Math.min(speedPopup.parent.width-speedPopup.width-8,
                        pos.x+speedButton.width-speedPopup.width));
                    speedPopup.y = Math.max(8, pos.y-speedPopup.height-8);
                    speedPopup.open();
                }
            }
            RibbonButton {
                id: soundButton
                text: root.audioVolumePercent===0 ? "♫  Sound off  ▾" : "♫  Sound on  ▾"
                onClicked: {
                    const pos = soundButton.mapToItem(volumePopup.parent, 0, 0);
                    volumePopup.x = Math.max(8, Math.min(volumePopup.parent.width-volumePopup.width-8,
                        pos.x+soundButton.width-volumePopup.width));
                    volumePopup.y = Math.max(8, pos.y-volumePopup.height-8);
                    volumePopup.open();
                }
            }
        }

        // Compact advanced editing, actions are grouped beneath the timeline.
        Flickable {
            id: timelineViewport
            Layout.fillWidth: true
            Layout.preferredHeight: 127
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width,width*root.timelineZoom)
            contentHeight: 116
            ScrollBar.horizontal: ScrollBar { policy: root.timelineZoom>1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
            WheelHandler {
                target: null
                onWheel: function(event) {
                    if(root.timelineZoom>1) {
                        const next=timelineViewport.contentX-event.angleDelta.y/120*55;
                        timelineViewport.contentX=Math.max(0,Math.min(timelineViewport.contentWidth-timelineViewport.width,next));
                        event.accepted=true;
                    }
                }
            }
            Item {
                id: timelineContent
                width: timelineViewport.contentWidth
                height: 116
                Item {
                    id: timelineRuler
                    width: parent.width
                    height: 15
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
                    width: parent.width
                    height: 90
                    y: 23

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
                    color: "#3029C7AC"
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
                    preventStealing: true
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
                    preventStealing: true
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

            // Above the filmstrip selection and drag layer so this button
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
                        font.family: gapAction.font.family
                        font.pixelSize: gapAction.font.pixelSize
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
            }
        }

        Flow {
            id: toolbarFlow
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 5

            RibbonButton { text: "✂ Split  S"; enabled: root.endTime-root.startTime >= .05; onClicked: root.splitRequested() }
            RibbonButton { text: "Soft Delete  Del"; enabled: root.canSoftDelete; onClicked: root.softDeleteRequested() }
            RibbonButton { text: "Restore"; enabled: root.selectedRemoved; onClicked: root.restoreSegmentRequested() }
            RibbonButton { text: "Remove Gap"; enabled: root.selectedRemoved && !root.selectedCollapsed; onClicked: root.removeGapRequested(root.selectedSegmentId) }
            RibbonButton { text: "↶"; enabled: root.canUndo; onClicked: root.undoRequested() }
            RibbonButton { text: "↷"; enabled: root.canRedo; onClicked: root.redoRequested() }
            RibbonButton { text: "Reset all"; onClicked: root.resetAllRequested() }

            Rectangle { width: 1; height: 24; color: root.tokens.panelBorder || "#23515A" }

            RibbonButton { text: root.rangePlaying ? "❚❚ Range  R" : "▶ Range  R"; onClicked: root.togglePlaybackRequested() }
            RibbonButton { text: "⇥ Next  J"; enabled: root.hasNextKept; onClicked: root.jumpNextRequested() }
            RibbonButton { text: "Set IN"; onClicked: root.startTimeEdited(Math.min(root.position,root.endTime-.12)) }
            RibbonButton { text: "Set OUT"; onClicked: root.endTimeEdited(Math.max(root.position,root.startTime+.12)) }
            RibbonButton { text: "Reset range"; onClicked: root.resetRequested() }
            RibbonButton { text: "Example"; enabled: root.sourceDuration>1.0; onClicked: root.exampleRequested() }
        }

        Text {
            Layout.fillWidth: true
            visible: root.segmentWarning.length > 0
            text: root.segmentWarning
            color: root.tokens.accentSolid || "#28DCA7"
            font.pixelSize: 10
        }
    }

    Popup {
        id: speedPopup
        parent: Overlay.overlay
        modal: false
        focus: true
        width: 93
        height: 184
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 7
            color: root.tokens.panelGlassStrong || "#1B1D2A"
            border.color: root.tokens.panelBorder || "#23515A"
        }
        contentItem: ColumnLayout {
            spacing: 1
            Repeater {
                model: [0.25,0.5,1,1.5,2]
                Button {
                    required property real modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    text: root.speedText(modelData)
                    onClicked: { root.speedEdited(modelData); speedPopup.close(); }
                    background: Rectangle {
                        radius: 4
                        color: Math.abs(root.editSpeed-modelData)<.001 ?
                            (root.tokens.accentTint || "#2E274D") : "transparent"
                    }
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        color: Math.abs(root.editSpeed-modelData)<.001 ?
                            (root.tokens.accentSolid || "#29C7AC") : (root.tokens.textPrimary || "#E6F6F6")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Popup {
        id: volumePopup
        parent: Overlay.overlay
        modal: false
        focus: true
        width: 268
        height: 225
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 10
            color: root.tokens.panelGlassStrong || "#1B1D2A"
            border.color: root.tokens.panelBorder || "#23515A"
        }
        contentItem: ColumnLayout {
            spacing: 7
            Text { text: "TRIM AUDIO"; font.pixelSize: 10; font.bold: true; color: root.tokens.textSecondary || "#85AAB1" }
            Text { text: "Export volume"; font.pixelSize: 12; font.bold: true; color: root.tokens.textPrimary || "#E6F6F6" }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.audioVolumePercent+"%"
                    font.pixelSize: 22; font.bold: true; color: root.tokens.textPrimary || "#E6F6F6"
                }
                Item { Layout.fillWidth: true }
                Text { text: "Original sound level: 100%"; font.pixelSize: 9; color: root.tokens.textSecondary || "#85AAB1" }
            }
            Slider {
                Layout.fillWidth: true
                from: 0; to: 100; stepSize: 1
                value: root.audioVolumePercent
                onMoved: root.audioVolumeEdited(Math.round(value))
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "0% · No sound"; font.pixelSize: 9; color: root.tokens.textSecondary || "#85AAB1" }
                Item { Layout.fillWidth: true }
                Text { text: "100% · Original"; font.pixelSize: 9; color: root.tokens.textSecondary || "#85AAB1" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: [25,50,75,100]
                    RibbonButton {
                        required property int modelData
                        Layout.fillWidth: true
                        text: modelData+"%"
                        onClicked: root.audioVolumeEdited(modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    id: muteControl
                    text: root.audioVolumePercent===0 ? "Unmute audio" : "Mute audio"
                    font.pixelSize: 10
                    onClicked: root.audioVolumeEdited(root.audioVolumePercent===0 ?
                        Math.max(1,root.lastAudibleVolume) : 0)
                    background: Item {}
                    contentItem: Text {
                        text: muteControl.text
                        font.family: muteControl.font.family
                        font.pixelSize: muteControl.font.pixelSize
                        color: root.tokens.accentSolid || "#29C7AC"
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    id: resetVolume
                    text: "Reset to 100%"
                    font.pixelSize: 10
                    onClicked: root.audioVolumeEdited(100)
                    background: Item {}
                    contentItem: Text {
                        text: resetVolume.text
                        font.family: resetVolume.font.family
                        font.pixelSize: resetVolume.font.pixelSize
                        color: root.tokens.textPrimary || "#E6F6F6"
                    }
                }
            }
        }
    }
}

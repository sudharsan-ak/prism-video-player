import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Three-row compact Quick Trim, matching the approved screenshot.
// IN/OUT grips change trim times; seeking and the playhead stay independent.
Rectangle {
    id: root
    color: tokens.panelGlass || "#151821"
    border.color: tokens.panelBorder || "#303040"
    border.width: 1
    property var tokens: themeController.tokens
    property real duration: 0
    property real startTime: 0
    property real endTime: 0
    property real position: 0
    property real playbackSpeed: 1
    property int audioVolumePercent: 100
    property int lastAudibleVolume: 100
    property bool playing: false
    property bool sourceIsMp4: false
    property bool advancedCutsExist: false
    readonly property color accent: tokens.accentSolid || "#7958EA"
    readonly property color ink: tokens.textPrimary || "#F4F3FF"
    readonly property color muted: tokens.textSecondary || "#9F9DAF"
    readonly property color line: tokens.panelBorder || "#343447"
    signal startTimeEdited(real seconds)
    signal endTimeEdited(real seconds)
    signal seekRequested(real seconds)
    signal playRequested()
    signal beginningRequested()
    signal speedEdited(real speed)
    signal volumeEdited(int value)
    signal resetRequested()
    signal advancedRequested()
    signal copyRequested()
    signal saveRequested()

    function timeText(v) {
        const n=Math.max(0,Math.floor(v||0)), h=Math.floor(n/3600);
        const m=Math.floor(n%3600/60), s=n%60;
        const p=n=>String(n).padStart(2,"0");
        return h ? h+":"+p(m)+":"+p(s) : m+":"+p(s);
    }
    function seekAt(x) {
        return Math.max(0,Math.min(duration,x/Math.max(1,filmstrip.width)*duration));
    }
    function speedText(v) { return Number(v).toFixed(1)+"x"; }

    component TrimButton: Button {
        id: btn
        font.pixelSize: 11
        padding: 7
        implicitHeight: 27
        background: Rectangle {
            radius: 6
            color: btn.hovered ? (root.tokens.accentTint||"#282335") : "transparent"
            border.color: root.line
            border.width: 1
        }
        contentItem: Text {
            text: btn.text
            font.family: btn.font.family
            font.pixelSize: btn.font.pixelSize
            font.bold: btn.font.bold
            color: root.ink
            opacity: btn.enabled ? 1 : .35
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 10
        anchors.bottomMargin: 9
        spacing: 7

        // Row 1: label/back left, transport centered, stats + speed + sound right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 9
            Text { text: "QUICK TRIM"; font.pixelSize: 11; font.bold: true; color: root.ink }

            Item { Layout.fillWidth: true }

            TrimButton {
                text: "↤"
                onClicked: root.beginningRequested()
                ToolTip.visible: hovered
                ToolTip.text: "Back to trim start"
            }
            Button {
                id: playButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                padding: 0
                onClicked: root.playRequested()
                ToolTip.visible: hovered
                ToolTip.text: root.playing ? "Pause" : "Play trim"
                background: Rectangle {
                    radius: width/2
                    color: playButton.hovered ? Qt.lighter(root.accent,1.14) : root.accent
                }
                contentItem: Item {
                    Text {
                        visible: !root.playing
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        text: "▶"
                        color: root.tokens.videoCardBackground || "#0B0B14"
                        font.pixelSize: 15
                    }
                    Row {
                        visible: root.playing
                        anchors.centerIn: parent
                        spacing: 3
                        Rectangle { width: 4; height: 12; radius: 1; color: root.tokens.videoCardBackground || "#0B0B14" }
                        Rectangle { width: 4; height: 12; radius: 1; color: root.tokens.videoCardBackground || "#0B0B14" }
                    }
                }
            }
            Text {
                text: root.timeText(root.position)+" / "+root.timeText(root.duration)
                font.pixelSize: 11; color: root.ink
            }

            Item { Layout.fillWidth: true }

            Text { text: "IN"; font.pixelSize: 10; color: root.muted }
            Text { text: root.timeText(root.startTime); font.pixelSize: 11; font.bold: true; color: root.ink }
            Text { text: "OUT"; font.pixelSize: 10; color: root.muted }
            Text { text: root.timeText(root.endTime); font.pixelSize: 11; font.bold: true; color: root.ink }
            Text { text: "SELECTED"; visible: root.width>=950; font.pixelSize: 10; color: root.muted }
            Text {
                text: root.timeText(root.endTime-root.startTime)
                visible: root.width>=950; font.pixelSize: 11; font.bold: true; color: root.ink
            }
            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: root.line }
            TrimButton {
                id: speedButton
                text: "▸  "+root.speedText(root.playbackSpeed)
                onClicked: {
                    const pos = speedButton.mapToItem(speedPopup.parent, 0, 0);
                    speedPopup.x = Math.max(8, Math.min(speedPopup.parent.width-speedPopup.width-8,
                        pos.x+speedButton.width-speedPopup.width));
                    speedPopup.y = Math.max(8, pos.y-speedPopup.height-8);
                    speedPopup.open();
                }
            }
            TrimButton {
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

        // Row 2: single 42px filmstrip, source thumbnail selection and needle.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Rectangle {
                id: filmstrip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 42
                radius: 6
                clip: true
                color: root.tokens.videoCardBackground || "#292A38"
                border.color: root.line
                border.width: 1
                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: 16
                        Item {
                            width: filmstrip.width/16
                            height: filmstrip.height
                            clip: true
                            Rectangle { anchors.fill: parent; color: index%2 ? "#313143" : "#272938" }
                            Image {
                                anchors.fill: parent
                                property var frames: videoThumbnailController.frames
                                source: frames.length ? frames[Math.min(index,frames.length-1)] : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { root.seekRequested(root.seekAt(mouse.x)); }
                }
                Rectangle {
                    width: root.startTime/Math.max(.001,root.duration)*parent.width
                    height: parent.height
                    color: "#B40A0C17"
                }
                Rectangle {
                    x: root.endTime/Math.max(.001,root.duration)*parent.width
                    width: parent.width-x
                    height: parent.height
                    color: "#B40A0C17"
                }
                Rectangle {
                    x: root.startTime/Math.max(.001,root.duration)*parent.width
                    width: Math.max(0,(root.endTime-root.startTime)/Math.max(.001,root.duration)*parent.width)
                    height: parent.height
                    color: Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.22)
                    border.color: root.accent
                    border.width: 1
                }
                Rectangle {
                    x: root.position/Math.max(.001,root.duration)*parent.width-1
                    width: 2; height: parent.height
                    color: root.ink
                    visible: root.duration>0
                }
            }
            Rectangle {
                id: inGrip
                width: 9; height: filmstrip.height; radius: 2; z: 4
                x: Math.max(filmstrip.x,Math.min(filmstrip.x+filmstrip.width-width,
                    filmstrip.x+root.startTime/Math.max(.001,root.duration)*filmstrip.width-width/2))
                y: filmstrip.y
                color: root.accent
                Text { anchors.centerIn: parent; text: "I"; font.pixelSize: 8; font.bold: true; color: "#0B0B14" }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if(pressed) root.startTimeEdited(root.seekAt(mapToItem(filmstrip,mouse.x,mouse.y).x));
                    }
                }
            }
            Rectangle {
                id: outGrip
                width: 9; height: filmstrip.height; radius: 2; z: 5
                x: Math.max(filmstrip.x,Math.min(filmstrip.x+filmstrip.width-width,
                    filmstrip.x+root.endTime/Math.max(.001,root.duration)*filmstrip.width-width/2))
                y: filmstrip.y
                color: root.accent
                Text { anchors.centerIn: parent; text: "II"; font.pixelSize: 8; font.bold: true; color: "#0B0B14" }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if(pressed) root.endTimeEdited(root.seekAt(mapToItem(filmstrip,mouse.x,mouse.y).x));
                    }
                }
            }
            Item {
                id: playhead
                width: 14; height: 50; z: 3
                x: Math.max(0,Math.min(filmstrip.width-width,
                    filmstrip.x+root.position/Math.max(.001,root.duration)*filmstrip.width-width/2))
                y: filmstrip.y-5
                visible: root.duration>0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7; width: 2; height: parent.height-7; color: root.ink
                }
                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "▼"; font.pixelSize: 10; color: root.ink
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if(pressed) root.seekRequested(root.seekAt(mapToItem(filmstrip,mouse.x,mouse.y).x));
                    }
                }
            }
        }

        // Row 3: reset left, Advanced / copy / overwrite right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 7
            Button {
                id: resetButton
                text: "Reset Trim"
                font.pixelSize: 11
                onClicked: root.resetRequested()
                background: Item {}
                contentItem: Text {
                    text: resetButton.text
                    font.family: resetButton.font.family
                    font.pixelSize: resetButton.font.pixelSize
                    color: root.muted
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Advanced cuts preserved"
                visible: root.advancedCutsExist && root.width>=1160
                font.pixelSize: 10
                color: root.muted
            }
            Button {
                id: advancedButton
                text: "Advanced Editor ↗"
                font.pixelSize: 11
                onClicked: root.advancedRequested()
                background: Item {}
                contentItem: Text {
                    text: advancedButton.text
                    font.family: advancedButton.font.family
                    font.pixelSize: advancedButton.font.pixelSize
                    color: root.muted
                    verticalAlignment: Text.AlignVCenter
                }
            }
            TrimButton {
                text: "Save as Copy"
                enabled: root.duration>0 && root.endTime-root.startTime>=.1
                onClicked: root.copyRequested()
            }
            TrimButton {
                id: saveButton
                text: "Save"
                enabled: root.sourceIsMp4 && root.endTime-root.startTime>=.1
                onClicked: root.saveRequested()
                ToolTip.visible: hovered && !root.sourceIsMp4
                ToolTip.text: "Overwrite is available only for MP4. Use Save as Copy."
                background: Rectangle {
                    radius: 6
                    color: saveButton.enabled ? root.accent : (root.tokens.panelGlassStrong||"#282335")
                }
                contentItem: Text {
                    text: saveButton.text
                    // Second QML font fix from the Windows build feedback.
                    font.family: saveButton.font.family
                    font.pixelSize: saveButton.font.pixelSize
                    font.bold: true
                    color: saveButton.enabled ? "#0B0B14" : root.muted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
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
            color: root.tokens.panelGlassStrong||"#1B1D2A"
            border.color: root.line
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
                        color: Math.abs(root.playbackSpeed-modelData)<.001 ?
                            (root.tokens.accentTint||"#2E274D") : "transparent"
                    }
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        color: Math.abs(root.playbackSpeed-modelData)<.001 ? root.accent : root.ink
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
            color: root.tokens.panelGlassStrong||"#1B1D2A"
            border.color: root.line
        }
        contentItem: ColumnLayout {
            spacing: 7
            Text { text: "TRIM AUDIO"; font.pixelSize: 10; font.bold: true; color: root.muted }
            Text { text: "Export volume"; font.pixelSize: 12; font.bold: true; color: root.ink }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.audioVolumePercent+"%"
                    font.pixelSize: 22; font.bold: true; color: root.ink
                }
                Item { Layout.fillWidth: true }
                Text { text: "Original sound level: 100%"; font.pixelSize: 9; color: root.muted }
            }
            Slider {
                Layout.fillWidth: true
                from: 0; to: 100; stepSize: 1
                value: root.audioVolumePercent
                onMoved: root.volumeEdited(Math.round(value))
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "0% · No sound"; font.pixelSize: 9; color: root.muted }
                Item { Layout.fillWidth: true }
                Text { text: "100% · Original"; font.pixelSize: 9; color: root.muted }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: [25,50,75,100]
                    TrimButton {
                        required property int modelData
                        Layout.fillWidth: true
                        text: modelData+"%"
                        onClicked: root.volumeEdited(modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    id: muteControl
                    text: root.audioVolumePercent===0 ? "Unmute audio" : "Mute audio"
                    font.pixelSize: 10
                    onClicked: root.volumeEdited(root.audioVolumePercent===0 ?
                        Math.max(1,root.lastAudibleVolume) : 0)
                    background: Item {}
                    contentItem: Text {
                        text: muteControl.text
                        font.family: muteControl.font.family
                        font.pixelSize: muteControl.font.pixelSize
                        color: root.accent
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    id: resetVolume
                    text: "Reset to 100%"
                    font.pixelSize: 10
                    onClicked: root.volumeEdited(100)
                    background: Item {}
                    contentItem: Text {
                        text: resetVolume.text
                        font.family: resetVolume.font.family
                        font.pixelSize: resetVolume.font.pixelSize
                        color: root.ink
                    }
                }
            }
        }
    }
}

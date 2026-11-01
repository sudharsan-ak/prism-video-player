import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Simple IN/OUT trimming. No advanced segment model affects Quick Trim exports.
Rectangle {
    id: root
    color: tokens.panelGlass || "#08252D"
    border.color: tokens.panelBorder || "#23515A"
    border.width: 1
    property var tokens: themeController.tokens
    property real duration: 0
    property real startTime: 0
    property real endTime: 0
    property real position: 0
    property bool playing: false
    property bool audioMuted: false
    property bool sourceIsMp4: false
    property bool advancedCutsExist: false
    signal startTimeEdited(real seconds)
    signal endTimeEdited(real seconds)
    signal seekRequested(real seconds)
    signal playRequested()
    signal beginningRequested()
    signal muteRequested()
    signal resetRequested()
    signal advancedRequested()
    signal copyRequested()
    signal saveRequested()

    function timeText(t) {
        const n = Math.max(0,Math.floor(t || 0));
        const m = Math.floor(n/60), s = n%60;
        return (m>=60 ? Math.floor(m/60)+":" + String(m%60).padStart(2,"0") : m) +
            ":" + String(s).padStart(2,"0");
    }
    function seekAt(x) {
        return Math.max(0,Math.min(duration,x/Math.max(1,filmstrip.width)*duration));
    }

    component TrimButton: Button {
        id: btn
        font.pixelSize: 11
        padding: 9
        background: Rectangle {
            radius: 7
            color: btn.down || btn.hovered ? (root.tokens.accentTint || "#124B4C")
                                            : (root.tokens.panelGlassStrong || "#113840")
            border.color: root.tokens.panelBorder || "#23515A"
            border.width: 1
        }
        contentItem: Text {
            text: btn.text
            font: btn.font
            font.bold: true
            color: root.tokens.textPrimary || "#E6F6F6"
            opacity: btn.enabled ? 1 : .4
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 13
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 11
            Text {
                text: "QUICK TRIM"
                font.bold: true
                font.pixelSize: 12
                color: root.tokens.textPrimary || "#FFFFFF"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "IN " + root.timeText(root.startTime) +
                      "     OUT " + root.timeText(root.endTime) +
                      "     SELECTED " + root.timeText(root.endTime-root.startTime)
                font.pixelSize: 11
                color: root.tokens.accentSolid || "#29C7AC"
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            TrimButton { text: "↤"; onClicked: root.beginningRequested() }
            TrimButton { text: root.playing ? "❚❚" : "▶"; onClicked: root.playRequested() }
            Text {
                text: root.timeText(root.position) + " / " + root.timeText(root.duration)
                font.pixelSize: 11
                color: root.tokens.textSecondary || "#85AAB1"
            }
            TrimButton { text: root.audioMuted ? "🔇" : "🔊"; onClicked: root.muteRequested() }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 91
            Rectangle {
                id: filmstrip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 70
                radius: 7
                clip: true
                color: root.tokens.videoCardBackground || "#12171A"
                border.width: 1
                border.color: root.tokens.panelBorder || "#23515A"
                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: 16
                        Item {
                            width: filmstrip.width/16
                            height: filmstrip.height
                            Rectangle { anchors.fill: parent; color: index%2===0 ? "#263038" : "#31383D" }
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
                    x: 0
                    width: Math.max(0,root.startTime/Math.max(.001,root.duration))*parent.width
                    height: parent.height
                    color: "#A800090C"
                }
                Rectangle {
                    x: root.endTime/Math.max(.001,root.duration)*parent.width
                    width: parent.width-x
                    height: parent.height
                    color: "#A800090C"
                }
                Rectangle {
                    x: root.startTime/Math.max(.001,root.duration)*parent.width
                    width: (root.endTime-root.startTime)/Math.max(.001,root.duration)*parent.width
                    height: parent.height
                    color: "#2429C7AC"
                    border.color: root.tokens.accentSolid || "#29C7AC"
                    border.width: 2
                }
                Rectangle {
                    x: root.position/Math.max(.001,root.duration)*parent.width-1
                    y: -1
                    width: 2
                    height: parent.height+2
                    color: root.tokens.textPrimary || "#FFFFFF"
                }
            }
            Rectangle {
                id: inGrip
                width: 13; height: filmstrip.height; radius: 3
                x: Math.max(0,Math.min(filmstrip.width-width,
                    filmstrip.x + root.startTime/Math.max(.001,root.duration)*filmstrip.width-width/2))
                y: filmstrip.y
                color: root.tokens.accentSolid || "#29C7AC"
                z: 4
                Text { anchors.centerIn: parent; text: "Ⅰ"; color: "#06171D"; font.pixelSize: 11 }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if (pressed) root.startTimeEdited(root.seekAt(
                            mapToItem(filmstrip,mouse.x,mouse.y).x));
                    }
                }
            }
            Rectangle {
                id: outGrip
                width: 13; height: filmstrip.height; radius: 3
                x: Math.max(0,Math.min(filmstrip.width-width,
                    filmstrip.x + root.endTime/Math.max(.001,root.duration)*filmstrip.width-width/2))
                y: filmstrip.y
                color: root.tokens.accentSolid || "#29C7AC"
                z: 5
                Text { anchors.centerIn: parent; text: "Ⅱ"; color: "#06171D"; font.pixelSize: 11 }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPositionChanged: function(mouse) {
                        if (pressed) root.endTimeEdited(root.seekAt(
                            mapToItem(filmstrip,mouse.x,mouse.y).x));
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7
            TrimButton {
                text: "Reset Trim"
                onClicked: root.resetRequested()
            }
            Item { Layout.fillWidth: true }
            TrimButton {
                text: "Advanced Editor  ↗"
                onClicked: root.advancedRequested()
            }
            TrimButton {
                text: "Save as Copy"
                enabled: root.duration > 0 && root.endTime-root.startTime >= .1
                onClicked: root.copyRequested()
            }
            TrimButton {
                id: saveButton
                text: "Save"
                enabled: root.sourceIsMp4 && root.endTime-root.startTime >= .1
                onClicked: root.saveRequested()
                ToolTip.visible: hovered && !root.sourceIsMp4
                ToolTip.text: "Overwrite is supported only for MP4 sources. Use Save as Copy."
                background: Rectangle {
                    radius: 7
                    color: saveButton.enabled ? (root.tokens.accentSolid || "#29C7AC")
                                              : (root.tokens.panelGlassStrong || "#113840")
                }
                contentItem: Text {
                    text: saveButton.text
                    font: saveButton.font
                    font.bold: true
                    color: saveButton.enabled ? "#071D1D" : (root.tokens.textMuted || "#638C96")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: root.advancedCutsExist
            text: "Advanced cuts are preserved when switching modes but not applied to Quick Trim saves."
            font.pixelSize: 10
            color: root.tokens.textSecondary || "#85AAB1"
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The crop rectangle is edited directly over the video, not in a dialog.
// Values are percentages of the frame after rotation; both are exported.
ColumnLayout {
    id: root
    property var tokens: themeController.tokens
    property bool cropActive: false
    property real cropX: 0
    property real cropY: 0
    property real cropWidth: 1
    property real cropHeight: 1
    property int quarterTurns: 0
    readonly property bool isCropped: cropX > 0.0001 || cropY > 0.0001 ||
        cropWidth < 0.9999 || cropHeight < 0.9999
    signal cropModeToggled()
    signal cropResetRequested()
    signal cropPresetRequested(string preset)

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Button {
            id: cropToggle
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            enabled: exportQueue.canQueue
            text: root.cropActive ? "Hide crop guides" : "Crop frame"
            font.pixelSize: 11
            font.bold: true
            onClicked: root.cropModeToggled()
            background: Rectangle {
                radius: 8
                color: root.cropActive ? (root.tokens.accentTint || "#203A29")
                                       : (root.tokens.panelGlassStrong || "#242331")
                border.color: root.cropActive ? (root.tokens.accentSolid || "#25EA78")
                                               : (root.tokens.panelBorder || "#444")
            }
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: root.tokens.textPrimary || "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        Button {
            id: resetCrop
            Layout.preferredWidth: 61
            Layout.preferredHeight: 36
            enabled: exportQueue.canQueue && root.isCropped
            text: "Reset"
            font.pixelSize: 11
            onClicked: root.cropResetRequested()
            background: Rectangle {
                radius: 8
                color: root.tokens.panelGlassStrong || "#242331"
                border.color: root.tokens.panelBorder || "#444"
            }
            contentItem: Text {
                text: parent.text
                font: parent.font
                opacity: parent.enabled ? 1 : 0.5
                color: root.tokens.textPrimary || "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: root.cropActive
        text: "Drag inside the frame to move; drag corners to resize."
        font.pixelSize: 10
        color: root.tokens.textSecondary || "#AAA"
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: ["Full", "1:1", "16:9", "9:16"]
            Button {
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                enabled: exportQueue.canQueue
                text: modelData
                font.pixelSize: 10
                onClicked: root.cropPresetRequested(modelData)
                background: Rectangle {
                    radius: 6
                    color: root.tokens.panelGlassStrong || "#242331"
                    border.color: root.tokens.panelBorder || "#444"
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.isCropped
            ? "Crop: " + Math.round(root.cropWidth * 100) + "% × " +
              Math.round(root.cropHeight * 100) + "% of the rotated frame"
            : "Crop: Full frame"
        font.pixelSize: 10
        color: root.tokens.textSecondary || "#AAA"
        wrapMode: Text.WordWrap
    }

}

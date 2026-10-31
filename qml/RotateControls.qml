import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A separate rotation section so Crop and Rotate collapse independently.
ColumnLayout {
    id: root
    property var tokens: themeController.tokens
    property int quarterTurns: 0
    signal rotationRequested(int turns)
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: [0, 90, 180, 270]
            Button {
                id: rotationButton
                required property int modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                enabled: exportQueue.canQueue
                text: modelData + "°"
                font.pixelSize: 11
                onClicked: root.rotationRequested(modelData / 90)
                background: Rectangle {
                    radius: 7
                    color: root.quarterTurns * 90 === rotationButton.modelData
                        ? (root.tokens.accentTint || "#203A29")
                        : (root.tokens.panelGlassStrong || "#242331")
                    border.color: root.quarterTurns * 90 === rotationButton.modelData
                        ? (root.tokens.accentSolid || "#25EA78")
                        : (root.tokens.panelBorder || "#444")
                }
                contentItem: Text {
                    text: rotationButton.text
                    font: rotationButton.font
                    color: root.tokens.textPrimary || "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Rotation is shown live and applied before cropping on export."
        font.pixelSize: 10
        color: root.tokens.textSecondary || "#AAA"
        wrapMode: Text.WordWrap
    }
}

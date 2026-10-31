import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Reusable themed view. Jobs continue when Edit mode is closed;
// the list is available both inside Edit and from the top-bar Queue.
Rectangle {
    id: root
    property var tokens: themeController.tokens
    property bool compact: false
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.compact ? 0 : 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "EXPORT QUEUE"
                font.pixelSize: 11
                font.bold: true
                color: root.tokens.textPrimary || "#fff"
                Layout.fillWidth: true
            }
            Text {
                text: exportQueue.waitingCount + " waiting"
                color: root.tokens.textSecondary || "#aaa"
                font.pixelSize: 10
            }
            Button {
                visible: exportQueue.jobs.length > 0
                text: "Clear finished"
                font.pixelSize: 10
                flat: true
                onClicked: exportQueue.clearFinished()
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: root.tokens.accentSolid || "#A89BFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            visible: exportQueue.jobs.length === 0
            Layout.fillWidth: true
            text: "Nothing queued yet. Add an MP4 or GIF export from Edit."
            color: root.tokens.textSecondary || "#aaa"
            wrapMode: Text.WordWrap
            font.pixelSize: 11
        }

        ScrollView {
            visible: exportQueue.jobs.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Column {
                width: parent.width
                spacing: 7
                Repeater {
                    model: exportQueue.jobs
                    Rectangle {
                        id: jobCard
                        required property var modelData
                        width: parent.width
                        implicitHeight: jobColumn.implicitHeight + 14
                        color: root.tokens.panelGlassStrong || "#242331"
                        radius: 7
                        border.color: root.tokens.panelBorder || "#444"

                        ColumnLayout {
                            id: jobColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: jobCard.modelData.name
                                    elide: Text.ElideMiddle
                                    color: root.tokens.textPrimary || "#fff"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Text {
                                    text: jobCard.modelData.format + " · " + jobCard.modelData.speed + "x"
                                    color: root.tokens.textSecondary || "#aaa"
                                    font.pixelSize: 10
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: jobCard.modelData.status +
                                        (jobCard.modelData.status === "Running"
                                            ? " · " + Math.round(jobCard.modelData.progress * 100) + "%"
                                            : "")
                                    color: jobCard.modelData.status === "Failed"
                                        ? "#E36B6B" : (root.tokens.textSecondary || "#aaa")
                                    font.pixelSize: 10
                                }
                                Button {
                                    visible: jobCard.modelData.status === "Queued" ||
                                             jobCard.modelData.status === "Running"
                                    text: "Cancel"
                                    font.pixelSize: 10
                                    flat: true
                                    onClicked: exportQueue.cancelJob(jobCard.modelData.id)
                                    contentItem: Text {
                                        text: parent.text
                                        font: parent.font
                                        color: root.tokens.accentSolid || "#A89BFF"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                            ProgressBar {
                                id: jobProgress
                                Layout.fillWidth: true
                                visible: jobCard.modelData.status === "Running"
                                value: jobCard.modelData.progress
                                background: Rectangle {
                                    implicitHeight: 5
                                    radius: 3
                                    color: root.tokens.seekTrack || "#444"
                                }
                                contentItem: Item {
                                    implicitHeight: 5
                                    Rectangle {
                                        height: 5
                                        radius: 3
                                        width: parent.width * jobProgress.position
                                        color: root.tokens.accentSolid || "#A89BFF"
                                    }
                                }
                            }

                            Text {
                                visible: jobCard.modelData.error !== ""
                                Layout.fillWidth: true
                                text: jobCard.modelData.error
                                wrapMode: Text.WrapAnywhere
                                color: "#E36B6B"
                                font.pixelSize: 10
                            }
                            Text {
                                visible: !root.compact &&
                                         jobCard.modelData.status === "Completed"
                                Layout.fillWidth: true
                                text: jobCard.modelData.output
                                elide: Text.ElideMiddle
                                color: root.tokens.textMuted || "#aaa"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}

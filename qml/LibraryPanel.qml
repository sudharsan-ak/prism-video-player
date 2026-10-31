import QtQuick
import QtQuick.Controls

// Collapsible left-side panel (PHASE1_PLAN_QT.md section 6.5). Closed
// by default, toggled from the top bar's Library button, not nested
// in a menu. Queue/Recent tabs, "+ Add files to queue" which queues
// and auto-plays if the queue was empty.
Rectangle {
    id: root
    width: 278
    color: tokens.panelGlass || "#fff"
    border.color: tokens.panelBorder || "transparent"
    border.width: 1

    property var tokens: themeController.tokens
    property var mpv: null
    signal addFilesRequested()

    property int activeTab: 0 // 0 = queue, 1 = recent

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        Row {
            width: parent.width
            height: 30
            spacing: 4

            Rectangle {
                width: (parent.width - 4) / 2
                height: parent.height
                radius: 8
                color: root.activeTab === 0 ? (root.tokens.panelGlassStrong || "#fff") : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "Queue"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.tokens.textPrimary || "#000"
                }
                MouseArea { anchors.fill: parent; onClicked: root.activeTab = 0 }
            }
            Rectangle {
                width: (parent.width - 4) / 2
                height: parent.height
                radius: 8
                color: root.activeTab === 1 ? (root.tokens.panelGlassStrong || "#fff") : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "Recent"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.tokens.textPrimary || "#000"
                }
                MouseArea { anchors.fill: parent; onClicked: root.activeTab = 1 }
            }
        }

        Rectangle {
            width: parent.width
            height: 36
            radius: 10
            color: root.tokens.accentTint || "transparent"
            border.color: root.tokens.accentSolid || "#D97757"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "+ Add files to queue"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.tokens.accentSolid || "#D97757"
            }
            MouseArea { anchors.fill: parent; onClicked: root.addFilesRequested() }
        }

        Row {
            visible: root.activeTab === 0
            width: parent.width
            Text {
                text: "UP NEXT  " + playerController.playlist.length
                font.pixelSize: 9
                font.weight: Font.Black
                color: root.tokens.textMuted || "#888"
                width: parent.width - 50
            }
            Text {
                text: "Clear"
                visible: playerController.playlist.length > 0
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: root.tokens.accentSolid || "#888"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: playerController.clearQueue()
                }
            }
        }

        ListView {
            visible: root.activeTab === 0
            width: parent.width
            height: root.height - 160
            clip: true
            model: playerController.playlist
            delegate: Rectangle {
                width: ListView.view.width
                height: 44
                radius: 10
                color: index === playerController.currentIndex ? (root.tokens.accentTint || "transparent") : "transparent"
                border.color: index === playerController.currentIndex ? (root.tokens.accentSolid || "transparent") : "transparent"
                border.width: 1

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    spacing: 2
                    Text {
                        text: modelData.split(/[\\\/]/).pop()
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.tokens.textPrimary || "#000"
                        elide: Text.ElideRight
                        width: 190
                    }
                    Text {
                        text: index === playerController.currentIndex ? "NOW PLAYING" : "LOCAL FILE"
                        font.pixelSize: 9
                        color: index === playerController.currentIndex ? (root.tokens.accentSolid || "#888") : (root.tokens.textMuted || "#888")
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: playerController.playAtIndex(index)
                }
                // Per-item remove, separate from the row's own play
                // click - stopPropagation keeps a removal tap from also
                // triggering playAtIndex() on the row underneath it.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 10
                    text: "✕"
                    font.pixelSize: 11
                    color: root.tokens.textMuted || "#888"
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: function(mouse) {
                            mouse.accepted = true;
                            playerController.removeFromQueue(index);
                        }
                    }
                }
            }
        }

        Row {
            visible: root.activeTab === 1
            width: parent.width
            Text {
                text: "RECENTLY OPENED  " + settingsStore.recentFiles.length
                font.pixelSize: 9
                font.weight: Font.Black
                color: root.tokens.textMuted || "#888"
                width: parent.width - 50
            }
            Text {
                text: "Clear"
                visible: settingsStore.recentFiles.length > 0
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: root.tokens.accentSolid || "#888"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: settingsStore.clearRecent()
                }
            }
        }

        ListView {
            visible: root.activeTab === 1
            width: parent.width
            height: root.height - 160
            clip: true
            model: settingsStore.recentFiles
            delegate: Rectangle {
                width: ListView.view.width
                height: 44
                color: "transparent"
                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    spacing: 2
                    Text {
                        text: modelData.split(/[\\\/]/).pop()
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.tokens.textPrimary || "#000"
                        elide: Text.ElideRight
                        width: 190
                    }
                    Text {
                        text: "OPEN AGAIN"
                        font.pixelSize: 9
                        color: root.tokens.textMuted || "#888"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: playerController.playRecent(modelData)
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 10
                    text: "✕"
                    font.pixelSize: 11
                    color: root.tokens.textMuted || "#888"
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: function(mouse) {
                            mouse.accepted = true;
                            settingsStore.removeRecent(modelData);
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10
        text: "Private by design — no account, no ads, no streaming."
        font.pixelSize: 9
        color: root.tokens.textMuted || "#888"
        wrapMode: Text.WordWrap
        width: parent.width - 28
        horizontalAlignment: Text.AlignHCenter
    }
}

import QtQuick
import QtQuick.Controls

Menu {
    id: root
    signal openFilesRequested()
    signal addFolderRequested()

    MenuItem {
        text: "Open files..."
        onTriggered: root.openFilesRequested()
    }
    MenuItem {
        text: "Add folder to queue..."
        onTriggered: root.addFolderRequested()
    }
    Menu {
        title: "Open recent"
        enabled: settingsStore.recentFiles.length > 0
        Repeater {
            model: settingsStore.recentFiles
            MenuItem {
                text: modelData.split(/[\\\/]/).pop()
                onTriggered: playerController.playRecent(modelData)
            }
        }
    }
    MenuSeparator {}
    MenuItem {
        text: "Clear queue"
        onTriggered: playerController.clearQueue()
    }
    MenuItem {
        text: "Save frame as image... (coming in Phase 2)"
        enabled: false
    }
    MenuSeparator {}
    MenuItem {
        text: "Exit"
        onTriggered: Qt.quit()
    }
}

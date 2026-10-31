import QtQuick
import QtQuick.Controls

Menu {
    id: root
    property var mpv: null

    Menu {
        id: bookmarksMenu
        title: "Bookmarks"
        enabled: playerController.bookmarks.length > 0
        // Each bookmark gets a paired "Remove" entry directly under it.
        // A plain Repeater's delegate must be exactly one MenuItem to
        // land correctly in a Menu's content list, so two entries per
        // bookmark need Instantiator (which inserts each object itself)
        // rather than Repeater (which would nest them under one nested
        // Column item instead of flattening into the menu).
        Instantiator {
            model: playerController.bookmarks
            delegate: MenuItem {
                text: modelData.label
                onTriggered: playerController.seekToBookmark(modelData.time)
            }
            onObjectAdded: function(index, object) { bookmarksMenu.insertItem(index * 2, object); }
            onObjectRemoved: function(index, object) { bookmarksMenu.removeItem(object); }
        }
        Instantiator {
            model: playerController.bookmarks
            delegate: MenuItem {
                text: "    ✕ Remove"
                onTriggered: playerController.removeBookmarkAt(modelData.time)
            }
            onObjectAdded: function(index, object) { bookmarksMenu.insertItem(index * 2 + 1, object); }
            onObjectRemoved: function(index, object) { bookmarksMenu.removeItem(object); }
        }
    }
    MenuSeparator {}
    MenuItem {
        text: "Open captures folder"
        onTriggered: Qt.openUrlExternally("file:///" + settingsStore.capturesFolderPath())
    }
    MenuItem {
        text: "Keyboard shortcuts"
        onTriggered: prismWindow.toggleShortcutsPanel()
    }
}

import QtQuick
import QtQuick.Controls

Menu {
    id: root

    Menu {
        title: "Theme (" + currentThemeDisplayName() + ")"
        function currentThemeDisplayName() {
            for (let i = 0; i < themeController.availableThemes.length; i++) {
                if (themeController.availableThemes[i].id === themeController.activeThemeName)
                    return themeController.availableThemes[i].displayName;
            }
            return "";
        }
        Repeater {
            model: themeController.availableThemes
            MenuItem {
                text: modelData.displayName
                checkable: true
                checked: themeController.activeThemeName === modelData.id
                onTriggered: themeController.activeThemeName = modelData.id
            }
        }
    }
    MenuSeparator {}
    Menu {
        title: "Seek bar thickness"
        MenuItem {
            text: "Slim (4px)"
            checkable: true
            checked: settingsStore.seekBarThickness === "slim"
            onTriggered: settingsStore.seekBarThickness = "slim"
        }
        MenuItem {
            text: "Medium (6px)"
            checkable: true
            checked: settingsStore.seekBarThickness === "medium"
            onTriggered: settingsStore.seekBarThickness = "medium"
        }
        MenuItem {
            text: "Thick (8px)"
            checkable: true
            checked: settingsStore.seekBarThickness === "thick"
            onTriggered: settingsStore.seekBarThickness = "thick"
        }
    }
    MenuSeparator {}
    MenuItem {
        text: "Keep backup when replacing original"
        checkable: true
        checked: settingsStore.keepBackupOnReplace
        onTriggered: settingsStore.keepBackupOnReplace = !settingsStore.keepBackupOnReplace
    }
    MenuSeparator {}
    MenuItem {
        text: "Resume playback position"
        checkable: true
        checked: settingsStore.resumeEnabled
        onTriggered: settingsStore.resumeEnabled = !settingsStore.resumeEnabled
    }
    MenuItem {
        text: "Default volume: " + settingsStore.volume + "%"
        enabled: false
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
    MenuSeparator {}
    MenuItem {
        text: "About Prism"
        onTriggered: prismWindow.toggleAboutPanel()
    }
}

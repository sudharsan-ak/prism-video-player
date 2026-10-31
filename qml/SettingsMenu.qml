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

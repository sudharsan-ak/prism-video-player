import QtQuick
import QtQuick.Controls

// Groups Tools + Settings under one top-bar entry, same consolidation
// rationale as PlaybackMenu.
Menu {
    id: root
    property var mpv: null

    ToolsMenu {
        title: "Tools"
        mpv: root.mpv
    }
    SettingsMenu {
        title: "Settings"
    }
}

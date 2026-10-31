import QtQuick
import QtQuick.Controls

Menu {
    id: root
    property var mpv: null
    signal loadSubtitleRequested()

    Menu {
        title: "Subtitle track"
        MenuItem { text: "Off"; onTriggered: playerController.setSubtitleTrack("no") }
        Repeater {
            model: mpv ? mpv.trackList.filter(function(t) { return t.type === "sub"; }) : []
            MenuItem {
                text: modelData.title || modelData.lang || ("Track " + modelData.id)
                checkable: true
                checked: modelData.selected === true
                onTriggered: playerController.setSubtitleTrack(modelData.id)
            }
        }
    }
    MenuItem {
        text: "Off"
        onTriggered: playerController.setSubtitleTrack("no")
    }
    MenuItem {
        text: "Load external subtitle file..."
        onTriggered: root.loadSubtitleRequested()
    }
    MenuSeparator {}
    Menu {
        title: "Subtitle delay (sync)"
        MenuItem { text: "-0.5s"; onTriggered: playerController.setSubtitleDelay(-0.5) }
        MenuItem { text: "Reset"; onTriggered: playerController.setSubtitleDelay(0) }
        MenuItem { text: "+0.5s"; onTriggered: playerController.setSubtitleDelay(0.5) }
    }
    MenuItem {
        text: "Font/size/position... (coming in Phase 2)"
        enabled: false
    }
}

import QtQuick
import QtQuick.Controls

Menu {
    id: root
    property var mpv: null

    Menu {
        title: "Audio track"
        MenuItem { text: "No audio"; onTriggered: playerController.setAudioTrack("no") }
        Repeater {
            model: mpv ? mpv.trackList.filter(function(t) { return t.type === "audio"; }) : []
            MenuItem {
                text: modelData.title || modelData.lang || ("Track " + modelData.id)
                checkable: true
                checked: modelData.selected === true
                onTriggered: playerController.setAudioTrack(modelData.id)
            }
        }
    }
    MenuSeparator {}
    MenuItem {
        text: "Volume up"
        onTriggered: playerController.setVolume((mpv ? mpv.volume : 0) + 5)
    }
    MenuItem {
        text: "Volume down"
        onTriggered: playerController.setVolume((mpv ? mpv.volume : 0) - 5)
    }
    MenuItem {
        text: "Mute"
        onTriggered: playerController.setVolume((mpv && mpv.volume > 0) ? 0 : 80)
    }
    MenuSeparator {}
    Menu {
        title: "Audio delay (sync)"
        MenuItem { text: "-0.5s"; onTriggered: playerController.setAudioDelay(-0.5) }
        MenuItem { text: "Reset"; onTriggered: playerController.setAudioDelay(0) }
        MenuItem { text: "+0.5s"; onTriggered: playerController.setAudioDelay(0.5) }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Window

// Right-click context menu over the video. This is the feature that
// drove the architecture pivot away from Electron (PHASE1_PLAN_QT.md
// section 5.1) - mirrors the most-used subset of the top-bar menus.
Menu {
    id: root

    property var mpv: null

    MenuItem {
        text: mpv && mpv.paused ? "Play" : "Pause"
        onTriggered: playerController.togglePause()
    }
    MenuItem {
        text: "Stop"
        onTriggered: playerController.setPaused(true)
    }
    MenuSeparator {}
    MenuItem {
        text: "Previous file"
        onTriggered: playerController.previous()
    }
    MenuItem {
        text: "Next file"
        onTriggered: playerController.next()
    }
    MenuItem {
        text: "Skip back 10s"
        onTriggered: playerController.skip(-10)
    }
    MenuItem {
        text: "Skip forward 10s"
        onTriggered: playerController.skip(10)
    }
    MenuSeparator {}
    Menu {
        title: "Audio track"
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
    Menu {
        title: "Subtitle track"
        MenuItem {
            text: "Off"
            onTriggered: playerController.setSubtitleTrack("no")
        }
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
    Menu {
        title: "Aspect ratio"
        MenuItem { text: "Original / Auto"; onTriggered: playerController.setAspectRatio("no") }
        MenuItem { text: "16:9"; onTriggered: playerController.setAspectRatio("16:9") }
        MenuItem { text: "4:3"; onTriggered: playerController.setAspectRatio("4:3") }
        MenuItem { text: "21:9"; onTriggered: playerController.setAspectRatio("21:9") }
        MenuItem { text: "1:1"; onTriggered: playerController.setAspectRatio("1:1") }
    }
    MenuSeparator {}
    MenuItem {
        text: "Take screenshot"
        onTriggered: playerController.takeScreenshot()
    }
    MenuItem {
        text: prismWindow.visibility === Window.FullScreen ? "Exit fullscreen" : "Fullscreen"
        onTriggered: prismWindow.toggleFullscreen()
    }
    MenuSeparator {}
    MenuItem {
        text: "Settings"
        onTriggered: prismWindow.openSettingsMenu()
    }
}

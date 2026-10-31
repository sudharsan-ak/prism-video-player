import QtQuick
import QtQuick.Controls

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
    MenuSeparator {}
    MenuItem {
        text: "Skip back 10s"
        onTriggered: playerController.skip(-10)
    }
    MenuItem {
        text: "Skip forward 10s"
        onTriggered: playerController.skip(10)
    }
    MenuItem {
        text: "Skip back 30s"
        onTriggered: playerController.skip(-30)
    }
    MenuItem {
        text: "Skip forward 30s"
        onTriggered: playerController.skip(30)
    }
    MenuItem {
        text: "Frame step back"
        onTriggered: playerController.frameStepBackward()
    }
    MenuItem {
        text: "Frame step forward"
        onTriggered: playerController.frameStepForward()
    }
    MenuSeparator {}
    MenuItem {
        text: "Set A-B loop points"
        onTriggered: {
            if (mpv && mpv.getProperty("ab-loop-a") === "no")
                playerController.setLoopA();
            else
                playerController.setLoopB();
        }
    }
    MenuItem {
        text: "Bookmark this moment"
        onTriggered: playerController.addBookmarkHere()
    }
}

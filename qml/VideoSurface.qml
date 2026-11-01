import QtQuick
import Prism

// Wraps MpvObject and adds the interactions a native child-window
// embed could never give the Electron build: hover for the fullscreen
// auto-hide overlay, right-click for the context menu (the feature
// that drove the whole stack pivot). Because MpvObject is a normal
// QQuickFramebufferObject here, these are ordinary MouseArea signals,
// not a fight with a separate native HWND.
//
// Click behavior (locked after user testing): a single click never
// touches playback - it only shows/hides the fullscreen floating
// control bar. Only a double click toggles play/pause. Fullscreen
// itself is never triggered by clicking the video at all - only by F,
// Escape (exit-only), or the explicit fullscreen button - a double
// click used to also toggle fullscreen, which fought with "double
// click = play/pause" and felt accidental.
Item {
    id: root

    property alias mpv: mpvObject
    signal contextMenuRequested(point pos)
    signal mouseActivity()
    signal singleClicked()
    signal doubleClicked()

    MpvObject {
        id: mpvObject
        anchors.fill: parent
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onPositionChanged: root.mouseActivity()
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.contextMenuRequested(Qt.point(mouse.x, mouse.y));
            } else {
                root.singleClicked();
            }
        }
        onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton)
                root.doubleClicked();
        }
        onWheel: function(wheel) {
            const delta = wheel.angleDelta.y > 0 ? 5 : -5;
            playerController.setVolume(mpvObject.volume + delta);
        }
    }
}

import QtQuick
import QtQuick.Controls

Menu {
    id: root
    property var mpv: null

    MenuItem {
        text: mpv ? ("Track: " + mpv.videoWidth + "x" + mpv.videoHeight) : "Track"
        enabled: false
    }
    Menu {
        title: "Aspect ratio"
        MenuItem { text: "Original / Auto"; onTriggered: playerController.setAspectRatio("no") }
        MenuItem { text: "16:9 Widescreen"; onTriggered: playerController.setAspectRatio("16:9") }
        MenuItem { text: "4:3 Classic"; onTriggered: playerController.setAspectRatio("4:3") }
        MenuItem { text: "21:9 Cinema"; onTriggered: playerController.setAspectRatio("21:9") }
        MenuItem { text: "1:1 Square"; onTriggered: playerController.setAspectRatio("1:1") }
    }
    Menu {
        title: "Rotate"
        MenuItem { text: "0°"; onTriggered: playerController.setRotation(0) }
        MenuItem { text: "90°"; onTriggered: playerController.setRotation(1) }
        MenuItem { text: "180°"; onTriggered: playerController.setRotation(2) }
        MenuItem { text: "270°"; onTriggered: playerController.setRotation(3) }
    }
    Menu {
        title: "Brightness / Contrast / Saturation / Gamma"
        onAboutToShow: prismWindow.openAdjustments()
        MenuItem {
            text: "Open Adjustments panel"
            onTriggered: prismWindow.openAdjustments()
        }
    }
    MenuSeparator {}
    MenuItem {
        text: mpv && mpv.hwdecCurrent ? ("Hardware decode: " + mpv.hwdecCurrent) : "Hardware decode: automatic"
        enabled: false
    }
    MenuSeparator {}
    MenuItem {
        text: "Take screenshot"
        onTriggered: playerController.takeScreenshot()
    }
}

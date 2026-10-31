import QtQuick
import QtQuick.Controls

// Groups Play/Video/Audio/Subtitle under one top-bar entry so the bar
// doesn't eat most of the window width (PHASE1_PLAN_QT.md's original
// 7-menu layout left too little room for the now-playing title at
// normal window widths - user-requested consolidation).
Menu {
    id: root
    property var mpv: null
    signal loadSubtitleRequested()

    PlayMenu {
        title: "Play"
        mpv: root.mpv
    }
    VideoMenu {
        title: "Video"
        mpv: root.mpv
    }
    AudioMenu {
        title: "Audio"
        mpv: root.mpv
    }
    SubtitleMenu {
        title: "Subtitle"
        mpv: root.mpv
        onLoadSubtitleRequested: root.loadSubtitleRequested()
    }
}

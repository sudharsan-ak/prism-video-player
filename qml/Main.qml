import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Prism

ApplicationWindow {
    id: prismWindow
    width: 1280
    height: 800
    minimumWidth: 700
    minimumHeight: 450
    visible: true
    title: "Prism"
    flags: Qt.Window | Qt.FramelessWindowHint
    // Taskbar/Alt-Tab/Explorer icon comes from the .rc-embedded icon.ico
    // compiled into the exe (CMakeLists.txt) - ApplicationWindow has no
    // settable "icon" property in this Qt version to also set here.

    property var tokens: themeController.tokens
    property bool libraryOpen: false
    property bool adjustmentsOpen: false
    property bool fullscreenMode: false

    color: "transparent"

    function toggleFullscreen() {
        if (visibility === Window.FullScreen) {
            visibility = Window.Windowed;
            fullscreenMode = false;
        } else {
            visibility = Window.FullScreen;
            fullscreenMode = true;
        }
        // Re-claim focus so Escape/Space/etc keep working regardless of
        // what had focus before the switch (e.g. a panel control) -
        // fullscreen's Escape-to-exit was silently dead without this.
        globalShortcuts.forceActiveFocus();
    }

    function openAdjustments() {
        adjustmentsOpen = true;
    }

    function toggleAdjustments() {
        adjustmentsOpen = !adjustmentsOpen;
    }

    function openSettingsMenu() {
        // Context menu's Settings shortcut opens the Adjustments panel,
        // the closest equivalent to a Settings surface reachable from
        // over the video (PHASE1_PLAN_QT.md section 6.3).
        adjustmentsOpen = true;
    }

    function toggleShortcutsPanel() {
        shortcutsOverlay.visible = !shortcutsOverlay.visible;
    }

    function toggleAboutPanel() {
        aboutOverlay.visible = !aboutOverlay.visible;
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: tokens.backgroundGradient ? tokens.backgroundGradient[0] : "#F5F1E6" }
            GradientStop { position: 0.55; color: tokens.backgroundGradient ? tokens.backgroundGradient[1] : "#EDE6D6" }
            GradientStop { position: 1.0; color: tokens.backgroundGradient ? tokens.backgroundGradient[2] : "#E6DCC6" }
        }
    }

    ColumnLayout {
        id: windowedChrome
        anchors.fill: parent
        spacing: 0
        visible: !prismWindow.fullscreenMode

        TopBar {
            id: topBar
            Layout.fillWidth: true
            mpv: videoSurface.mpv
            libraryOpen: prismWindow.libraryOpen
            adjustmentsOpen: prismWindow.adjustmentsOpen
            onLibraryToggled: prismWindow.libraryOpen = !prismWindow.libraryOpen
            onAdjustmentsToggled: prismWindow.adjustmentsOpen = !prismWindow.adjustmentsOpen
            onOpenFilesRequested: openFilesDialog.open()
            onAddFolderRequested: addFolderDialog.open()
            onLoadSubtitleRequested: subtitleDialog.open()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            LibraryPanel {
                id: libraryPanel
                Layout.fillHeight: true
                visible: prismWindow.libraryOpen
                mpv: videoSurface.mpv
                onAddFilesRequested: addToQueueDialog.open()
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    id: videoStage
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.fill: parent
                        radius: 0
                        color: tokens.videoCardBackground || "#141210"
                        clip: true

                        Item {
                            id: windowedVideoSlot
                            anchors.fill: parent
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !videoSurface.mpv || !videoSurface.mpv.mediaPath
                            text: "Open a video to get started"
                            font.pixelSize: 13
                            color: "#555"
                        }
                    }
                }

                BottomControlBar {
                    id: bottomBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    mpv: videoSurface.mpv
                }
            }

            AdjustmentsPanel {
                id: adjustmentsPanel
                Layout.fillHeight: true
                visible: prismWindow.adjustmentsOpen
                mpv: videoSurface.mpv
                onCloseRequested: prismWindow.adjustmentsOpen = false
            }
        }
    }

    Item {
        id: fullscreenChrome
        anchors.fill: parent
        visible: prismWindow.fullscreenMode

        Item {
            id: fullscreenVideoSlot
            anchors.fill: parent
        }

        FullscreenOverlay {
            id: fullscreenOverlay
            anchors.fill: parent
            mpv: videoSurface.mpv
        }
    }

    // One MpvObject for the whole app's life: toggling fullscreen moves
    // this single video item between the windowed and fullscreen slot
    // instead of creating a second engine instance, so playback state
    // never resets (PHASE1_PLAN_QT.md section 6.8).
    VideoSurface {
        id: videoSurface
        anchors.fill: parent
        parent: windowedVideoSlot
        onContextMenuRequested: function(pos) {
            contextMenu.mpv = videoSurface.mpv;
            contextMenu.popup(videoSurface, pos.x, pos.y);
        }
        onMouseActivity: {
            if (prismWindow.fullscreenMode)
                fullscreenOverlay.notifyActivity();
        }
        onSingleClicked: {
            // Single click never touches playback - only toggles the
            // floating overlay's visibility in fullscreen, per explicit
            // feedback that clicking the video was wrongly firing
            // play/pause. Double click (VideoSurface.onDoubleClicked)
            // is the only click gesture that plays/pauses.
            if (prismWindow.fullscreenMode)
                fullscreenOverlay.toggleVisibility();
        }
    }

    onFullscreenModeChanged: {
        videoSurface.parent = fullscreenMode ? fullscreenVideoSlot : windowedVideoSlot;
        videoSurface.anchors.fill = videoSurface.parent;
    }

    ContextMenu {
        id: contextMenu
    }

    // Visible feedback for PlayerController.notify() (screenshot saved,
    // screenshot failed, invalid file, etc.) - these previously only
    // reached console.log, which is invisible in a release build with
    // no console, so a failure (like the screenshot bug) looked like
    // the button silently did nothing.
    Rectangle {
        id: toast
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 170
        width: toastText.implicitWidth + 32
        height: 36
        radius: 10
        opacity: 0
        z: 50
        color: toastIsError ? "#D64545" : (tokens.panelGlassStrong || "#222")
        property bool toastIsError: false

        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
        }

        Timer {
            id: toastTimer
            interval: 2800
            onTriggered: toast.opacity = 0
        }

        function show(message, isError) {
            toastText.text = message;
            toastIsError = isError;
            opacity = 1;
            toastTimer.restart();
        }
    }

    Connections {
        target: playerController
        function onNotify(message, type) {
            toast.show(message, type === "error");
        }
    }

    OsdOverlay {
        id: osd
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 120
    }

    Rectangle {
        id: shortcutsOverlay
        visible: false
        anchors.centerIn: parent
        width: 420
        height: 260
        radius: 14
        color: tokens.panelGlassStrong || "#fff"
        border.color: tokens.panelBorder || "#ccc"
        border.width: 1
        z: 100

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 8

            Text { text: "Keyboard shortcuts"; font.pixelSize: 14; font.weight: Font.Bold; color: tokens.textPrimary }
            Text { text: "Space: Play / Pause"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Left / Right: ±5 sec"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Shift + Left / Right: ±30 sec"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "Up / Down: Volume"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "F: Fullscreen"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "O: Open files"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "[ / ]: Playback speed"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "S: Screenshot"; font.pixelSize: 11; color: tokens.textSecondary }
            Text { text: "B: Bookmark"; font.pixelSize: 11; color: tokens.textSecondary }
        }
        MouseArea { anchors.fill: parent; onClicked: {} }
    }
    MouseArea {
        anchors.fill: parent
        visible: shortcutsOverlay.visible || aboutOverlay.visible
        onClicked: { shortcutsOverlay.visible = false; aboutOverlay.visible = false; }
    }

    Rectangle {
        id: aboutOverlay
        visible: false
        anchors.centerIn: parent
        width: 340
        height: 160
        radius: 14
        color: tokens.panelGlassStrong || "#fff"
        border.color: tokens.panelBorder || "#ccc"
        border.width: 1
        z: 100

        Column {
            anchors.centerIn: parent
            spacing: 8
            Text { text: "Prism"; font.pixelSize: 16; font.weight: Font.Black; color: tokens.textPrimary; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "A local-only, offline-first media player."; font.pixelSize: 11; color: tokens.textSecondary; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "No accounts. No ads. No tracking."; font.pixelSize: 11; color: tokens.textMuted; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    FileDialog {
        id: openFilesDialog
        title: "Open local video or audio"
        fileMode: FileDialog.OpenFiles
        onAccepted: playerController.openFiles(selectedFiles.map(u => u.toString().replace("file:///", "")))
    }

    FileDialog {
        id: addToQueueDialog
        title: "Add files to queue"
        fileMode: FileDialog.OpenFiles
        onAccepted: playerController.addToQueue(selectedFiles.map(u => u.toString().replace("file:///", "")))
    }

    FolderDialog {
        id: addFolderDialog
        title: "Add folder to queue"
        onAccepted: {
            // Folder expansion to individual files happens through the
            // controller once a user selects one; Prism keeps file
            // picking local-only, matching PHASE1_PLAN_QT.md section 5.3.
        }
    }

    FileDialog {
        id: subtitleDialog
        title: "Load subtitles"
        nameFilters: ["Subtitle files (*.srt *.ass *.ssa *.vtt *.sub *.idx *.smi)"]
        onAccepted: playerController.loadExternalSubtitle(selectedFile.toString().replace("file:///", ""))
    }

    Connections {
        target: videoSurface.mpv
        function onVolumeChanged() {
            osd.show("Volume", videoSurface.mpv.volume, 100);
        }
    }

    Item {
        id: globalShortcuts
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
        if (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier)
            return;

        switch (event.key) {
        case Qt.Key_Space:
            playerController.togglePause();
            event.accepted = true;
            break;
        case Qt.Key_Left:
            playerController.skip(event.modifiers & Qt.ShiftModifier ? -30 : -5);
            event.accepted = true;
            break;
        case Qt.Key_Right:
            playerController.skip(event.modifiers & Qt.ShiftModifier ? 30 : 5);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            playerController.setVolume((videoSurface.mpv ? videoSurface.mpv.volume : 0) + 5);
            event.accepted = true;
            break;
        case Qt.Key_Down:
            playerController.setVolume((videoSurface.mpv ? videoSurface.mpv.volume : 0) - 5);
            event.accepted = true;
            break;
        case Qt.Key_F:
            prismWindow.toggleFullscreen();
            event.accepted = true;
            break;
        case Qt.Key_O:
            openFilesDialog.open();
            event.accepted = true;
            break;
        case Qt.Key_S:
            playerController.takeScreenshot();
            event.accepted = true;
            break;
        case Qt.Key_B:
            playerController.addBookmarkHere();
            event.accepted = true;
            break;
        case Qt.Key_BracketLeft:
            playerController.setSpeed((videoSurface.mpv ? videoSurface.mpv.speed : 1) - 0.1);
            event.accepted = true;
            break;
        case Qt.Key_BracketRight:
            playerController.setSpeed((videoSurface.mpv ? videoSurface.mpv.speed : 1) + 0.1);
            event.accepted = true;
            break;
        case Qt.Key_Escape:
            if (prismWindow.fullscreenMode) {
                prismWindow.toggleFullscreen();
                event.accepted = true;
            }
            break;
        }
        }
    }

    Component.onCompleted: {
        playerController.mpv = Qt.binding(function() { return videoSurface.mpv; });
        globalShortcuts.forceActiveFocus();
    }

    // Windows' "Open with" / double-click-to-open passes the file path
    // as a plain command-line argument. Opening it synchronously in
    // Component.onCompleted ran before the window's OpenGL/FBO render
    // surface had actually been realized, so mpv decoded and played
    // audio correctly but had nothing valid to render into - picture
    // stayed black while audio and the seek bar worked fine. A short
    // deferred start (after the first frame or two) gives the render
    // context time to exist before loadfile fires. File -> Open always
    // happened well after the window was already fully up, which is
    // why that path never showed the bug.
    Timer {
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            const args = Qt.application.arguments;
            if (args.length > 1) {
                playerController.openFiles([args[args.length - 1]]);
            }
        }
    }

    // Qt.FramelessWindowHint removes the native OS resize border along
    // with the title bar, so without this the window could only be
    // resized via the maximize button - there was no way to drag an
    // edge/corner to a custom size at all. Window.startSystemResize()
    // hands off to the OS's own resize behavior (correct cursor,
    // correct snapping), the same mechanism startSystemMove() already
    // uses for dragging via the top bar. Hidden once maximized or
    // fullscreen, where resizing doesn't apply.
    Item {
        anchors.fill: parent
        visible: prismWindow.visibility !== Window.Maximized && !prismWindow.fullscreenMode
        z: 1000

        readonly property int edge: 6

        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.edge
            cursorShape: Qt.SizeHorCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.edge
            cursorShape: Qt.SizeHorCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge)
        }
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.edge
            cursorShape: Qt.SizeVerCursor
            onPressed: prismWindow.startSystemResize(Qt.TopEdge)
        }
        MouseArea {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.edge
            cursorShape: Qt.SizeVerCursor
            onPressed: prismWindow.startSystemResize(Qt.BottomEdge)
        }
        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeFDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge | Qt.TopEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.top: parent.top
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeBDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge | Qt.TopEdge)
        }
        MouseArea {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeBDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
        }
        MouseArea {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.edge * 2
            height: parent.edge * 2
            cursorShape: Qt.SizeFDiagCursor
            onPressed: prismWindow.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
